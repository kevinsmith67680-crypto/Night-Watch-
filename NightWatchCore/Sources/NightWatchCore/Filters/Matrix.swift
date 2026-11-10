import Foundation

/// A small grid of numbers with the matrix maths a Kalman filter needs.
/// Written in plain Swift so it runs and tests anywhere. Values are stored row by row.
public struct Matrix: Equatable, Sendable, CustomStringConvertible {
    public let rows: Int
    public let columns: Int
    public private(set) var values: [Double]

    public init(rows: Int, columns: Int, values: [Double]) {
        precondition(rows > 0 && columns > 0 && values.count == rows * columns,
                     "Matrix size doesn't match the number of values")
        self.rows = rows
        self.columns = columns
        self.values = values
    }

    /// Build from rows, e.g. Matrix([[1, 2], [3, 4]]).
    public init(_ grid: [[Double]]) {
        let columns = grid.first?.count ?? 0
        precondition(grid.allSatisfy { $0.count == columns }, "Every row must be the same length")
        self.init(rows: grid.count, columns: columns, values: grid.flatMap { $0 })
    }

    /// A single column, e.g. a state vector.
    public static func column(_ values: [Double]) -> Matrix {
        Matrix(rows: values.count, columns: 1, values: values)
    }

    public static func zeros(rows: Int, columns: Int) -> Matrix {
        Matrix(rows: rows, columns: columns, values: [Double](repeating: 0, count: rows * columns))
    }

    public static func identity(_ size: Int) -> Matrix {
        var matrix = zeros(rows: size, columns: size)
        for i in 0..<size { matrix[i, i] = 1 }
        return matrix
    }

    public subscript(row: Int, column: Int) -> Double {
        get { values[row * columns + column] }
        set { values[row * columns + column] = newValue }
    }

    public var transposed: Matrix {
        var result = Matrix.zeros(rows: columns, columns: rows)
        for r in 0..<rows {
            for c in 0..<columns { result[c, r] = self[r, c] }
        }
        return result
    }

    public static func + (lhs: Matrix, rhs: Matrix) -> Matrix {
        precondition(lhs.rows == rhs.rows && lhs.columns == rhs.columns, "Sizes must match to add")
        return Matrix(rows: lhs.rows, columns: lhs.columns, values: zip(lhs.values, rhs.values).map { $0 + $1 })
    }

    public static func - (lhs: Matrix, rhs: Matrix) -> Matrix {
        precondition(lhs.rows == rhs.rows && lhs.columns == rhs.columns, "Sizes must match to subtract")
        return Matrix(rows: lhs.rows, columns: lhs.columns, values: zip(lhs.values, rhs.values).map { $0 - $1 })
    }

    public static func * (lhs: Matrix, rhs: Matrix) -> Matrix {
        precondition(lhs.columns == rhs.rows, "Left columns must equal right rows to multiply")
        var result = Matrix.zeros(rows: lhs.rows, columns: rhs.columns)
        for r in 0..<lhs.rows {
            for c in 0..<rhs.columns {
                var sum = 0.0
                for k in 0..<lhs.columns { sum += lhs[r, k] * rhs[k, c] }
                result[r, c] = sum
            }
        }
        return result
    }

    public static func * (scale: Double, matrix: Matrix) -> Matrix {
        Matrix(rows: matrix.rows, columns: matrix.columns, values: matrix.values.map { scale * $0 })
    }

    /// The inverse (Gauss–Jordan elimination), or nil if the matrix can't be inverted.
    public func inverted() -> Matrix? {
        guard rows == columns else { return nil }
        let n = rows
        var a = self
        var inverse = Matrix.identity(n)
        for column in 0..<n {
            // Use the row with the biggest value in this column, for accuracy.
            var pivot = column
            for r in column..<n where abs(a[r, column]) > abs(a[pivot, column]) { pivot = r }
            guard abs(a[pivot, column]) > 1e-12 else { return nil }
            if pivot != column {
                for c in 0..<n {
                    let t = a[column, c]; a[column, c] = a[pivot, c]; a[pivot, c] = t
                    let u = inverse[column, c]; inverse[column, c] = inverse[pivot, c]; inverse[pivot, c] = u
                }
            }
            let divisor = a[column, column]
            for c in 0..<n {
                a[column, c] /= divisor
                inverse[column, c] /= divisor
            }
            for r in 0..<n where r != column {
                let factor = a[r, column]
                if factor == 0 { continue }
                for c in 0..<n {
                    a[r, c] -= factor * a[column, c]
                    inverse[r, c] -= factor * inverse[column, c]
                }
            }
        }
        return inverse
    }

    /// The determinant (Gaussian elimination), or nil if the matrix isn't square.
    public var determinant: Double? {
        guard rows == columns else { return nil }
        let n = rows
        var a = self
        var result = 1.0
        for column in 0..<n {
            var pivot = column
            for r in column..<n where abs(a[r, column]) > abs(a[pivot, column]) { pivot = r }
            if abs(a[pivot, column]) < 1e-300 { return 0 }
            if pivot != column {
                for c in 0..<n {
                    let t = a[column, c]; a[column, c] = a[pivot, c]; a[pivot, c] = t
                }
                result = -result
            }
            result *= a[column, column]
            for r in (column + 1)..<n {
                let factor = a[r, column] / a[column, column]
                for c in column..<n { a[r, c] -= factor * a[column, c] }
            }
        }
        return result
    }

    public var description: String {
        (0..<rows).map { r in
            (0..<columns).map { c in String(format: "%.4g", self[r, c]) }.joined(separator: "  ")
        }.joined(separator: "\n")
    }
}
