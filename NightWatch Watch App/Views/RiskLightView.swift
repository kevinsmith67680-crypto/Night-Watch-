import SwiftUI
import NightWatchCore

/// The traffic light, clearly labelled as temporary prototype rules.
/// Used both for real monitoring and in simulation replays.
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
                advice(for: assessment.level)

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

    /// What to do. Amber is a short list of steps, with the ECG prompt highlighted.
    @ViewBuilder
    private func advice(for level: RiskLevel) -> some View {
        switch level {
        case .amber:
            VStack(alignment: .leading, spacing: 4) {
                Text(SafetyText.amberSummary)
                    .font(.footnote)
                ForEach(SafetyText.amberSteps, id: \.self) { step in
                    let isECG = step.contains("ECG")
                    Label(step, systemImage: Self.icon(for: step))
                        .font(isECG ? Font.footnote.weight(.semibold) : Font.footnote)
                        .padding(isECG ? 4 : 0)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(isECG ? Color.orange.opacity(0.3) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 6))
                }
                Text(SafetyText.ecgCaution)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .green, .red:
            Text(SafetyText.message(for: level))
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private static func icon(for step: String) -> String {
        if step.contains("ECG") { return "waveform.path.ecg" }
        if step.contains("water") { return "drop.fill" }
        if step.contains("cool") { return "thermometer.snowflake" }
        if step.contains("someone") { return "person.2.fill" }
        return "circle.fill"
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
