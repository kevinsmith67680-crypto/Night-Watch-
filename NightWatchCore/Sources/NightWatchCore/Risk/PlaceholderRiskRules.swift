import Foundation

/// ⚠️ TEMPORARY traffic-light rules, until the IMM filter exists.
///
/// The idea: a high heart rate is only suspicious when it is NOT explained by
/// movement. So every rule requires the wearer to have been still for a while,
/// and none fires while the excess is clearly falling (e.g. recovering after
/// exercise). All thresholds live in `RiskConfig`.
public struct PlaceholderRiskRules: RiskEngine {
    public let config: RiskConfig
    public let windowSeconds: Double
    /// Tremor size above which tremor counts as raised (degrees per second):
    /// personal if calibration measured your normal tremor, otherwise fixed.
    public let tremorThresholdDegPerSec: Double

    /// What we remember about each recent window.
    private struct Snapshot: Sendable {
        var time: Timestamp
        var isStill: Bool
        var heartRate: Double?
        var tremorReliable: Bool
        var tremorDegPerSec: Double
        var tremorRhythmicity: Double
    }

    private var history: [Snapshot] = []
    private var currentLevel: RiskLevel = .green
    /// When the conditions for the current level stopped being met.
    private var clearSince: Timestamp?
    private let historySeconds: Double

    /// - personalTremorDegPerSec: your normal tremor from calibration, or nil.
    public init(config: RiskConfig = RiskConfig(), windowSeconds: Double = 5,
                personalTremorDegPerSec: Double? = nil) {
        self.config = config
        self.windowSeconds = windowSeconds
        if let personal = personalTremorDegPerSec {
            tremorThresholdDegPerSec = max(config.tremorRaisedMinimumDegPerSec,
                                           config.tremorRaisedMultiplier * personal)
        } else {
            tremorThresholdDegPerSec = config.tremorRaisedDegPerSec
        }
        let longestStill = max(config.amberStillMinutes, config.amberAbsoluteStillMinutes,
                               config.redStillMinutes, config.redAbsoluteStillMinutes)
        historySeconds = (longestStill + config.tremorLookbackMinutes + 5) * 60
    }

    public mutating func assess(_ result: WindowResult) -> RiskAssessment {
        let now = result.features.end
        let motion = result.features.motion
        history.append(Snapshot(time: now,
                                isStill: motion?.isStill ?? false,
                                heartRate: result.features.heartRateBPM,
                                tremorReliable: motion?.tremorReliable ?? false,
                                tremorDegPerSec: motion?.tremorGyroDegPerSec ?? 0,
                                tremorRhythmicity: motion?.tremorRhythmicity ?? 0))
        let oldest = now - historySeconds
        history.removeAll { $0.time < oldest }

        let still = stillMinutes(now: now)
        let heartRate = recentHeartRate(now: now)
        let tremor = tremorRaised(now: now)
        let useExcess = result.baselineIsCalibrated || !config.requireCalibrationForExcessRules
        let excess = useExcess ? result.filtered?.excessBPM : nil
        let trend = result.filtered?.trendBPMPerMinute ?? 0

        // 1. Which level do the rules call for right now?
        var target = RiskLevel.green
        var reasons: [String] = []
        func flag(_ level: RiskLevel, _ reason: String) {
            if level > target { target = level }
            reasons.append(reason)
        }
        let stillText = "while still for \(Int(still.rounded(.down))) min"
        let rising = trend >= config.amberRisingTrendBPMPerMinute
        let notFalling = trend >= config.notFallingTrendBPMPerMinute

        if let excess {
            let excessText = String(format: "Excess heart rate %+.0f bpm", excess)
            let trendText = String(format: "%+.1f bpm/min", trend)
            if still >= config.redStillMinutes && excess >= config.redExcessBPM {
                if trend >= config.redRisingTrendBPMPerMinute {
                    flag(.red, "\(excessText), rising \(trendText), \(stillText).")
                } else if tremor {
                    let tremorText = String(format: "raised tremor (above %.1f °/s)", tremorThresholdDegPerSec)
                    flag(.red, "\(excessText) with \(tremorText), \(stillText).")
                }
            }
            if still >= config.redStillMinutes && excess >= config.redExcessAloneBPM && notFalling {
                flag(.red, "\(excessText) and not falling, \(stillText).")
            }
            if still >= config.amberStillMinutes && excess >= config.amberExcessRisingBPM && rising {
                flag(.amber, "\(excessText), rising \(trendText), \(stillText).")
            }
            if still >= config.amberStillMinutes && excess >= config.amberExcessSteadyBPM && notFalling {
                flag(.amber, "\(excessText) and not falling, \(stillText).")
            }
        }
        if let heartRate {
            let rateText = "Heart rate \(Int(heartRate.rounded())) bpm"
            if still >= config.redAbsoluteStillMinutes && heartRate >= config.redAbsoluteHeartRateBPM {
                flag(.red, "\(rateText) \(stillText).")
            }
            if still >= config.amberAbsoluteStillMinutes && heartRate >= config.amberAbsoluteHeartRateBPM {
                flag(.amber, "\(rateText) \(stillText).")
            }
        }

        // 2. Step up at once; step down only after a quiet period.
        if target >= currentLevel {
            currentLevel = target
            clearSince = nil
        } else {
            let since = clearSince ?? now
            clearSince = since
            let waitSeconds = config.stepDownAfterMinutes * 60
            if now - since >= waitSeconds {
                currentLevel = target
                clearSince = nil
            } else {
                let minutesLeft = Int(((waitSeconds - (now - since)) / 60).rounded(.up))
                reasons.append("Staying \(currentLevel.label) for up to \(minutesLeft) more min after the warning signs cleared.")
            }
        }

        // 3. Things worth knowing.
        if !useExcess {
            reasons.append("Not calibrated: only the heart-rate backstop rules are active.")
        }
        if heartRate == nil {
            reasons.append("No heart rate in the last minute.")
        }

        return RiskAssessment(time: now, level: currentLevel, reasons: reasons,
                              stillMinutes: still, recentHeartRateBPM: heartRate,
                              tremorRaised: tremor, engineName: "Temporary rules")
    }

    public mutating func reset() {
        history.removeAll()
        currentLevel = .green
        clearSince = nil
    }

    // MARK: - Helpers

    /// Length of the current still period, in minutes. Brief movements (up to
    /// `maxMovingWindowsInStillPeriod` windows in a row) don't end it; a longer
    /// movement or a gap in the data does.
    private func stillMinutes(now: Timestamp) -> Double {
        var movingInRow = 0
        var periodStart: Timestamp?
        var previousTime = now
        for snapshot in history.reversed() {
            if previousTime - snapshot.time > windowSeconds * 3 { break }   // gap in data
            previousTime = snapshot.time
            if snapshot.isStill {
                movingInRow = 0
                periodStart = snapshot.time - windowSeconds
            } else {
                movingInRow += 1
                if movingInRow > config.maxMovingWindowsInStillPeriod { break }
            }
        }
        guard let start = periodStart else { return 0 }
        return (now - start) / 60
    }

    /// Median heart rate over the last `staleHeartRateSeconds`, or nil if none.
    private func recentHeartRate(now: Timestamp) -> Double? {
        let rates = history
            .filter { now - $0.time <= config.staleHeartRateSeconds }
            .compactMap { $0.heartRate }
        return Statistics.median(rates)
    }

    private func tremorRaised(now: Timestamp) -> Bool {
        let recent = history.filter { now - $0.time < config.tremorLookbackMinutes * 60 }
        let reliable = recent.filter { $0.tremorReliable }
        guard !reliable.isEmpty, reliable.count * 2 >= recent.count,
              let size = Statistics.median(reliable.map { $0.tremorDegPerSec }),
              let rhythm = Statistics.median(reliable.map { $0.tremorRhythmicity })
        else { return false }
        return size >= tremorThresholdDegPerSec && rhythm >= config.tremorMinimumRhythmicity
    }
}
