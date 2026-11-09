import Foundation

/// A simple 3-D vector (x, y, z).
///
/// Used for acceleration, gravity and rotation rate. We use our own type
/// instead of Apple's `simd` so the code also builds and tests on any machine.
public struct Vector3: Equatable, Codable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    public static let zero = Vector3(x: 0, y: 0, z: 0)

    /// Length of the vector: √(x² + y² + z²).
    public var magnitude: Double {
        (x * x + y * y + z * z).squareRoot()
    }
}
