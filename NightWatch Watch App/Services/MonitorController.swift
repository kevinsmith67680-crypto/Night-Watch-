import Foundation
import Combine
import WatchKit
import NightWatchCore

/// Runs the sensors and publishes what the screens need to show.
///
/// Two modes share the same sensors:
///  • monitoring: each 5-second window goes through the pipeline, which uses
///    your saved baseline to work out expected and excess heart rate;
///  • calibrating: each window is also recorded so a baseline can be learned.
@MainActor
final class MonitorController: ObservableObject {

    /// The one controller for the whole app. Shared so that crash recovery
    /// (which watchOS reports to the app delegate) can reach it.
    static let shared = MonitorController()

    enum State: Equatable {
        case idle
        case starting
        case running
        case stopping
        case failed(String)
    }

    enum Mode: String, Equatable {
        case monitoring
        case calibrating
    }

    /// Small things remembered between launches, for crash recovery.
    private enum Remembered {
        static let activeMode = "nightwatch.activeMode"
        static let lastRiskLevel = "nightwatch.lastRiskLevel"
    }

    // MARK: Live session

    @Published private(set) var state: State = .idle
    @Published private(set) var mode: Mode = .monitoring
    @Published private(set) var latestHeartRate: HeartRateSample?
    /// How many heart-rate readings arrived this session (to check how often they come).
    @Published private(set) var heartRateCount = 0
    @Published private(set) var startDate: Date?
    /// The most recent finished 5-second window.
    @Published private(set) var latestResult: WindowResult?
    @Published private(set) var windowCount = 0
    /// Explains why motion isn't available, e.g. in the simulator.
    @Published private(set) var motionNote: String?
    /// The latest traffic-light verdict (monitoring mode only).
    @Published private(set) var risk: RiskAssessment?
    /// Explains that monitoring was restarted after the app stopped unexpectedly.
    @Published private(set) var recoveryNote: String?

    // MARK: Calibration

    /// Your saved baseline, or nil if you haven't calibrated yet.
    @Published private(set) var baseline: BaselineModel?
    @Published private(set) var calibrationProgress: CalibrationProgress
    @Published private(set) var calibrationMessage: String?
    @Published private(set) var isFitting = false

    var isActive: Bool {
        state == .starting || state == .running
    }

    private let config: MonitorConfig
    private let heartRateSource: WorkoutHeartRateSource
    private let motionSource: MotionSource
    private var pipeline: MonitoringPipeline
    private var calibrator: BaselineCalibrator
    private var unsavedCalibrationWindows = 0
    private let escalation: EscalationHandler
    private let logger = SessionLogger()

    init(config: MonitorConfig = .standard) {
        let savedBaseline = BaselineStore.loadBaseline()
        let calibrator = BaselineCalibrator(config: config, points: BaselineStore.loadCalibrationPoints())

        self.config = config
        self.heartRateSource = WorkoutHeartRateSource(healthStore: Health.store)
        self.motionSource = MotionSource(sampleRateHz: config.features.motionSampleRateHz)
        self.pipeline = MonitoringPipeline(config: config, baseline: savedBaseline)
        self.calibrator = calibrator
        self.calibrationProgress = calibrator.progress
        self.escalation = HapticAlerts(config: config.risk)
        self.baseline = savedBaseline

        // Lets each CSV row record the battery level, to measure real drain.
        WKInterfaceDevice.current().isBatteryMonitoringEnabled = true

        // The sources promise to call these on the main thread, so we can
        // handle them immediately and in order.
        heartRateSource.onRunning = { [weak self] in
            MainActor.assumeIsolated { self?.sessionDidStart() }
        }
        heartRateSource.onEnded = { [weak self] in
            MainActor.assumeIsolated { self?.sessionDidEnd() }
        }
        heartRateSource.onError = { [weak self] error in
            MainActor.assumeIsolated { self?.state = .failed(error.localizedDescription) }
        }
    }

    // MARK: - Buttons

    func start(_ newMode: Mode) {
        switch state {
        case .idle, .failed: break
        default: return
        }
        prepareForSession(newMode)
        recoveryNote = nil
        UserDefaults.standard.set(0, forKey: Remembered.lastRiskLevel)
        logger.start(source: newMode.rawValue)

        do {
            try heartRateSource.start { [weak self] reading in
                MainActor.assumeIsolated { self?.receive(reading) }
            }
        } catch {
            state = .failed(String(describing: error))
            logger.finish()
            UserDefaults.standard.removeObject(forKey: Remembered.activeMode)
        }
    }

    /// Called after watchOS relaunches the app because it stopped unexpectedly
    /// while a session was running. Picks the session back up.
    func recoverActiveSession() {
        switch state {
        case .idle, .failed: break
        default: return   // already running
        }
        let defaults = UserDefaults.standard
        let recoveredMode = Mode(rawValue: defaults.string(forKey: Remembered.activeMode) ?? "") ?? .monitoring
        let previousLevel = RiskLevel(rawValue: defaults.integer(forKey: Remembered.lastRiskLevel)) ?? .green

        prepareForSession(recoveredMode)
        var note = "Night Watch stopped unexpectedly and has restarted. The light needs a few minutes "
            + "of new data before it means anything again."
        if recoveredMode == .monitoring && previousLevel > .green {
            note += " Before it stopped, the light was \(previousLevel.label.uppercased())."
            WKInterfaceDevice.current().play(.notification)
        }
        recoveryNote = note
        logger.start(source: "\(recoveredMode.rawValue)-recovered")

        Task {
            do {
                try await heartRateSource.recover { [weak self] reading in
                    MainActor.assumeIsolated { self?.receive(reading) }
                }
            } catch {
                state = .failed("Couldn't restart after the app stopped: \(error.localizedDescription)")
                logger.finish()
                defaults.removeObject(forKey: Remembered.activeMode)
            }
        }
    }

    func stop() {
        guard isActive else { return }
        state = .stopping
        motionSource.stop()
        heartRateSource.stop()
    }

    /// Calculates the baseline from everything recorded so far and saves it.
    func fitCalibration() {
        guard !isFitting, !isActive else { return }
        isFitting = true
        calibrationMessage = nil
        Task {
            let appleResting = await RestingHeartRateReader.latest(from: Health.store)
            do {
                let result = try calibrator.fit(appleRestingHeartRateBPM: appleResting)
                BaselineStore.save(baseline: result.model)
                baseline = result.model
                calibrationMessage = (["Baseline saved."] + result.warnings).joined(separator: " ")
            } catch {
                calibrationMessage = String(describing: error)
            }
            isFitting = false
        }
    }

    /// Deletes all calibration recordings and the saved baseline.
    func resetCalibration() {
        guard !isActive else { return }
        BaselineStore.deleteAll()
        calibrator = BaselineCalibrator(config: config)
        calibrationProgress = calibrator.progress
        unsavedCalibrationWindows = 0
        baseline = nil
        calibrationMessage = "Calibration deleted."
    }

    // MARK: - Events

    /// Every reading from every sensor comes through here.
    private func receive(_ reading: SensorReading) {
        if case .heartRate(let sample) = reading {
            latestHeartRate = sample
            heartRateCount += 1
        }
        if let result = pipeline.process(reading) {
            publish(result)
        }
    }

    private func publish(_ result: WindowResult) {
        latestResult = result
        windowCount += 1
        logger.append(result, batteryPercent: Self.batteryPercent())

        // Traffic light and wrist tap, while monitoring only.
        if mode == .monitoring, let assessment = result.risk {
            let previousLevel = risk?.level
            risk = assessment
            escalation.handle(assessment, previousLevel: previousLevel)
            if assessment.level != previousLevel {
                UserDefaults.standard.set(assessment.level.rawValue, forKey: Remembered.lastRiskLevel)
            }
        }

        if mode == .calibrating {
            if calibrator.add(result.features) {
                unsavedCalibrationWindows += 1
            }
            calibrationProgress = calibrator.progress
            if unsavedCalibrationWindows >= 12 {   // save about once a minute
                saveCalibrationPoints()
            }
        }
    }

    /// The watch's battery level (0–100), or nil if unknown.
    private static func batteryPercent() -> Double? {
        let level = WKInterfaceDevice.current().batteryLevel
        return level >= 0 ? Double(level) * 100 : nil
    }

    private func saveCalibrationPoints() {
        BaselineStore.save(calibrationPoints: calibrator.points)
        unsavedCalibrationWindows = 0
    }

    /// Resets everything for a new (or recovered) session.
    private func prepareForSession(_ newMode: Mode) {
        mode = newMode
        state = .starting
        latestHeartRate = nil
        heartRateCount = 0
        startDate = nil
        latestResult = nil
        windowCount = 0
        motionNote = nil
        risk = nil
        calibrationMessage = nil
        pipeline = MonitoringPipeline(config: config, baseline: baseline)
        UserDefaults.standard.set(newMode.rawValue, forKey: Remembered.activeMode)
    }

    private func sessionDidStart() {
        state = .running
        startDate = heartRateSource.sessionStartDate ?? Date()
        // Motion starts once the workout session is running, because the
        // session is what keeps it going with the screen off.
        do {
            try motionSource.start { [weak self] reading in
                MainActor.assumeIsolated { self?.receive(reading) }
            }
        } catch {
            motionNote = String(describing: error)
        }
    }

    private func sessionDidEnd() {
        motionSource.stop()
        if let last = pipeline.finish() {
            publish(last)
        }
        if mode == .calibrating {
            saveCalibrationPoints()
        }
        logger.finish()
        UserDefaults.standard.removeObject(forKey: Remembered.activeMode)
        startDate = nil
        if case .failed = state { return }   // keep the error message on screen
        state = .idle
    }
}
