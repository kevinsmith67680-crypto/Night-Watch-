import Foundation

/// Turns window results into CSV rows (opens in Numbers, Excel or Google Sheets).
/// One row per 5-second window. Empty cells mean "not available".
public enum CSVFormat {

    /// Column names, in order. Units are in the names.
    public static let columns: [String] = [
        "time_iso", "time_unix", "source",
        "hr_bpm", "hr_samples", "expected_hr_bpm", "excess_raw_bpm",
        "excess_filtered_bpm", "trend_bpm_per_min", "excess_sd_bpm", "filter_decision",
        "activity_g", "lagged_activity_g", "still", "still_minutes",
        "tremor_accel_mg", "tremor_gyro_dps", "tremor_peak_hz", "tremor_rhythmicity",
        "tremor_reliable", "tremor_raised",
        "forearm_elevation_deg", "arm_orientation", "motion_samples", "motion_quality_ok",
        "risk_level", "risk_reasons", "baseline_calibrated", "battery_percent",
    ]

    public static var header: String {
        columns.joined(separator: ",")
    }

    /// - source: where the data came from, e.g. "monitoring" or "simulated-dancing".
    /// - batteryPercent: the watch's battery level, if known.
    public static func row(for result: WindowResult, source: String, batteryPercent: Double? = nil) -> String {
        let features = result.features
        let motion = features.motion
        let filtered = result.filtered
        let risk = result.risk

        let fields: [String] = [
            isoTime(features.end),
            number(features.end, 3),
            escape(source),

            number(features.heartRateBPM, 1),
            "\(features.heartRateSampleCount)",
            number(result.expectedHeartRateBPM, 1),
            number(result.excessHeartRateBPM, 1),

            number(filtered?.excessBPM, 2),
            number(filtered?.trendBPMPerMinute, 3),
            number(filtered?.excessSDBPM, 2),
            filtered?.decision.rawValue ?? "",

            number(motion?.activityG, 4),
            number(result.laggedActivityG, 4),
            flag(motion?.isStill),
            number(risk?.stillMinutes, 2),

            number(motion?.tremorAccelMilliG, 3),
            number(motion?.tremorGyroDegPerSec, 3),
            number(motion?.tremorPeakHz, 1),
            number(motion?.tremorRhythmicity, 3),
            flag(motion?.tremorReliable),
            flag(risk?.tremorRaised),

            number(motion?.forearmElevationDegrees, 1),
            motion?.armOrientation.rawValue ?? "",
            motion.map { "\($0.sampleCount)" } ?? "",
            flag(motion?.qualityOK),

            risk?.level.label ?? "",
            escape(risk?.reasons.joined(separator: " | ") ?? ""),
            flag(result.baselineIsCalibrated),
            number(batteryPercent, 0),
        ]
        return fields.joined(separator: ",")
    }

    // MARK: - Helpers

    static func number(_ value: Double?, _ decimals: Int) -> String {
        guard let value, value.isFinite else { return "" }
        return String(format: "%.\(decimals)f", value)
    }

    static func flag(_ value: Bool?) -> String {
        guard let value else { return "" }
        return value ? "1" : "0"
    }

    /// Text containing commas, quotes or new lines must be wrapped in quotes.
    static func escape(_ text: String) -> String {
        guard text.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) else { return text }
        return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone.current
        return formatter
    }()

    static func isoTime(_ time: Timestamp) -> String {
        isoFormatter.string(from: Date(timeIntervalSince1970: time))
    }
}
