import SwiftUI
import WatchKit
import NightWatchCore

/// Plays back a simulated scenario minute by minute, showing exactly what the
/// monitoring screen would show at each moment: the traffic light, its advice
/// (e.g. the ECG prompt on amber) and the numbers behind it. It uses the same
/// views as real monitoring, and taps the wrist when the light rises.
struct ScenarioReplayView: View {
    let scenario: Scenario
    /// A run already done by "Run all", or nil to simulate now.
    let existingRun: SimulationRun?
    /// Called once a new run has been simulated (to record the result and save its log).
    let onFinished: (SimulationRun) -> Void

    @State private var run: SimulationRun?
    /// Position in the run, in 5-second windows (fractional while playing).
    @State private var position = 0.0
    @State private var isPlaying = false
    @State private var fast = false
    /// The level the wrist was last told about, so each rise taps once.
    @State private var announcedLevel: RiskLevel = .green

    var body: some View {
        Group {
            if let run, !run.results.isEmpty {
                replay(run)
            } else {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Simulating \(Int(scenario.durationMinutes)) minutes…")
                        .font(.footnote)
                }
            }
        }
        .navigationTitle(scenario.title)
        .task { await loadIfNeeded() }
        .task(id: isPlaying) { await play() }
        .onDisappear { isPlaying = false }
    }

    // MARK: - Screen

    private func replay(_ run: SimulationRun) -> some View {
        let index = currentIndex(in: run)
        let current = run.results[index]
        let minute = (current.features.end - run.startTime) / 60

        return ScrollView {
            VStack(spacing: 8) {
                Label("SIMULATION · not real data", systemImage: "play.rectangle.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.orange)

                Text(String(format: "Minute %.1f of %.0f", minute, scenario.durationMinutes))
                    .font(.footnote)
                    .monospacedDigit()
                TimelineBar(levels: run.results.map { $0.risk?.level ?? .green }, position: index)

                // Exactly what the monitoring screen would show now.
                RiskLightView(assessment: current.risk)

                controls(run)

                heartRate(current)
                FeaturesPanel(result: current, note: nil)

                outcome(run)
                DisclaimerBanner()
            }
            .padding(.horizontal, 4)
        }
    }

    @ViewBuilder
    private func controls(_ run: SimulationRun) -> some View {
        HStack {
            Button { step(by: -12, in: run) } label: {
                Image(systemName: "gobackward.60")
            }
            Button { togglePlay(run) } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
            }
            Button { step(by: 12, in: run) } label: {
                Image(systemName: "goforward.60")
            }
        }

        let amber = firstIndex(reaching: .amber, in: run)
        let red = firstIndex(reaching: .red, in: run)
        if amber != nil || red != nil {
            HStack {
                if let amber {
                    Button("Amber") { jump(to: amber, in: run) }
                        .tint(.orange)
                }
                if let red {
                    Button("Red") { jump(to: red, in: run) }
                        .tint(.red)
                }
            }
        }

        Button(fast ? "Speed: 5 min per second" : "Speed: 1 min per second") {
            fast.toggle()
        }
        .font(.footnote)
    }

    private func heartRate(_ result: WindowResult) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: "heart.fill")
                .foregroundStyle(.red)
            Text(result.features.heartRateBPM.map { String(Int($0.rounded())) } ?? "--")
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text("BPM")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func outcome(_ run: SimulationRun) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Result")
                .font(.headline)
                .foregroundStyle(Theme.green)
            Text("Should: \(scenario.expectationText)")
                .font(.caption2)
            Text(run.summary)
                .font(.caption2)
            Text("Seed \(run.seed). Each new run uses fresh random noise.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Playback

    private func currentIndex(in run: SimulationRun) -> Int {
        max(0, min(run.results.count - 1, Int(position)))
    }

    private func firstIndex(reaching level: RiskLevel, in run: SimulationRun) -> Int? {
        run.results.firstIndex { ($0.risk?.level ?? .green) >= level }
    }

    private func togglePlay(_ run: SimulationRun) {
        if !isPlaying && currentIndex(in: run) >= run.results.count - 1 {
            jump(to: 0, in: run)   // at the end: start again from the beginning
        }
        isPlaying.toggle()
    }

    private func step(by windows: Int, in run: SimulationRun) {
        jump(to: currentIndex(in: run) + windows, in: run)
    }

    private func jump(to index: Int, in run: SimulationRun) {
        isPlaying = false
        position = Double(max(0, min(run.results.count - 1, index)))
        announcedLevel = run.results[currentIndex(in: run)].risk?.level ?? .green
    }

    /// Moves forward 10 times a second: 1 or 5 simulated minutes per real second.
    private func play() async {
        guard isPlaying, let run else { return }
        let last = Double(run.results.count - 1)
        while isPlaying && !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(100))
            guard isPlaying else { break }
            let windowsPerSecond = (fast ? 5.0 : 1.0) * 12
            position = min(last, position + windowsPerSecond * 0.1)
            announceIfRaised(run)
            if position >= last {
                isPlaying = false
            }
        }
    }

    /// Taps the wrist when playback reaches amber or red, as the real app would.
    private func announceIfRaised(_ run: SimulationRun) {
        let level = run.results[currentIndex(in: run)].risk?.level ?? .green
        if level > announcedLevel {
            WKInterfaceDevice.current().play(level == .red ? .failure : .notification)
        }
        announcedLevel = level
    }

    private func loadIfNeeded() async {
        guard run == nil else { return }
        if let existingRun {
            run = existingRun
            announcedLevel = existingRun.results.first?.risk?.level ?? .green
            return
        }
        let kind = scenario.kind
        let start = Date().timeIntervalSince1970
        let seed = UInt64.random(in: 1...100_000)
        let result = await Task.detached(priority: .userInitiated) {
            Simulator.run(kind, seed: seed, startTime: start)
        }.value
        run = result
        announcedLevel = result.results.first?.risk?.level ?? .green
        onFinished(result)
    }
}

/// A thin bar coloured green, amber or red along the whole scenario, with a
/// white marker at the current position.
private struct TimelineBar: View {
    let levels: [RiskLevel]
    let position: Int

    var body: some View {
        Canvas { context, size in
            guard !levels.isEmpty else { return }
            let width = size.width / CGFloat(levels.count)
            for (i, level) in levels.enumerated() {
                let rect = CGRect(x: CGFloat(i) * width, y: 0, width: width + 0.5, height: size.height)
                context.fill(Path(rect), with: .color(Self.color(for: level)))
            }
            let x = (CGFloat(position) + 0.5) * width
            context.fill(Path(CGRect(x: x - 1.5, y: 0, width: 3, height: size.height)), with: .color(.white))
        }
        .frame(height: 10)
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private static func color(for level: RiskLevel) -> Color {
        switch level {
        case .green: return .green
        case .amber: return .orange
        case .red: return .red
        }
    }
}
