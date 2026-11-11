import Foundation
import HealthKit
import NightWatchCore

/// Monitoring mode's heart-rate input.
///
/// It runs an Apple "workout session". That does two things:
///  1. the watch measures heart rate every few seconds instead of every few minutes;
///  2. watchOS keeps Night Watch running with the screen off. From Step 3 on,
///     the motion sensors rely on this too.
///
/// The workout is DISCARDED when monitoring stops, so nothing is saved as a
/// workout in the Health app.
///
/// All callbacks (`deliver`, `onRunning`, `onEnded`, `onError`) arrive on the
/// main thread.
final class WorkoutHeartRateSource: NSObject, SensorSource {

    let name = "Apple Watch heart rate (workout session)"
    let provides: Set<SensorKind> = [.heartRate]
    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Called once the workout session is running.
    var onRunning: (() -> Void)?
    /// Called once the session has fully ended and been cleaned up.
    var onEnded: (() -> Void)?
    /// Called if the workout session fails, e.g. permission was turned off.
    var onError: ((Error) -> Void)?

    private let healthStore: HKHealthStore
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var deliver: ((SensorReading) -> Void)?
    /// Time of the last reading we passed on, so the same one is never sent twice.
    private var lastSampleDate: Date?

    private let heartRateType = HKQuantityType(.heartRate)
    private let beatsPerMinute = HKUnit.count().unitDivided(by: .minute())

    init(healthStore: HKHealthStore) {
        self.healthStore = healthStore
        super.init()
    }

    /// When the current workout session began (nil if none).
    var sessionStartDate: Date? {
        session?.startDate
    }

    // MARK: - SensorSource

    /// Call on the main thread.
    func start(deliver: @escaping (SensorReading) -> Void) throws {
        guard isAvailable else {
            throw SensorError.unavailable("Health data is not available on this device.")
        }
        guard session == nil else {
            throw SensorError.unavailable("Monitoring is still stopping. Try again in a moment.")
        }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .other
        configuration.locationType = .indoor   // indoor = GPS stays off, saving battery

        let newSession = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
        let newBuilder = newSession.associatedWorkoutBuilder()
        newBuilder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore,
                                                        workoutConfiguration: configuration)
        newSession.delegate = self
        newBuilder.delegate = self

        session = newSession
        builder = newBuilder
        self.deliver = deliver
        lastSampleDate = nil

        let startDate = Date()
        newSession.startActivity(with: startDate)
        newBuilder.beginCollection(withStart: startDate) { [weak self] success, error in
            guard !success else { return }
            DispatchQueue.main.async {
                self?.onError?(error ?? SensorError.unavailable("Heart-rate collection could not start."))
                self?.stop()
            }
        }
    }

    /// Re-attaches to a workout session that was still running when the app
    /// stopped unexpectedly (watchOS relaunches the app and asks it to recover).
    /// Calls `onRunning` if the session is running.
    @MainActor
    func recover(deliver: @escaping (SensorReading) -> Void) async throws {
        guard session == nil else {
            throw SensorError.unavailable("Monitoring is already running.")
        }
        let recovered: HKWorkoutSession = try await withCheckedThrowingContinuation { continuation in
            healthStore.recoverActiveWorkoutSession { session, error in
                if let session {
                    continuation.resume(returning: session)
                } else {
                    continuation.resume(throwing: error ?? SensorError.unavailable("There was no workout session to recover."))
                }
            }
        }
        let recoveredBuilder = recovered.associatedWorkoutBuilder()
        recoveredBuilder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore,
                                                              workoutConfiguration: recovered.workoutConfiguration)
        recovered.delegate = self
        recoveredBuilder.delegate = self

        session = recovered
        builder = recoveredBuilder
        self.deliver = deliver
        lastSampleDate = nil

        if recovered.state == .running {
            onRunning?()
        }
    }

    /// Call on the main thread. `onEnded` is called once everything has shut down.
    func stop() {
        guard let session else { return }
        switch session.state {
        case .notStarted, .prepared:
            finish()                                 // never got going: just tidy up
        case .ended:
            endCollectionAndDiscard(at: Date())      // already ended (e.g. after an error)
        default:
            session.end()                            // the delegate below finishes the job
        }
    }

    // MARK: - Private

    /// Ends data collection, throws the workout away, and resets everything.
    private func endCollectionAndDiscard(at date: Date) {
        guard let builder else {
            finish()
            return
        }
        builder.endCollection(withEnd: date) { [weak self] _, _ in
            builder.discardWorkout()
            DispatchQueue.main.async { self?.finish() }
        }
    }

    /// Must run on the main thread.
    private func finish() {
        session = nil
        builder = nil
        deliver = nil
        lastSampleDate = nil
        onEnded?()
    }
}

// MARK: - Workout session events (arrive on a background thread)

extension WorkoutHeartRateSource: HKWorkoutSessionDelegate {

    func workoutSession(_ workoutSession: HKWorkoutSession,
                        didChangeTo toState: HKWorkoutSessionState,
                        from fromState: HKWorkoutSessionState,
                        date: Date) {
        DispatchQueue.main.async { [weak self] in
            guard let self, workoutSession === self.session else { return }
            switch toState {
            case .running:
                self.onRunning?()
            case .ended:
                self.endCollectionAndDiscard(at: date)
            default:
                break
            }
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self, workoutSession === self.session else { return }
            self.onError?(error)
            self.stop()   // clean up so monitoring can be started again
        }
    }
}

// MARK: - New data from the watch's sensors (arrives on a background thread)

extension WorkoutHeartRateSource: HKLiveWorkoutBuilderDelegate {

    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder,
                        didCollectDataOf collectedTypes: Set<HKSampleType>) {
        guard collectedTypes.contains(heartRateType),
              let statistics = workoutBuilder.statistics(for: heartRateType),
              let quantity = statistics.mostRecentQuantity(),
              let interval = statistics.mostRecentQuantityDateInterval()
        else { return }

        let bpm = quantity.doubleValue(for: beatsPerMinute)
        let sampleDate = interval.end

        DispatchQueue.main.async { [weak self] in
            guard let self, workoutBuilder === self.builder else { return }
            if let last = self.lastSampleDate, sampleDate <= last { return }   // already sent
            self.lastSampleDate = sampleDate
            let sample = HeartRateSample(time: sampleDate.timeIntervalSince1970, bpm: bpm)
            self.deliver?(.heartRate(sample))
        }
    }

    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        // Workout events (pauses, laps) aren't used by Night Watch.
    }
}
