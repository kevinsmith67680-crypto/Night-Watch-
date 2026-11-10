import Foundation

/// Smooths excess heart rate with a 2-state Kalman filter.
///
/// State: [excess heart rate (bpm), its rate of change (bpm per second)].
/// Model: "constant velocity", meaning the excess keeps changing at its current
/// rate, and the rate itself drifts slowly at random (`trendChangePerMinute`).
///
/// Measurement: measured − expected heart rate for each 5-second window.
///
/// On top of the standard filter:
///  • spike rejection: a measurement more than `spikeGateSD` standard deviations
///    from the prediction is ignored, unless several arrive in a row, in which
///    case it is a real change and the filter restarts from the new level;
///  • movement-aware trust: measurements count for less while moving, because
///    wrist heart rate is less reliable then.
///
/// Science note: Apple's heart-rate readings are already smoothed, so
/// neighbouring measurements aren't fully independent. The filter therefore
/// tends to be a little over-confident; the conservative trend setting allows for that.
public struct ExcessHeartRateFilter: StateEstimator {
    public let config: KalmanConfig
    /// Measurement error at rest (bpm, 1 standard deviation).
    public let restingMeasurementSDBPM: Double

    private var filter: KalmanFilter?
    private var lastTime: Timestamp?
    private var consecutiveRejections = 0

    /// Only the measurement sees the excess itself, not its trend: H = [1, 0].
    private static let observation = Matrix([[1, 0]])

    /// - baseline: if calibrated, its typical error sets how much to trust each measurement.
    public init(config: KalmanConfig = KalmanConfig(), baseline: BaselineModel? = nil) {
        self.config = config
        if config.useCalibratedMeasurementSD, let baseline, baseline.isCalibrated {
            restingMeasurementSDBPM = max(config.minimumMeasurementSDBPM, baseline.residualSDBPM)
        } else {
            restingMeasurementSDBPM = config.measurementSDBPM
        }
    }

    public mutating func update(measurement: Double?, activityG: Double?, at time: Timestamp) -> ExcessHeartRateEstimate? {
        let measurementSD = restingMeasurementSDBPM + config.extraMeasurementSDPerG * max(0, activityG ?? 0)

        // Start (or start again after a long gap) from the first available measurement.
        if let value = measurement, filter == nil || isLongGap(until: time) {
            start(at: value, time: time, measurementSD: measurementSD)
            return estimate(at: time, decision: .restarted)
        }
        guard var kalman = filter, let last = lastTime else { return nil }   // nothing yet

        // 1. Predict forward to now.
        let elapsed = max(0, time - last)
        kalman.predict(transition: Self.transition(elapsed), processNoise: processNoise(elapsed))
        lastTime = time

        guard let value = measurement else {
            filter = kalman
            return estimate(at: time, decision: .missing)
        }

        // 2. How surprising is this measurement?
        let z = Matrix([[value]])
        let noise = Matrix([[measurementSD * measurementSD]])
        guard let surprise = kalman.innovation(measurement: z, observation: Self.observation,
                                               measurementNoise: noise) else {
            filter = kalman
            return estimate(at: time, decision: .missing)
        }

        // 3. Spike rejection.
        let gate = config.spikeGateSD * config.spikeGateSD
        if surprise.normalizedSquared > gate {
            consecutiveRejections += 1
            if consecutiveRejections >= config.acceptAfterConsecutiveRejections {
                // Several "spikes" in a row: this is a real change. Restart from
                // the new level but keep the trend we had.
                start(at: value, time: time, measurementSD: measurementSD,
                      trendPerSecond: kalman.state[1, 0])
                return estimate(at: time, decision: .restarted)
            }
            filter = kalman
            return estimate(at: time, decision: .rejectedAsSpike)
        }

        // 4. Normal update.
        consecutiveRejections = 0
        kalman.update(measurement: z, observation: Self.observation, measurementNoise: noise)
        filter = kalman
        return estimate(at: time, decision: .accepted)
    }

    public mutating func reset() {
        filter = nil
        lastTime = nil
        consecutiveRejections = 0
    }

    // MARK: - Model

    /// F: excess(t + dt) = excess(t) + dt × rate;  rate stays the same.
    private static func transition(_ dt: Double) -> Matrix {
        Matrix([[1, dt],
                [0, 1]])
    }

    /// Q: random drift of the rate ("continuous white-noise acceleration" model).
    private func processNoise(_ dt: Double) -> Matrix {
        let perSecond = config.trendChangePerMinute / 60             // bpm/s per minute
        let intensity = perSecond * perSecond / 60                    // (bpm/s)² per second
        return intensity * Matrix([[dt * dt * dt / 3, dt * dt / 2],
                                   [dt * dt / 2, dt]])
    }

    private func isLongGap(until time: Timestamp) -> Bool {
        guard let last = lastTime else { return false }
        return time - last > config.restartAfterGapSeconds
    }

    private mutating func start(at value: Double, time: Timestamp, measurementSD: Double,
                                trendPerSecond: Double = 0) {
        let trendSD = config.initialTrendSDBPMPerMinute / 60
        filter = KalmanFilter(state: Matrix.column([value, trendPerSecond]),
                              covariance: Matrix([[measurementSD * measurementSD, 0],
                                                  [0, trendSD * trendSD]]))
        lastTime = time
        consecutiveRejections = 0
    }

    private func estimate(at time: Timestamp, decision: MeasurementDecision) -> ExcessHeartRateEstimate? {
        guard let filter else { return nil }
        return ExcessHeartRateEstimate(
            time: time,
            excessBPM: filter.state[0, 0],
            trendBPMPerMinute: filter.state[1, 0] * 60,
            excessSDBPM: max(0, filter.covariance[0, 0]).squareRoot(),
            trendSDBPMPerMinute: max(0, filter.covariance[1, 1]).squareRoot() * 60,
            decision: decision)
    }
}
