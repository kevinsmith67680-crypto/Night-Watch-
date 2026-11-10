import Foundation

/// Splits a signal into its frequencies and says how much "power" (energy per
/// second) is at each one.
///
/// Example: a wrist tremor at 9 Hz shows up as a sharp spike at 9 Hz; dancing
/// shows up as big power around 1–3 Hz.
///
/// How it works (a "periodogram"):
///   1. subtract the average, so a constant offset doesn't count as movement;
///   2. multiply by a smooth bell-shaped "Hann window" so the abrupt start and
///      end of the 5-second chunk don't create fake frequencies;
///   3. compare the signal with a sine wave at each frequency (a Fourier transform).
///
/// Scaling: adding up `binPower` over a band gives the mean-square value of the
/// signal in that band. So a sine wave of amplitude A gives A²/2, and the
/// square root of a band's power is the RMS (typical size) of the signal there.
///
/// Several axes (x, y, z) can be passed in; their powers are added, so the
/// result doesn't depend on how the watch is rotated.
public struct Spectrum: Sendable {
    /// Frequency of each bin, in Hz: 0, 0.2, 0.4 … up to half the sample rate.
    public let frequencies: [Double]
    /// Power in each bin, in (signal units)².
    public let binPower: [Double]

    public init(axes: [[Double]], sampleRateHz: Double) {
        let n = axes.map { $0.count }.min() ?? 0
        guard n >= 2, sampleRateHz > 0 else {
            self.frequencies = []
            self.binPower = []
            return
        }

        let half = n / 2
        let count = Double(n)

        // Hann window and its total energy (used for scaling).
        let window = (0..<n).map { 0.5 - 0.5 * cos(2 * Double.pi * Double($0) / count) }
        let windowEnergy = window.reduce(0.0) { $0 + $1 * $1 }

        // Pre-computed cos/sin values, reused for every frequency.
        let cosTable = (0..<n).map { cos(2 * Double.pi * Double($0) / count) }
        let sinTable = (0..<n).map { sin(2 * Double.pi * Double($0) / count) }

        var power = [Double](repeating: 0, count: half + 1)

        for axis in axes {
            let mean = axis.prefix(n).reduce(0.0, +) / count
            let x = (0..<n).map { (axis[$0] - mean) * window[$0] }

            for k in 0...half {
                var real = 0.0
                var imaginary = 0.0
                var index = 0                       // (k × i) mod n, without overflow
                for i in 0..<n {
                    real += x[i] * cosTable[index]
                    imaginary -= x[i] * sinTable[index]
                    index += k
                    if index >= n { index -= n }
                }
                let twoSided = (real * real + imaginary * imaginary) / (count * windowEnergy)
                // Positive and negative frequencies are mirror images, so every bin
                // except 0 Hz and the very top one is counted twice.
                let isEdgeBin = (k == 0) || (n % 2 == 0 && k == half)
                power[k] += isEdgeBin ? twoSided : 2 * twoSided
            }
        }

        self.frequencies = (0...half).map { Double($0) * sampleRateHz / count }
        self.binPower = power
    }

    /// Total power in the band from `low` Hz up to (not including) `high` Hz.
    public func bandPower(from low: Double, to high: Double) -> Double {
        var total = 0.0
        for (k, frequency) in frequencies.enumerated() where frequency >= low && frequency < high {
            total += binPower[k]
        }
        return total
    }

    /// The frequency with the most power inside the band, or nil if the band is empty.
    public func peakFrequency(from low: Double, to high: Double) -> Double? {
        var best: Int?
        for (k, frequency) in frequencies.enumerated() where frequency >= low && frequency < high {
            if let current = best, binPower[k] <= binPower[current] { continue }
            best = k
        }
        return best.map { frequencies[$0] }
    }
}
