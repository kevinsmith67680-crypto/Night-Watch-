import Foundation

/// Every safety-related sentence the app shows, kept in one place so it is
/// easy to review and so the tests can check it.
///
/// Rules for this wording:
///  • never diagnose, and never say the user is "safe";
///  • never imply that a normal ECG rules out a heart problem;
///  • always point to 999 for emergencies. The app never calls anyone itself.
public enum SafetyText {
    /// Shown on every main screen.
    public static let disclaimer =
        "Prototype — not a medical device. If someone has chest pain, is overheating or having a seizure, call 999."

    public static let green =
        "No unusual pattern detected. This does not mean you are safe."

    public static let amber =
        "Your heart rate is higher than expected for how still you are. "
        + "Rest somewhere cool, sip water, tell someone you're with, "
        + "and take a reading in the ECG app. A normal ECG does not rule out a heart problem."

    public static let red =
        "Strong warning pattern. If you feel unwell, have chest pain, are overheating "
        + "or having a seizure, call 999 now."

    public static func message(for level: RiskLevel) -> String {
        switch level {
        case .green: return green
        case .amber: return amber
        case .red: return red
        }
    }
}
