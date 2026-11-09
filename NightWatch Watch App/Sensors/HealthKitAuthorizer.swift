import Foundation
import HealthKit

/// Asks for, and keeps track of, permission to use Health data.
///
/// Privacy note: HealthKit never tells an app whether the user allowed it to
/// READ a data type (so an app can't learn that you hid something). We can only
/// see whether the user allowed us to WRITE workouts, which is what monitoring
/// mode needs, so that is what `status` reports.
@MainActor
final class HealthKitAuthorizer: ObservableObject {

    enum Status: Equatable {
        case checking
        /// This device has no Health data store.
        case unavailable
        /// We haven't asked yet, or we added new data types since we last asked.
        case needsPermission
        /// Workout permission granted, so monitoring mode can run.
        case ready
        /// The user turned workout permission off, so monitoring can't run.
        case workoutDenied
        case failed(String)
    }

    @Published private(set) var status: Status = .checking

    /// Shared by the whole app. Apple recommends one per app.
    let healthStore = HKHealthStore()

    /// Data Night Watch WRITES. A workout session (monitoring mode) needs
    /// permission to save workouts, even though we discard ours at the end.
    private let typesToShare: Set<HKSampleType> = [
        HKObjectType.workoutType(),
    ]

    /// Data Night Watch READS.
    private let typesToRead: Set<HKObjectType> = [
        HKQuantityType(.heartRate),          // live heart rate during monitoring
        HKQuantityType(.restingHeartRate),   // Apple's daily resting HR, to sanity-check calibration
        HKObjectType.electrocardiogramType(),// ECG results (read-only, used in a later stage)
        HKObjectType.workoutType(),
    ]

    /// Works out the current status without showing anything to the user.
    func refreshStatus() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            status = .unavailable
            return
        }
        do {
            let request = try await healthStore.statusForAuthorizationRequest(
                toShare: typesToShare, read: typesToRead)
            if request == .shouldRequest {
                status = .needsPermission
                return
            }
        } catch {
            status = .failed(error.localizedDescription)
            return
        }
        switch healthStore.authorizationStatus(for: HKObjectType.workoutType()) {
        case .sharingAuthorized:
            status = .ready
        case .sharingDenied:
            status = .workoutDenied
        case .notDetermined:
            status = .needsPermission
        @unknown default:
            status = .needsPermission
        }
    }

    /// Shows Apple's Health permission sheet on the watch.
    func requestAccess() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            status = .unavailable
            return
        }
        do {
            try await healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead)
            await refreshStatus()
        } catch {
            status = .failed(error.localizedDescription)
        }
    }
}
