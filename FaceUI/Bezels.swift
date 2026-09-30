import SwiftUI
import FaceKit

/// Qué marca un bisel: cuántas marcas encender y qué números poner.
struct BezelScale {
    let ticks: Int
    let filled: Int?
    let labels: [(index: Int, text: String)]

    static func make(_ bezel: FaceBezel, data: FaceData, second: Double, ticks: Int = 60) -> BezelScale {
        func quarters(_ texts: [String]) -> [(index: Int, text: String)] {
            texts.enumerated().map { (index: (($0.offset + 1) * ticks / 4) % ticks, text: $0.element) }
        }
        switch bezel {
        case .seconds:
            return BezelScale(ticks: 60, filled: Int(second.rounded(.down)),
                              labels: stride(from: 5, through: 60, by: 5).map { (index: $0 % 60, text: "\($0)") })
        case .minutes:
            return BezelScale(ticks: 60, filled: nil, labels: stride(from: 5, through: 60, by: 5).map { (index: $0 % 60, text: "\($0)") })
        case .recovery:
            return BezelScale(ticks: ticks, filled: data.recovery.map { Int((Double($0) / 100 * Double(ticks)).rounded()) },
                              labels: quarters(["25", "50", "75", "100"]))
        case .strain:
            return BezelScale(ticks: ticks, filled: data.strain.map { Int((min(1, $0 / 20) * Double(ticks)).rounded()) },
                              labels: quarters(["5", "10", "15", "20"]))
        case .steps:
            return BezelScale(ticks: ticks, filled: data.steps.map { Int((min(1, Double($0) / 10_000) * Double(ticks)).rounded()) },
                              labels: quarters(["2,5k", "5k", "7,5k", "10k"]))
        case .compass, .none:
            return BezelScale(ticks: ticks, filled: nil, labels: [])
        }
    }
}

/// Bisel pegado al borde de la pantalla (Ultra modular): marcas y números que recorren el rectángulo redondeado.
struct EdgeBezel: View {
    let bezel: FaceBezel
    let data: FaceData
    let second: Double
    let style: FaceStyle
    /// Encender las marcas (no con la pantalla atenuada ni con los segundos apagados).
    let showProgress: Bool

    var body: some View {
        Canvas { context, size in
            let s = size.width / 198
            let inset = 2.5 * s
            let w = size.width - 2 * inset, h = size.height - 2 * inset
            let radius = w * 0.235
            let scale = BezelScale.make(bezel, data: data, second: second)
            func edge(_ i: Int) -> (CGPoint, CGPoint) {
                let p = FaceGeometry.roundedRectPoint(t: Double(i) / Double(scale.ticks), width: w, height: h, radius: radius)
                return (CGPoint(x: inset + p.point.x, y: inset + p.point.y), CGPoint(x: cos(p.angle), y: sin(p.angle)))
            }
            for i in 0..<scale.ticks {
                let (outer, dir) = edge(i)
                let major = i % 5 == 0
                let length = (major ? 7 : 4) * s
                var path = Path()
                path.move(to: outer)
                path.addLine(to: CGPoint(x: outer.x - dir.x * length, y: outer.y - dir.y * length))
                var color = style.tertiary
                if showProgress, let filled = scale.filled {
                    if bezel == .seconds && i == filled { color = style.primary } else if i <= filled && (bezel == .seconds || i < filled) { color = style.accent }
                }
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: (major ? 1.8 : 1.1) * s, lineCap: .round))
            }
            for label in scale.labels {
                let (outer, dir) = edge(label.index)
                let at = CGPoint(x: outer.x - dir.x * 14 * s, y: outer.y - dir.y * 14 * s)
                let lit = showProgress && (scale.filled.map { label.index <= $0 || (label.index == 0 && $0 >= scale.ticks - 1) } ?? false)
                context.draw(Text(label.text).font(.system(size: 8.5 * s, weight: .semibold, design: .rounded))
                                .foregroundStyle(lit ? style.primary : style.secondary), at: at, anchor: .center)
            }
        }
    }
}

/// Aro de una esfera redonda: minutos, brújula (gira con el rumbo) o un dato.
struct DialBezel: View {
    let bezel: FaceBezel
    let data: FaceData
    let second: Double
    let style: FaceStyle
    let showProgress: Bool

    var body: some View {
        Canvas { context, size in
            let s = size.width / 198
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2 - 1.5 * s
            func point(_ angle: Double, _ r: CGFloat) -> CGPoint {
                CGPoint(x: center.x + r * sin(angle), y: center.y - r * cos(angle))
            }
            func tick(_ angle: Double, _ length: CGFloat, _ width: CGFloat, _ color: Color) {
                var p = Path()
                p.move(to: point(angle, radius))
                p.addLine(to: point(angle, radius - length))
                context.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
            }
            switch bezel {
            case .compass:
                // Cada 5 grados; N, E, S, O y los números cada 30. Gira para que la N apunte al norte.
                let rotation = -(data.heading ?? 0) * Double.pi / 180
                for i in 0..<72 {
                    let a = Double(i) * 5 * Double.pi / 180 + rotation
                    let major = i % 6 == 0
                    tick(a, (major ? 7 : 3.5) * s, (major ? 1.8 : 1) * s, major ? style.secondary : style.tertiary)
                }
                for k in 0..<12 {
                    let a = Double(k) * 30 * Double.pi / 180 + rotation
                    let cardinal = k % 3 == 0
                    let text = cardinal ? ["N", "E", "S", "O"][k / 3] : "\(k * 30)"
                    let color = k == 0 ? style.accent : (cardinal ? style.primary : style.secondary)
                    context.draw(Text(text).font(.system(size: (cardinal ? 12 : 8.5) * s, weight: cardinal ? .bold : .semibold, design: .rounded))
                                    .foregroundStyle(color), at: point(a, radius - 15 * s), anchor: .center)
                }
            case .minutes, .recovery, .strain, .steps, .seconds:
                let scale = BezelScale.make(bezel, data: data, second: second)
                for i in 0..<scale.ticks {
                    let a = Double(i) / Double(scale.ticks) * 2 * Double.pi
                    let major = i % 5 == 0
                    var color = major ? style.secondary : style.tertiary
                    if showProgress, let filled = scale.filled, i < filled { color = style.accent }
                    tick(a, (major ? 7 : 3.5) * s, (major ? 1.8 : 1) * s, color)
                }
                for label in scale.labels {
                    let a = Double(label.index) / Double(scale.ticks) * 2 * Double.pi
                    context.draw(Text(label.text).font(.system(size: 8.5 * s, weight: .semibold, design: .rounded))
                                    .foregroundStyle(style.secondary), at: point(a, radius - 15 * s), anchor: .center)
                }
            case .none:
                break
            }
        }
    }
}

/// Marcas de las horas: bastones, números, romanos o solo las cuatro principales.
struct HourMarkers: View {
    let dial: FaceDial
    /// Distancia del centro a las marcas (fracción del radio).
    let radiusFraction: CGFloat
    let style: FaceStyle

    var body: some View {
        Canvas { context, size in
            let s = size.width / 198
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2 * radiusFraction
            for h in 1...12 {
                let a = Double(h) / 12 * 2 * Double.pi
                if let text = dial.label(hour: h) {
                    let r = radius - 9 * s
                    let fontSize: CGFloat = dial == .roman ? 11 * s : 14 * s
                    context.draw(Text(text).font(style.valueFont(fontSize, weight: .semibold)).foregroundStyle(h == 12 ? style.accent : style.primary),
                                 at: CGPoint(x: center.x + r * sin(a), y: center.y - r * cos(a)), anchor: .center)
                } else if dial != .minimal || h % 3 == 0 {
                    let long = h % 3 == 0
                    let length = (long ? 14 : 9) * s
                    var p = Path()
                    p.move(to: CGPoint(x: center.x + radius * sin(a), y: center.y - radius * cos(a)))
                    p.addLine(to: CGPoint(x: center.x + (radius - length) * sin(a), y: center.y - (radius - length) * cos(a)))
                    context.stroke(p, with: .color(h == 12 ? style.accent : style.primary), style: StrokeStyle(lineWidth: (long ? 4 : 2.5) * s, lineCap: .round))
                }
            }
        }
    }
}

/// Agujas: horas y minutos del color principal, segundero del color de la esfera.
struct Hands: View {
    let hour: Int
    let minute: Int
    let second: Double
    let showSeconds: Bool
    let style: FaceStyle
    /// Radio disponible (fracción de la mitad del ancho).
    var radiusFraction: CGFloat = 0.8

    var body: some View {
        Canvas { context, size in
            let s = size.width / 198
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2 * radiusFraction
            let angles = FaceGeometry.handAngles(hour: hour, minute: minute, second: second, smoothSeconds: false)
            func hand(_ angle: Double, length: CGFloat, width: CGFloat, color: Color) {
                var ctx = context
                ctx.translateBy(x: center.x, y: center.y)
                ctx.rotate(by: .radians(angle))
                let stem = radius * 0.14
                ctx.fill(Path(roundedRect: CGRect(x: -1.2 * s, y: -stem, width: 2.4 * s, height: stem), cornerRadius: 1.2 * s), with: .color(color))
                ctx.fill(Path(roundedRect: CGRect(x: -width / 2, y: -length, width: width, height: length - stem), cornerRadius: width / 2),
                         with: .color(color))
            }
            hand(angles.hour, length: radius * 0.58, width: 6 * s, color: style.primary)
            hand(angles.minute, length: radius * 0.92, width: 4.5 * s, color: style.primary)
            if showSeconds && !style.dimmed {
                var ctx = context
                ctx.translateBy(x: center.x, y: center.y)
                ctx.rotate(by: .radians(angles.second))
                ctx.fill(Path(CGRect(x: -0.75 * s, y: -radius * 0.98, width: 1.5 * s, height: radius * 1.16)), with: .color(style.accent))
            }
            context.fill(Path(ellipseIn: CGRect(x: center.x - 3.5 * s, y: center.y - 3.5 * s, width: 7 * s, height: 7 * s)),
                         with: .color(showSeconds && !style.dimmed ? style.accent : style.primary))
            context.fill(Path(ellipseIn: CGRect(x: center.x - 1.5 * s, y: center.y - 1.5 * s, width: 3 * s, height: 3 * s)), with: .color(.black))
        }
    }
}
