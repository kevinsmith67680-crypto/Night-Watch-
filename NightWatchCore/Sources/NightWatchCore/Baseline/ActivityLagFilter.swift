import Foundation

/// Models the delay between moving and your heart rate responding.
///
/// When you start dancing, heart rate climbs over about half a minute. When you
/// stop, it falls back more slowly, over a few minutes. Comparing heart rate with
/// INSTANT activity would therefore make a person who has just stopped dancing
/// look like "heart rate high while still", which is exactly the red-flag pattern.
/// So expected heart rate is calculated from this LAGGED activity instead.
///
/// It is a first-order lag ("exponential smoothing") with two time constants:
/// `riseSeconds` while activity goes up and `fallSeconds` while it comes down.
/// After one time constant the lagged value has covered about 63% of a change.
public struct ActivityLagFilter: Sendable {
    public let riseSeconds: Double
    public let fallSeconds: Double
    /// The current lagged activity, in g. Nil until the first update.
    public private(set) var value: Double?
    private var lastTime: Timestamp?

    public init(riseSeconds: Double, fallSeconds: Double) {
        precondition(riseSeconds > 0 && fallSeconds > 0, "Lag times must be positive")
        self.riseSeconds = riseSeconds
        self.fallSeconds = fallSeconds
    }

    /// Feeds in the latest activity and returns the new lagged activity.
    public mutating func update(activity: Double, at time: Timestamp) -> Double {
        guard let current = value, let last = lastTime else {
            value = activity          // first reading: start from it
            lastTime = time
            return activity
        }
        let elapsed = max(0, time - last)
        let timeConstant = activity > current ? riseSeconds : fallSeconds
        let fraction = 1 - exp(-elapsed / timeConstant)   // how far to move towards the new value
        let next = current + fraction * (activity - current)
        value = next
        lastTime = time
        return next
    }

    /// Forget the history, e.g. at the start of a new recording.
    public mutating func reset() {
        value = nil
        lastTime = nil
    }
}
