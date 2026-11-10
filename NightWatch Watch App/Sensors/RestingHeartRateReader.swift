import Foundation
import HealthKit

/// Reads Apple's own daily resting heart rate from Health, used as a sanity
/// check on calibration.
enum RestingHeartRateReader {

    /// The most recent resting heart rate in bpm, or nil if there is none or
    /// access isn't allowed.
    static func latest(from store: HKHealthStore) async -> Double? {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.restingHeartRate))],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 1)
        guard let sample = try? await descriptor.result(for: store).first else { return nil }
        return sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
    }
}
