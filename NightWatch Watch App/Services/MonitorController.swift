import Foundation
import Combine
import NightWatchCore

/// Runs monitoring mode and publishes what the screen needs to show.
///
/// It owns the sensor sources and receives every reading they produce.
/// Step 2: heart rate only. Later steps pass each reading on to the pipeline
/// (feature extraction → Kalman filter → risk engine) from `receive(_:)`.
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

    var isActive: Bool {
        state == .starting || state == .running
    }

    private let heartRateSource: WorkoutHeartRateSource

    init() {
        heartRateSource = WorkoutHeartRateSource(healthStore: Health.store)

        // The source promises to call these on the main thread, so we can
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
        heartRateSource.stop()
    }

    // MARK: - Events

    private func receive(_ reading: SensorReading) {
        switch reading {
        case .heartRate(let sample):
            latestHeartRate = sample
            heartRateCount += 1
        case .motion, .wristTemperature:
            break   // added in later steps
        }
    }

    private func sessionDidStart() {
        state = .running
        startDate = Date()
    }

    private func sessionDidEnd() {
        startDate = nil
        if case .failed = state { return }   // keep the error message on screen
        state = .idle
    }
}
