import Foundation

/// Anything that turns each window's results into a traffic-light level.
///
/// `PlaceholderRiskRules` is the temporary version. The IMM filter's
/// "in trouble" probability will become another engine and can be passed into
/// `MonitoringPipeline` without changing anything else.
public protocol RiskEngine: Sendable {
    /// Called once per finished window, in time order.
    mutating func assess(_ result: WindowResult) -> RiskAssessment
    /// Forget all history, e.g. when monitoring restarts.
    mutating func reset()
}
