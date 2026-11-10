import SwiftUI
import NightWatchCore

/// Shows the latest 5-second motion results: activity, tremor and arm angle.
struct FeaturesPanel: View {
    let window: WindowFeatures?
    let note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let note {
                Text(note)
                    .foregroundStyle(.orange)
            }

            if let motion = window?.motion {
                row("Activity", String(format: "%.3f g", motion.activityG)
                                + (motion.isStill ? " · still" : " · moving"))

                if motion.tremorReliable {
                    row("Tremor", String(format: "%.2f °/s", motion.tremorGyroDegPerSec))
                    row("Peak", String(format: "%.1f Hz", motion.tremorPeakHz))
                    row("Rhythm", String(format: "%.2f", motion.tremorRhythmicity))
                } else {
                    row("Tremor", motion.qualityOK ? "– moving" : "– data gaps")
                }

                row("Arm", "\(label(for: motion.armOrientation)) \(Int(motion.forearmElevationDegrees.rounded()))°")
            } else if note == nil {
                Text("First results after 5 s…")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.footnote)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .monospacedDigit()
        }
    }

    private func label(for orientation: ArmOrientation) -> String {
        switch orientation {
        case .forearmVertical: return "vertical"
        case .forearmHorizontal: return "flat"
        case .inBetween: return "angled"
        case .unknown: return "?"
        }
    }
}
