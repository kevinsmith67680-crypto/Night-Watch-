import Foundation

/// One usable 5-second window recorded during calibration.
public struct CalibrationPoint: Codable, Equatable, Sendable {
    public var time: Timestamp
    public var activityG: Double
    public var heartRateBPM: Double
    /// Tremor size (degrees per second) if this window's tremor reading was
    /// reliable (still, enough samples), otherwise nil.
    public var tremorDegPerSec: Double?

    public init(time: Timestamp, activityG: Double, heartRateBPM: Double, tremorDegPerSec: Double? = nil) {
        self.time = time
        self.activityG = activityG
        self.heartRateBPM = heartRateBPM
        self.tremorDegPerSec = tremorDegPerSec
    }
}

/// How much calibration data has been collected, and what is still missing.
public struct CalibrationProgress: Equatable, Sendable {
    public var totalMinutes: Double
    public var stillMinutes: Double
    public var activeMinutes: Double
    public var requiredTotalMinutes: Double
    public var requiredStillMinutes: Double
    public var requiredActiveMinutes: Double
    /// Optional: quiet minutes with reliable tremor readings, for a personal tremor baseline.
    public var tremorMinutes: Double
    public var requiredTremorMinutes: Double

    public var hasEnoughTremorData: Bool {
        tremorMinutes >= requiredTremorMinutes
    }

    public var isReady: Bool {
        totalMinutes >= requiredTotalMinutes
            && stillMinutes >= requiredStillMinutes
            && activeMinutes >= requiredActiveMinutes
    }

    /// Plain-English list of what's still needed. Empty when ready.
    public var missing: [String] {
        var reasons: [String] = []
        if totalMinutes < requiredTotalMinutes {
            reasons.append("Record \(Self.minutes(requiredTotalMinutes - totalMinutes)) more min in total.")
        }
        if stillMinutes < requiredStillMinutes {
            reasons.append("Sit quietly for \(Self.minutes(requiredStillMinutes - stillMinutes)) more min.")
        }
        if activeMinutes < requiredActiveMinutes {
            reasons.append("Walk briskly, climb stairs or dance for \(Self.minutes(requiredActiveMinutes - activeMinutes)) more min.")
        }
        return reasons
    }

    private static func minutes(_ value: Double) -> Int {
        Int(value.rounded(.up))
    }
}

public struct CalibrationResult: Equatable, Sendable {
    public var model: BaselineModel
    /// Things worth knowing about the fit, in plain English.
    public var warnings: [String]
}

public enum CalibrationError: Error, Equatable, CustomStringConvertible {
    case notEnoughData([String])
    case cannotFit(String)

    public var description: String {
        switch self {
        case .notEnoughData(let reasons): return "Not enough data yet. " + reasons.joined(separator: " ")
        case .cannotFit(let reason): return reason
        }
    }
}

/// Learns your baseline from calibration recordings.
///
/// 1. Each usable window (heart rate + good motion data) is stored as a point.
/// 2. For every candidate pair of lag times, activity is passed through the lag
///    filter, and a straight line  heart rate = resting + k × lagged activity
///    is fitted by least squares.
/// 3. Glitches far from the line are dropped and the line refitted.
/// 4. The lag pair with the smallest typical error wins.
public struct BaselineCalibrator: Sendable {
    public let config: MonitorConfig
    public private(set) var points: [CalibrationPoint]

    public init(config: MonitorConfig = .standard, points: [CalibrationPoint] = []) {
        self.config = config
        self.points = points
    }

    /// Adds one finished window. Returns false (and ignores it) if the window
    /// has no heart rate or poor-quality motion data.
    @discardableResult
    public mutating func add(_ window: WindowFeatures) -> Bool {
        guard let heartRate = window.heartRateBPM,
              let motion = window.motion,
              motion.qualityOK
        else { return false }
        points.append(CalibrationPoint(time: window.end,
                                       activityG: motion.activityG,
                                       heartRateBPM: heartRate,
                                       tremorDegPerSec: motion.tremorReliable ? motion.tremorGyroDegPerSec : nil))
        return true
    }

    public var progress: CalibrationProgress {
        let minutesPerWindow = config.features.windowSeconds / 60
        let still = points.filter { $0.activityG < config.features.stillnessThresholdG }.count
        let active = points.filter { $0.activityG >= config.calibration.activeThresholdG }.count
        let tremor = points.filter { $0.tremorDegPerSec != nil }.count
        return CalibrationProgress(totalMinutes: Double(points.count) * minutesPerWindow,
                                   stillMinutes: Double(still) * minutesPerWindow,
                                   activeMinutes: Double(active) * minutesPerWindow,
                                   requiredTotalMinutes: config.calibration.minimumTotalMinutes,
                                   requiredStillMinutes: config.calibration.minimumStillMinutes,
                                   requiredActiveMinutes: config.calibration.minimumActiveMinutes,
                                   tremorMinutes: Double(tremor) * minutesPerWindow,
                                   requiredTremorMinutes: config.calibration.minimumTremorMinutes)
    }

    /// Fits the baseline. Throws `CalibrationError` if there isn't enough data
    /// or the result isn't believable.
    public func fit(appleRestingHeartRateBPM: Double? = nil, now: Date = Date()) throws -> CalibrationResult {
        let progress = self.progress
        guard progress.isReady else { throw CalibrationError.notEnoughData(progress.missing) }
        let settings = config.calibration

        var best: (fit: LinearFit, rise: Double, fall: Double)?
        for rise in settings.lagRiseCandidatesSeconds {
            for fall in settings.lagFallCandidatesSeconds {
                let samples = laggedSamples(riseSeconds: rise, fallSeconds: fall)
                guard let fit = LinearFit.robust(samples, cutoffSD: settings.outlierCutoffSD) else { continue }
                if let current = best, current.fit.residualSD <= fit.residualSD { continue }
                best = (fit, rise, fall)
            }
        }
        guard let chosen = best else {
            throw CalibrationError.cannotFit("Heart rate and movement didn't vary enough to calculate a baseline.")
        }

        var warnings: [String] = []
        var resting = chosen.fit.intercept
        var slope = chosen.fit.slope
        if slope < 0 {
            warnings.append("Heart rate didn't rise with movement in this data, so movement is ignored. Consider recording again.")
            slope = 0
            resting = chosen.fit.meanY
        }
        guard (35...120).contains(resting) else {
            throw CalibrationError.cannotFit(
                "The calculated resting heart rate (\(Int(resting.rounded())) bpm) isn't believable. Delete the calibration and record again.")
        }
        if let apple = appleRestingHeartRateBPM, abs(apple - resting) > settings.appleDisagreementWarningBPM {
            warnings.append("Calibrated resting heart rate (\(Int(resting.rounded())) bpm) differs from Apple's "
                            + "(\(Int(apple.rounded())) bpm). Recording more quiet sitting may help.")
        }

        // Personal normal tremor (optional): the median of reliable still-window readings.
        var tremorBaseline: Double?
        if progress.hasEnoughTremorData {
            tremorBaseline = Statistics.median(points.compactMap { $0.tremorDegPerSec })
        } else {
            warnings.append("Not enough quiet data for a personal tremor baseline, so the fixed tremor "
                            + "threshold is used. Record about 10 minutes sitting still, then calculate again.")
        }

        let model = BaselineModel(restingHeartRateBPM: resting,
                                  bpmPerG: slope,
                                  lagRiseSeconds: chosen.rise,
                                  lagFallSeconds: chosen.fall,
                                  residualSDBPM: chosen.fit.residualSD,
                                  rSquared: chosen.fit.rSquared,
                                  windowsUsed: chosen.fit.count,
                                  appleRestingHeartRateBPM: appleRestingHeartRateBPM,
                                  calibratedAt: now,
                                  isCalibrated: true,
                                  tremorBaselineDegPerSec: tremorBaseline)
        return CalibrationResult(model: model, warnings: warnings)
    }

    /// (lagged activity, heart rate) pairs for one choice of lag times.
    /// Recordings are split at pauses, and each one's warm-up is left out.
    private func laggedSamples(riseSeconds: Double, fallSeconds: Double) -> [(x: Double, y: Double)] {
        let settings = config.calibration
        var filter = ActivityLagFilter(riseSeconds: riseSeconds, fallSeconds: fallSeconds)
        var samples: [(x: Double, y: Double)] = []
        var segmentStart: Timestamp?
        var previousTime: Timestamp?

        for point in points.sorted(by: { $0.time < $1.time }) {
            if let previous = previousTime, point.time - previous > settings.maxGapSeconds {
                filter.reset()
                segmentStart = nil
            }
            let start = segmentStart ?? point.time
            segmentStart = start
            previousTime = point.time

            let lagged = filter.update(activity: point.activityG, at: point.time)
            if point.time - start >= settings.warmUpSeconds {
                samples.append((x: lagged, y: point.heartRateBPM))
            }
        }
        return samples
    }
}

/// A straight-line fit  y = intercept + slope × x  by least squares.
struct LinearFit: Equatable {
    var slope: Double
    var intercept: Double
    /// Typical distance of points from the line.
    var residualSD: Double
    var rSquared: Double
    var meanY: Double
    var count: Int

    static func ordinary(_ samples: [(x: Double, y: Double)]) -> LinearFit? {
        guard samples.count >= 3 else { return nil }
        let n = Double(samples.count)
        let meanX = samples.reduce(0.0) { $0 + $1.x } / n
        let meanY = samples.reduce(0.0) { $0 + $1.y } / n

        var sxx = 0.0, sxy = 0.0, syy = 0.0
        for sample in samples {
            let dx = sample.x - meanX
            let dy = sample.y - meanY
            sxx += dx * dx
            sxy += dx * dy
            syy += dy * dy
        }
        guard sxx > 1e-12 else { return nil }   // x never changed: no line can be fitted

        let slope = sxy / sxx
        let intercept = meanY - slope * meanX
        var ssResidual = 0.0
        for sample in samples {
            let residual = sample.y - (intercept + slope * sample.x)
            ssResidual += residual * residual
        }
        return LinearFit(slope: slope,
                         intercept: intercept,
                         residualSD: (ssResidual / max(n - 2, 1)).squareRoot(),
                         rSquared: syy > 0 ? 1 - ssResidual / syy : 0,
                         meanY: meanY,
                         count: samples.count)
    }

    /// Fits once, drops points more than `cutoffSD` typical errors away, fits again.
    static func robust(_ samples: [(x: Double, y: Double)], cutoffSD: Double) -> LinearFit? {
        guard let first = ordinary(samples) else { return nil }
        let limit = cutoffSD * first.residualSD
        let kept = samples.filter { abs($0.y - (first.intercept + first.slope * $0.x)) <= limit }
        return ordinary(kept) ?? first
    }
}
