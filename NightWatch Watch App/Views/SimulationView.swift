import SwiftUI
import NightWatchCore

/// Plays the test scenarios through the same pipeline the real watch uses.
struct SimulationView: View {
    @State private var runs: [ScenarioKind: SimulationRun] = [:]
    @State private var running: ScenarioKind?
    @State private var saveLogs = true

    var body: some View {
        List {
            Text("Plays a pretend person through exactly the same pipeline as real monitoring. Each scenario takes a few seconds on the watch.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Toggle("Save CSV logs", isOn: $saveLogs)

            ForEach(Scenario.all, id: \.kind) { scenario in
                Button {
                    Task { await run(scenario.kind) }
                } label: {
                    ScenarioRow(scenario: scenario, run: runs[scenario.kind], isRunning: running == scenario.kind)
                }
                .disabled(running != nil)
            }

            Button("Run all") {
                Task {
                    for scenario in Scenario.all { await run(scenario.kind) }
                }
            }
            .disabled(running != nil)

            DisclaimerBanner()
                .listRowBackground(Color.clear)
        }
        .navigationTitle("Simulation")
    }

    private func run(_ kind: ScenarioKind) async {
        running = kind
        let start = Date().timeIntervalSince1970
        let seed = UInt64.random(in: 1...100_000)   // fresh random noise every run
        let result = await Task.detached(priority: .userInitiated) {
            Simulator.run(kind, seed: seed, startTime: start)
        }.value
        runs[kind] = result
        if saveLogs {
            LogStore.save(simulation: result)
        }
        running = nil
    }
}

private struct ScenarioRow: View {
    let scenario: Scenario
    let run: SimulationRun?
    let isRunning: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(scenario.title)
                    .font(.headline)
                    .foregroundStyle(Theme.green)
                Spacer()
                if isRunning {
                    ProgressView()
                } else if let run {
                    Image(systemName: run.passed ? "checkmark.circle.fill" : "xmark.octagon.fill")
                        .foregroundStyle(run.passed ? .green : .red)
                }
            }
            Text(scenario.summary)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("Should: \(scenario.expectationText)")
                .font(.caption2)
            if let run {
                Text("Result (seed \(run.seed)): \(run.summary)")
                    .font(.caption2)
            }
        }
    }
}
