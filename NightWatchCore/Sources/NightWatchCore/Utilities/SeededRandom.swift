import Foundation

/// A repeatable random-number generator: the same seed always produces the same
/// numbers. Tests and simulator scenarios use it so they give identical results
/// on every run and on every machine.
public struct SeededRandom: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    /// SplitMix64, a small, well-tested generator.
    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A random number from a bell curve with the given mean and standard deviation.
    public mutating func gaussian(mean: Double = 0, standardDeviation: Double = 1) -> Double {
        // Box–Muller method: turns two even random numbers into one bell-curve number.
        let u1 = max(Double.random(in: 0..<1, using: &self), 1e-12)
        let u2 = Double.random(in: 0..<1, using: &self)
        return mean + standardDeviation * (-2 * log(u1)).squareRoot() * cos(2 * Double.pi * u2)
    }
}
