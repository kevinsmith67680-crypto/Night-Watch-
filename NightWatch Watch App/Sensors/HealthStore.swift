import HealthKit

/// One shared connection to the Health database for the whole app.
/// Apple recommends creating a single `HKHealthStore` and reusing it.
enum Health {
    static let store = HKHealthStore()
}
