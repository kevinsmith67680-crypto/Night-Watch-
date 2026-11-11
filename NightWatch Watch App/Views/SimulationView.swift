import SwiftUI
import NightWatchCore

/// Lists the test scenarios. Tap one to watch, minute by minute, how the app
/// would respond; "Run all" just checks pass/fail for every scenario.
struct SimulationView: View {
    @State private var runs: [ScenarioKind: SimulationRun] = [:]
    @State private var runningAll: ScenarioKind?
    @State private var saveLogs = true

    var body: some View {
        List {
            Text("Tap a scenario to see how Night Watch would respond, minute by minute. A pretend person goes through exactly the same steps as real monitoring.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Toggle("Save CSV logs", isOn: $saveLogs)

            ForEach(Scenario.all, id: \.kind) { scenario in
                NavigationLink {
                    ScenarioReplayView(scenario: scenario, existingRun: runs[scenario.kind]) { run in
                        record(run)
                    }
                } label: {
                    ScenarioRow(scenario: scenario, run: runs[scenario.kind],
                                isRunning: runningAll == scenario.kind)
                }
                .disabled(runningAll != nil)
            }

            Button("Run all (pass/fail only)") {
                Task {
                    for scenario in Scenario.all {
                        await runQuietly(scenario.kind)
                    }
                }
            }
            .disabled(runningAll != nil)

            DisclaimerBanner()
                .listRowBackground(Color.clear)
        }
        .navigationTitle("Simulation")
    }

    private func record(_ run: SimulationRun) {
        runs[run.scenario.kind] = run
        if saveLogs {
            LogStore.save(simulation: run)
        }
    }

    private func runQuietly(_ kind: ScenarioKind) async {
        runningAll = kind
        let start = Date().timeIntervalSince1970
        let seed = UInt64.random(in: 1...100_000)   // fresh random noise every run
        let result = await Task.detached(priority: .userInitiated) {
            Simulator.run(kind, seed: seed, startTime: start)
        }.value
        record(result)
        runningAll = nil
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
                Text("Last run: \(run.summary)")
                    .font(.caption2)
            }
        }
    }
}
