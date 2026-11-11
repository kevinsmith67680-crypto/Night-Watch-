import SwiftUI
import NightWatchCore

/// Records normal-day data and learns your personal baseline.
struct CalibrationView: View {
    @ObservedObject var monitor: MonitorController
    @State private var confirmingDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                baselineSummary
                Divider()
                progressSection
                controls
                if let message = monitor.calibrationMessage {
                    Text(message)
                        .font(.footnote)
                }
                Divider()
                tips
                Button("Delete calibration", role: .destructive) {
                    confirmingDelete = true
                }
                .disabled(monitor.isActive)
                DisclaimerBanner()
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Calibration")
        .confirmationDialog("Delete all calibration data and your baseline?",
                            isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) {
                monitor.resetCalibration()
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var baselineSummary: some View {
        if let baseline = monitor.baseline {
            Text("Your baseline")
                .font(.headline)
                .foregroundStyle(Theme.green)
            row("Resting", "\(Int(baseline.restingHeartRateBPM.rounded())) bpm")
            row("Movement", String(format: "+%.0f bpm per 0.1 g", baseline.bpmPerG * 0.1))
            row("Lag", "\(Int(baseline.lagRiseSeconds)) s up · \(Int(baseline.lagFallSeconds)) s down")
            row("Typical error", String(format: "±%.0f bpm", baseline.residualSDBPM))
            if let apple = baseline.appleRestingHeartRateBPM {
                row("Apple resting", "\(Int(apple.rounded())) bpm")
            }
            if let tremor = baseline.tremorBaselineDegPerSec {
                row("Normal tremor", String(format: "%.2f °/s", tremor))
            } else {
                row("Normal tremor", "not measured")
            }
        } else {
            Text("Not calibrated yet. Until you are, expected heart rate uses rough defaults.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var progressSection: some View {
        let progress = monitor.calibrationProgress
        return VStack(alignment: .leading, spacing: 2) {
            Text("Recorded")
                .font(.headline)
                .foregroundStyle(Theme.green)
            row("Total", minutes(progress.totalMinutes, of: progress.requiredTotalMinutes))
            row("Still", minutes(progress.stillMinutes, of: progress.requiredStillMinutes))
            row("Active", minutes(progress.activeMinutes, of: progress.requiredActiveMinutes))
            row("Tremor (optional)", minutes(progress.tremorMinutes, of: progress.requiredTremorMinutes))
        }
    }

    @ViewBuilder
    private var controls: some View {
        if monitor.isActive && monitor.mode == .calibrating {
            HStack(spacing: 4) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.red)
                Text(monitor.latestHeartRate.map { "\(Int($0.bpm.rounded())) bpm" } ?? "-- bpm")
                Spacer()
                if let start = monitor.startDate {
                    Text(start, style: .timer)
                        .monospacedDigit()
                }
            }
            .font(.footnote)
            Text("Recording. Go about normal activities.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Stop recording", role: .destructive) {
                monitor.stop()
            }
            .tint(.red)
            .disabled(monitor.state == .starting)

        } else if monitor.isActive {
            Text("Monitoring is running. Stop it before calibrating.")
                .font(.footnote)
                .foregroundStyle(.orange)

        } else {
            Button("Start recording") {
                monitor.start(.calibrating)
            }
            .tint(.green)
            .disabled(monitor.state == .stopping)

            if case .failed(let message) = monitor.state, monitor.mode == .calibrating {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Button(monitor.isFitting ? "Calculating…" : "Calculate baseline") {
                monitor.fitCalibration()
            }
            .disabled(!monitor.calibrationProgress.isReady || monitor.isFitting)

            if !monitor.calibrationProgress.isReady {
                Text(monitor.calibrationProgress.missing.joined(separator: " "))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var tips: some View {
        Text("Tips: record 2–4 sessions on normal days. Include sitting quietly, walking, and something "
             + "brisker such as stairs or dancing. Avoid calibrating after stimulants, lots of caffeine "
             + "or alcohol, or when unwell, as they would become part of your \"normal\".")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    // MARK: - Helpers

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .monospacedDigit()
        }
        .font(.footnote)
    }

    private func minutes(_ done: Double, of needed: Double) -> String {
        "\(Int(done.rounded(.down))) / \(Int(needed)) min"
    }
}
