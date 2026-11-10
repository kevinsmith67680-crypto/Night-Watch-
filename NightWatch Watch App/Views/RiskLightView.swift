import SwiftUI
import NightWatchCore

/// The traffic light, clearly labelled as temporary prototype rules.
struct RiskLightView: View {
    let assessment: RiskAssessment?

    var body: some View {
        VStack(spacing: 4) {
            Text(SafetyText.temporaryRulesLabel)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Circle()
                    .fill(color)
                    .frame(width: 30, height: 30)
                    .overlay(Circle().stroke(.white.opacity(0.3), lineWidth: 1))
                Text(title)
                    .font(.headline)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }

            if let assessment, showsLevel(assessment) {
                Text(SafetyText.message(for: assessment.level))
                    .font(.footnote)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ForEach(assessment.reasons, id: \.self) { reason in
                    Text(reason)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Text("Waiting for heart rate…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(8)
        .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
    }

    /// Grey "no data" only while nothing is known. A raised level stays visible
    /// even if heart rate drops out, with a note in the reasons.
    private func showsLevel(_ assessment: RiskAssessment) -> Bool {
        assessment.hasRecentHeartRate || assessment.level > .green
    }

    private var color: Color {
        guard let assessment, showsLevel(assessment) else { return .gray }
        switch assessment.level {
        case .green: return .green
        case .amber: return .orange
        case .red: return .red
        }
    }

    private var title: String {
        guard let assessment, showsLevel(assessment) else { return "No data yet" }
        return SafetyText.title(for: assessment.level)
    }
}
