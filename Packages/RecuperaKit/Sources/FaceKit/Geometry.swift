import Foundation

/// Un punto en la pantalla (y hacia abajo, como en SwiftUI).
public struct FacePoint: Sendable, Hashable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// Cuentas del dibujo que no dependen de SwiftUI (y así se prueban en Linux).
public enum FaceGeometry {
    /// Punto del borde de un rectángulo redondeado (`width` × `height`, esquinas de radio `radius`) a una fracción `t` de su
    /// perímetro, empezando arriba en el centro y en el sentido de las agujas del reloj. Devuelve también hacia dónde mira
    /// el borde hacia fuera (radianes; 0 = derecha, π/2 = abajo), para orientar las marcas del bisel.
    public static func roundedRectPoint(t: Double, width w: Double, height h: Double, radius: Double) -> (point: FacePoint, angle: Double) {
        let r = max(0, min(radius, min(w, h) / 2))
        let straightW = w - 2 * r, straightH = h - 2 * r
        let arc = Double.pi * r / 2
        let perimeter = 2 * straightW + 2 * straightH + 4 * arc
        guard perimeter > 0 else { return (FacePoint(x: w / 2, y: h / 2), -Double.pi / 2) }
        var s = (t - t.rounded(.down)) * perimeter

        func arcPoint(cx: Double, cy: Double, from start: Double, _ s: Double) -> (FacePoint, Double) {
            let a = start + (r > 0 ? s / r : 0)
            return (FacePoint(x: cx + r * cos(a), y: cy + r * sin(a)), a)
        }
        // Tramos: mitad derecha de arriba, esquina, derecha, esquina, abajo, esquina, izquierda, esquina y mitad izquierda de arriba.
        let half = straightW / 2
        if s <= half { return (FacePoint(x: w / 2 + s, y: 0), -Double.pi / 2) }
        s -= half
        if s <= arc { return arcPoint(cx: w - r, cy: r, from: -Double.pi / 2, s) }
        s -= arc
        if s <= straightH { return (FacePoint(x: w, y: r + s), 0) }
        s -= straightH
        if s <= arc { return arcPoint(cx: w - r, cy: h - r, from: 0, s) }
        s -= arc
        if s <= straightW { return (FacePoint(x: w - r - s, y: h), Double.pi / 2) }
        s -= straightW
        if s <= arc { return arcPoint(cx: r, cy: h - r, from: Double.pi / 2, s) }
        s -= arc
        if s <= straightH { return (FacePoint(x: 0, y: h - r - s), Double.pi) }
        s -= straightH
        if s <= arc { return arcPoint(cx: r, cy: r, from: Double.pi, s) }
        s -= arc
        return (FacePoint(x: r + min(s, half), y: 0), -Double.pi / 2)
    }

    /// Perímetro del rectángulo redondeado.
    public static func perimeter(width w: Double, height h: Double, radius: Double) -> Double {
        let r = max(0, min(radius, min(w, h) / 2))
        return 2 * (w - 2 * r) + 2 * (h - 2 * r) + 2 * Double.pi * r
    }

    /// Punto a `radius` del centro con `angle` medido como en un reloj: 0 = las 12, creciendo en el sentido de las agujas
    /// (en radianes).
    public static func clockPoint(center: FacePoint, radius: Double, angle: Double) -> FacePoint {
        FacePoint(x: center.x + radius * sin(angle), y: center.y - radius * cos(angle))
    }

    /// Ángulos de las agujas (radianes, 0 = las 12): horas, minutos y segundos.
    public static func handAngles(hour: Int, minute: Int, second: Double, smoothSeconds: Bool = true)
        -> (hour: Double, minute: Double, second: Double) {
        let s = smoothSeconds ? second : second.rounded(.down)
        let m = Double(minute) + s / 60
        let h = Double(hour % 12) + m / 60
        return (h / 12 * 2 * Double.pi, m / 60 * 2 * Double.pi, s / 60 * 2 * Double.pi)
    }
}
