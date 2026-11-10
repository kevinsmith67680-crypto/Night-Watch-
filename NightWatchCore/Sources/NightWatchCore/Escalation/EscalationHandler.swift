import Foundation

/// What happens when the risk level changes.
///
/// This prototype ONLY alerts the wearer on their own watch (a tap on the
/// wrist). It never calls or messages anyone. A future version could add a
/// handler that OFFERS to call 999 or a friend, but it must always ask the
/// user to confirm, never act on its own.
public protocol EscalationHandler: AnyObject {
    /// Called after every window while monitoring.
    /// - previousLevel: the level before this window, or nil for the first one.
    func handle(_ assessment: RiskAssessment, previousLevel: RiskLevel?)
}

/// Does nothing. Useful for tests and the simulator.
public final class NoEscalation: EscalationHandler {
    public init() {}
    public func handle(_ assessment: RiskAssessment, previousLevel: RiskLevel?) {}
}
