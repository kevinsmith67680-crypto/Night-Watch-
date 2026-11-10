import Foundation
import Combine
import NightWatchCore

/// Runs the sensors and publishes what the screens need to show.
///
/// Two modes share the same sensors:
///  • monitoring: each 5-second window goes through the pipeline, which uses
///    your saved baseline to work out expected and excess heart rate;
///  • calibrating: each window is also recorded so a baseline can be learned.
@MainActor
final class MonitorController: ObservableObject {

    enum State: Equatable {
        case idle
        case starting
        case running
        case stopping
        case failed(String)
    }

    enum Mode: Equatable {
        case monitoring
        case calibrating
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

        do {
            try heartRateSource.start { [weak self] reading in
                MainActor.assumeIsolated { self?.receive(reading) }
            }
        } catch {
            state = .failed(String(describing: error))
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

        // Traffic light and wrist tap, while monitoring only.
        if mode == .monitoring, let assessment = result.risk {
            let previousLevel = risk?.level
            risk = assessment
            escalation.handle(assessment, previousLevel: previousLevel)
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
        // Step 7: CSV logging hooks in here.
    }

    private func saveCalibrationPoints() {
        BaselineStore.save(calibrationPoints: calibrator.points)
        unsavedCalibrationWindows = 0
    }

    private func sessionDidStart() {
        state = .running
        startDate = Date()
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
        startDate = nil
        if case .failed = state { return }   // keep the error message on screen
        state = .idle
    }
}
