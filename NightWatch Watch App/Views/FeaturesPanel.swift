import SwiftUI
import NightWatchCore

/// Shows the latest 5-second results: expected and excess heart rate,
/// activity, tremor and arm angle.
struct FeaturesPanel: View {
    let result: WindowResult?
    let note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let note {
                Text(note)
                    .foregroundStyle(.orange)
            }

            if let result {
                heartRateRows(result)
            }

            if let motion = result?.features.motion {
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

    @ViewBuilder
    private func heartRateRows(_ result: WindowResult) -> some View {
        if let expected = result.expectedHeartRateBPM {
            row("Expected", String(format: "%.0f bpm", expected) + (result.baselineIsCalibrated ? "" : " *"))
        }
        if let filtered = result.filtered {
            // Smoothed by the Kalman filter.
            row("Excess", String(format: "%+.0f bpm", filtered.excessBPM))
            row("Trend", String(format: "%+.1f bpm/min", filtered.trendBPMPerMinute))
            switch filtered.decision {
            case .rejectedAsSpike:
                Text("Spike ignored")
                    .foregroundStyle(.orange)
            case .restarted:
                Text("Filter (re)started")
                    .foregroundStyle(.secondary)
            case .accepted, .missing:
                EmptyView()
            }
        }
        if let raw = result.excessHeartRateBPM {
            row("Raw excess", String(format: "%+.0f bpm", raw))
        }
        if !result.baselineIsCalibrated && result.expectedHeartRateBPM != nil {
            Text("* rough default, not calibrated yet")
                .foregroundStyle(.secondary)
        }
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
