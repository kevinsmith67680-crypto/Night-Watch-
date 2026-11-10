import Foundation
import Combine
import NightWatchCore

/// Runs monitoring mode and publishes what the screen needs to show.
///
/// It owns the sensor sources, passes every reading into the processing
/// pipeline, and publishes each finished 5-second window.
@MainActor
final class MonitorController: ObservableObject {

    enum State: Equatable {
        case idle
        case starting
        case running
        case stopping
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var latestHeartRate: HeartRateSample?
    /// How many heart-rate readings arrived this session (to check how often they come).
    @Published private(set) var heartRateCount = 0
    @Published private(set) var startDate: Date?
    /// The most recent finished 5-second window.
    @Published private(set) var latestWindow: WindowFeatures?
    @Published private(set) var windowCount = 0
    /// Explains why motion isn't available, e.g. in the simulator.
    @Published private(set) var motionNote: String?

    var isActive: Bool {
        state == .starting || state == .running
    }

    private let config: MonitorConfig
    private let heartRateSource: WorkoutHeartRateSource
    private let motionSource: MotionSource
    private var pipeline: MonitoringPipeline

    init(config: MonitorConfig = .standard) {
        self.config = config
        heartRateSource = WorkoutHeartRateSource(healthStore: Health.store)
        motionSource = MotionSource(sampleRateHz: config.features.motionSampleRateHz)
        pipeline = MonitoringPipeline(config: config)

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

    func start() {
        switch state {
        case .idle, .failed: break
        default: return
        }
        state = .starting
        latestHeartRate = nil
        heartRateCount = 0
        startDate = nil
        latestWindow = nil
        windowCount = 0
        motionNote = nil
        pipeline = MonitoringPipeline(config: config)

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

    // MARK: - Events

    /// Every reading from every sensor comes through here.
    private func receive(_ reading: SensorReading) {
        if case .heartRate(let sample) = reading {
            latestHeartRate = sample
            heartRateCount += 1
        }
        if let window = pipeline.process(reading) {
            publish(window)
        }
    }

    private func publish(_ window: WindowFeatures) {
        latestWindow = window
        windowCount += 1
        // Later steps: Kalman filter, risk engine and CSV logging hook in here.
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
        startDate = nil
        if case .failed = state { return }   // keep the error message on screen
        state = .idle
    }
}
