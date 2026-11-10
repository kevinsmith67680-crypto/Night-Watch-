import Foundation

/// How surprising a measurement was, compared with what the filter expected.
public struct Innovation: Equatable, Sendable {
    /// Measurement minus prediction (y = z − H·x).
    public let residual: Matrix
    /// How big that difference is expected to be (S = H·P·Hᵀ + R).
    public let covariance: Matrix
    /// The surprise squared, in standard deviations (yᵀ·S⁻¹·y). 16 means "4 SD away".
    public let normalizedSquared: Double
    /// How likely the measurement was under this filter's model.
    /// The IMM filter will compare this between its competing models.
    public let likelihood: Double
}

/// A standard linear Kalman filter, written generally so the IMM filter can
/// later run several of these side by side with different models.
///
/// Each step has two halves:
///   • predict: move the state forward in time (x = F·x) and grow its
///     uncertainty (P = F·P·Fᵀ + Q);
///   • update: blend in a measurement, weighting it by how much each side is trusted.
public struct KalmanFilter: Sendable {
    /// Current best estimate (a column).
    public private(set) var state: Matrix
    /// Uncertainty of that estimate.
    public private(set) var covariance: Matrix

    public init(state: Matrix, covariance: Matrix) {
        precondition(state.columns == 1, "State must be a single column")
        precondition(covariance.rows == state.rows && covariance.columns == state.rows,
                     "Covariance must be square and match the state size")
        self.state = state
        self.covariance = covariance
    }

    /// Predict step.
    /// - transition: F, how the state evolves on its own.
    /// - processNoise: Q, how much new uncertainty that adds.
    public mutating func predict(transition: Matrix, processNoise: Matrix) {
        state = transition * state
        covariance = transition * covariance * transition.transposed + processNoise
    }

    /// Works out how surprising a measurement is, without changing anything.
    /// - observation: H, which part of the state the measurement sees.
    /// - measurementNoise: R, how noisy the measurement is.
    public func innovation(measurement: Matrix, observation: Matrix, measurementNoise: Matrix) -> Innovation? {
        let residual = measurement - observation * state
        let expectedSpread = observation * covariance * observation.transposed + measurementNoise
        guard let inverse = expectedSpread.inverted(),
              let determinant = expectedSpread.determinant, determinant > 0
        else { return nil }

        let normalizedSquared = (residual.transposed * inverse * residual)[0, 0]
        let dimensions = Double(residual.rows)
        let likelihood = exp(-0.5 * normalizedSquared)
            / (pow(2 * Double.pi, dimensions) * determinant).squareRoot()
        return Innovation(residual: residual,
                          covariance: expectedSpread,
                          normalizedSquared: normalizedSquared,
                          likelihood: likelihood)
    }

    /// Update step: blends the measurement into the state.
    /// Returns the innovation, or nil if the maths failed (nothing is changed then).
    @discardableResult
    public mutating func update(measurement: Matrix, observation: Matrix, measurementNoise: Matrix) -> Innovation? {
        guard let result = innovation(measurement: measurement,
                                      observation: observation,
                                      measurementNoise: measurementNoise),
              let inverse = result.covariance.inverted()
        else { return nil }

        // Kalman gain: how far to move towards the measurement.
        let gain = covariance * observation.transposed * inverse
        state = state + gain * result.residual

        // "Joseph form" covariance update: the numerically safest way to shrink P.
        let factor = Matrix.identity(state.rows) - gain * observation
        covariance = factor * covariance * factor.transposed + gain * measurementNoise * gain.transposed
        return result
    }
}
