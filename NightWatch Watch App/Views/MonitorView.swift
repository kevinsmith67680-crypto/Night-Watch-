import SwiftUI
import NightWatchCore

/// Monitoring mode: the traffic light, live heart rate, the details behind
/// it, and the start/stop button.
struct MonitorView: View {
    @ObservedObject var monitor: MonitorController

    /// True while a calibration recording (not monitoring) is running.
    private var calibrationIsRunning: Bool {
        monitor.isActive && monitor.mode == .calibrating
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                let monitoringIsRunning = monitor.state == .running && monitor.mode == .monitoring
                if let note = monitor.recoveryNote {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                }
                if monitoringIsRunning {
                    RiskLightView(assessment: monitor.risk)
                }
                DisclaimerBanner()
                heartRate
                status
                startStopButton
                if monitoringIsRunning {
                    FeaturesPanel(result: monitor.latestResult, note: monitor.motionNote)
                }
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Monitoring")
    }

    // Big heart-rate number.
    private var heartRate: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: "heart.fill")
                .foregroundStyle(.red)
            Text(monitor.latestHeartRate.map { String(Int($0.bpm.rounded())) } ?? "--")
                .font(.system(size: 40, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text("BPM")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // One or two lines saying what's happening.
    @ViewBuilder
    private var status: some View {
        if calibrationIsRunning {
            Text("Calibration is recording. Stop it in Calibration first.")
                .font(.footnote)
                .foregroundStyle(.orange)
                .multilineTextAlignment(.center)
        } else {
            switch monitor.state {
            case .idle:
                Text("Not monitoring")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

            case .starting:
                Text("Starting…")
                    .font(.footnote)

            case .running:
                if let start = monitor.startDate {
                    HStack(spacing: 4) {
                        Text("Monitoring")
                        Text(start, style: .timer)
                            .monospacedDigit()
                    }
                    .font(.footnote)
                }
                if let sample = monitor.latestHeartRate {
                    HStack(spacing: 4) {
                        Text("Readings: \(monitor.heartRateCount) · last")
                        Text(Date(timeIntervalSince1970: sample.time), style: .relative)
                        Text("ago")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                } else {
                    Text("Waiting for first reading…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

            case .stopping:
                Text("Stopping…")
                    .font(.footnote)

            case .failed(let message):
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
    }

    @ViewBuilder
    private var startStopButton: some View {
        if calibrationIsRunning {
            EmptyView()
        } else if monitor.isActive {
            Button("Stop monitoring", role: .destructive) {
                monitor.stop()
            }
            .tint(.red)
            .disabled(monitor.state == .starting)
        } else {
            Button("Start monitoring") {
                monitor.start(.monitoring)
            }
            .tint(.green)
            .disabled(monitor.state == .stopping)
        }
    }
}

#Preview {
    MonitorView(monitor: MonitorController())
}
