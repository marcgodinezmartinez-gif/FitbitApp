import Foundation

/// Utilidades estadísticas puras y deterministas.
public enum Stats {
    public static func mean(_ xs: [Double]) -> Double? {
        guard !xs.isEmpty else { return nil }
        return xs.reduce(0, +) / Double(xs.count)
    }

    /// Desviación típica muestral (n − 1).
    public static func sd(_ xs: [Double]) -> Double? {
        guard xs.count > 1, let m = mean(xs) else { return nil }
        let v = xs.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(xs.count - 1)
        return v.squareRoot()
    }

    public static func median(_ xs: [Double]) -> Double? {
        guard !xs.isEmpty else { return nil }
        let s = xs.sorted()
        let n = s.count
        return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2
    }

    /// σ robusta = 1,4826 · MAD (ALG-BAS-01).
    public static func robustSigma(_ xs: [Double]) -> Double? {
        guard let m = median(xs) else { return nil }
        guard let mad = median(xs.map { abs($0 - m) }) else { return nil }
        return 1.4826 * mad
    }

    /// Percentil p ∈ [0, 100] con interpolación lineal.
    public static func percentile(_ xs: [Double], _ p: Double) -> Double? {
        guard !xs.isEmpty else { return nil }
        let s = xs.sorted()
        if s.count == 1 { return s[0] }
        let rank = min(max(p, 0), 100) / 100 * Double(s.count - 1)
        let lo = Int(rank.rounded(.down))
        let hi = min(lo + 1, s.count - 1)
        let f = rank - Double(lo)
        return s[lo] + (s[hi] - s[lo]) * f
    }

    public static func clip(_ x: Double, _ lo: Double, _ hi: Double) -> Double { min(max(x, lo), hi) }

    /// Función de distribución normal estándar Φ.
    public static func normalCDF(_ x: Double) -> Double { 0.5 * (1 + erf(x / 2.0.squareRoot())) }

    public static func pearson(_ xs: [Double], _ ys: [Double]) -> Double? {
        guard xs.count == ys.count, xs.count > 2, let mx = mean(xs), let my = mean(ys) else { return nil }
        var sxy = 0.0, sxx = 0.0, syy = 0.0
        for i in xs.indices {
            let dx = xs[i] - mx, dy = ys[i] - my
            sxy += dx * dy
            sxx += dx * dx
            syy += dy * dy
        }
        guard sxx > 0, syy > 0 else { return nil }
        return sxy / (sxx * syy).squareRoot()
    }

    /// Mínimos cuadrados: devuelve los coeficientes β para X (filas = observaciones, con la columna
    /// de unos ya incluida) e y. Resuelve (XᵀX)β = Xᵀy por eliminación gaussiana con pivote.
    public static func ols(_ x: [[Double]], _ y: [Double]) -> [Double]? {
        guard let p = x.first?.count, p > 0, x.count == y.count, x.count >= p else { return nil }
        var a = Array(repeating: Array(repeating: 0.0, count: p + 1), count: p)
        for (row, yi) in zip(x, y) {
            for i in 0..<p {
                for j in 0..<p { a[i][j] += row[i] * row[j] }
                a[i][p] += row[i] * yi
            }
        }
        for col in 0..<p {
            var pivot = col
            for r in col..<p where abs(a[r][col]) > abs(a[pivot][col]) { pivot = r }
            guard abs(a[pivot][col]) > 1e-12 else { return nil }
            a.swapAt(col, pivot)
            for r in 0..<p where r != col {
                let f = a[r][col] / a[col][col]
                if f == 0 { continue }
                for c in col...p { a[r][c] -= f * a[col][c] }
            }
        }
        return (0..<p).map { a[$0][p] / a[$0][$0] }
    }
}

/// Generador pseudoaleatorio determinista (SplitMix64) para *bootstrap* reproducible.
public struct SeededGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) { state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
