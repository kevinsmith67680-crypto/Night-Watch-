import Foundation

/// All the raw readings that arrived during one window of time.
public struct SensorWindow: Equatable, Sendable {
    public let start: Timestamp
    public let end: Timestamp
    public private(set) var heartRates: [HeartRateSample] = []
    public private(set) var motion: [MotionSample] = []
    public private(set) var wristTemperatures: [WristTemperatureSample] = []

    public init(start: Timestamp, end: Timestamp) {
        self.start = start
        self.end = end
    }

    public mutating func add(_ reading: SensorReading) {
        switch reading {
        case .heartRate(let sample): heartRates.append(sample)
        case .motion(let sample): motion.append(sample)
        case .wristTemperature(let sample): wristTemperatures.append(sample)
        }
    }
}

/// Collects readings into back-to-back windows (5 seconds by default).
///
/// Feed it every reading in the order they arrive. When a reading belongs
/// after the current window, that window is finished and handed back.
///
/// Late readings: Apple delivers heart rate a few seconds after it was
/// measured, so its timestamp can be earlier than the current window. Such a
/// reading goes into the window that is open when it ARRIVES (keeping its true
/// timestamp). The heart responds to movement with a delay anyway, which the
/// baseline model (Step 4) allows for.
///
/// Gaps: if nothing arrives for longer than a window, empty windows are
/// skipped rather than reported.
public struct WindowAccumulator: Sendable {
    public let windowSeconds: Double
    private var current: SensorWindow?

    public init(windowSeconds: Double) {
        precondition(windowSeconds > 0, "windowSeconds must be positive")
        self.windowSeconds = windowSeconds
    }

    /// Adds a reading. Returns the previous window if this reading closed it.
    public mutating func add(_ reading: SensorReading) -> SensorWindow? {
        if current == nil {
            current = SensorWindow(start: reading.time, end: reading.time + windowSeconds)
        }

        var finished: SensorWindow?
        if let open = current, reading.time >= open.end {
            finished = open
            // Start the window that contains this reading, staying on the same grid.
            let windowsToSkip = ((reading.time - open.start) / windowSeconds).rounded(.down)
            let newStart = open.start + windowsToSkip * windowSeconds
            current = SensorWindow(start: newStart, end: newStart + windowSeconds)
        }

        current?.add(reading)
        return finished
    }

    /// Hands back the unfinished window (e.g. when monitoring stops) and resets.
    public mutating func flush() -> SensorWindow? {
        let unfinished = current
        current = nil
        return unfinished
    }
}
