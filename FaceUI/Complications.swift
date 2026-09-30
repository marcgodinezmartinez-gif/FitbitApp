import SwiftUI
import FaceKit

/// Un hueco de la esfera con su dato, en el tamaño del hueco.
struct SlotView: View {
    let kind: SlotKind
    let complication: FaceComplication
    let data: FaceData
    let date: Date
    let style: FaceStyle
    /// Escala respecto a la pantalla de 45 mm.
    let scale: CGFloat
    var width: CGFloat = 0
    var height: CGFloat = 0
    var alignment: HorizontalAlignment = .leading
    var calendar: Calendar = .current

    var body: some View {
        if let value = FaceValues.value(complication, data, now: date, calendar: calendar) {
            switch kind {
            case .circular:
                CircularSlot(complication: complication, value: value, data: data, style: style, diameter: width)
            case .corner:
                CornerSlot(value: value, style: style, scale: scale, alignment: alignment)
            case .rectangular:
                RectangularSlot(complication: complication, value: value, data: data, style: style, scale: scale)
                    .frame(width: width, height: height)
            case .inline:
                InlineSlot(complication: complication, value: value, style: style, scale: scale)
            }
        }
    }
}

/// Redondo: un aro con el dato dentro (o los anillos, la fecha o la brújula).
struct CircularSlot: View {
    let complication: FaceComplication
    let value: FaceValue
    let data: FaceData
    let style: FaceStyle
    let diameter: CGFloat

    var body: some View {
        let d = diameter
        let lw = d * 0.09
        let tint = style.tint(value.tint)
        ZStack {
            switch complication {
            case .activity:
                ActivityRings(rings: data.rings, style: style, lineWidth: d * 0.11)
            case .date:
                VStack(spacing: -d * 0.05) {
                    Text(value.title).font(style.labelFont(d * 0.22)).foregroundStyle(style.accent)
                    Text(value.text).font(style.valueFont(d * 0.44)).foregroundStyle(style.primary)
                }
            case .compass:
                CompassRose(heading: data.heading, style: style, diameter: d)
            default:
                Circle().inset(by: lw / 2).stroke(style.tertiary, lineWidth: lw)
                if let f = value.fraction {
                    Circle().inset(by: lw / 2).trim(from: 0, to: max(0.002, min(1, f)))
                        .stroke(tint, style: StrokeStyle(lineWidth: lw, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                VStack(spacing: 0) {
                    if let symbol = value.symbol {
                        Image(systemName: symbol).font(.system(size: d * 0.19, weight: .semibold)).foregroundStyle(tint)
                    }
                    Text(value.text).font(style.valueFont(d * 0.3)).foregroundStyle(style.primary)
                        .lineLimit(1).minimumScaleFactor(0.5)
                }
                .padding(d * 0.17)
            }
        }
        .frame(width: d, height: d)
    }
}

/// Esquina: rótulo pequeño y cifra.
struct CornerSlot: View {
    let value: FaceValue
    let style: FaceStyle
    let scale: CGFloat
    let alignment: HorizontalAlignment

    var body: some View {
        VStack(alignment: alignment, spacing: 0) {
            HStack(spacing: 2 * scale) {
                if let s = value.symbol { Image(systemName: s).font(.system(size: 8.5 * scale, weight: .bold)) }
                Text(value.title).font(style.labelFont(9 * scale)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .foregroundStyle(style.tint(value.tint))
            Text(value.textWithUnit).font(style.valueFont(15 * scale)).foregroundStyle(style.primary)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
    }
}

/// Rectangular: el hueco grande.
struct RectangularSlot: View {
    let complication: FaceComplication
    let value: FaceValue
    let data: FaceData
    let style: FaceStyle
    let scale: CGFloat

    var body: some View {
        let s = scale
        switch complication {
        case .summary:
            VStack(alignment: .leading, spacing: 4 * s) {
                bar("REC", data.recovery.map { Double($0) / 100 }, data.recovery.map { "\($0) %" }, FaceValues.recoveryTint(data.recoveryZone))
                bar("CARGA", data.strain.map { $0 / 21 }, data.strain.map { FaceValues.decimal($0, digits: 1) }, .strain)
                bar("SUEÑO", data.sleepPerformance.map { Double($0) / 100 }, data.sleepMinutes.map { FaceValues.clockDuration(minutes: $0) }, .sleep)
            }
        case .heartRate:
            HStack(alignment: .bottom, spacing: 6 * s) {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    HStack(alignment: .firstTextBaseline, spacing: 2 * s) {
                        Text(value.text).font(style.valueFont(26 * s)).foregroundStyle(style.primary)
                        if let unit = value.unit { Text(unit).font(style.labelFont(10 * s)).foregroundStyle(style.secondary) }
                    }
                }
                FaceSparkline(values: data.heartRateTrend ?? [], color: style.tint(.heart), dim: style.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: 34 * s)
            }
        case .activity:
            HStack(spacing: 8 * s) {
                ActivityRings(rings: data.rings, style: style, lineWidth: 5.5 * s).frame(width: 46 * s, height: 46 * s)
                VStack(alignment: .leading, spacing: 1 * s) {
                    ring("MOVIMIENTO", data.rings?.move, .move)
                    ring("EJERCICIO", data.rings?.exercise, .exercise)
                    ring("DE PIE", data.rings?.stand, .stand)
                }
                Spacer(minLength: 0)
            }
        default:
            VStack(alignment: .leading, spacing: 1 * s) {
                header
                HStack(alignment: .firstTextBaseline, spacing: 3 * s) {
                    Text(value.text).font(style.valueFont(complication == .workout ? 17 * s : 24 * s)).foregroundStyle(style.primary)
                        .lineLimit(complication == .workout ? 2 : 1).minimumScaleFactor(0.6)
                    if let unit = value.unit { Text(unit).font(style.labelFont(11 * s)).foregroundStyle(style.secondary) }
                }
                if let detail = value.detail {
                    Text(detail).font(style.labelFont(10 * s)).foregroundStyle(style.secondary).lineLimit(1).minimumScaleFactor(0.7)
                }
                if let f = value.fraction, complication != .workout {
                    Capsule().fill(style.tertiary).frame(height: 3.5 * s)
                        .overlay(alignment: .leading) {
                            GeometryReader { g in
                                Capsule().fill(style.tint(value.tint)).frame(width: max(3.5 * s, g.size.width * min(1, f)))
                            }
                        }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        HStack(spacing: 3 * scale) {
            if let symbol = value.symbol { Image(systemName: symbol).font(.system(size: 10 * scale, weight: .bold)) }
            Text(value.title).font(style.labelFont(10 * scale)).lineLimit(1)
        }
        .foregroundStyle(style.tint(value.tint))
    }

    private func bar(_ label: String, _ fraction: Double?, _ text: String?, _ tint: FaceTint) -> some View {
        let s = scale
        return HStack(spacing: 5 * s) {
            Text(label).font(style.labelFont(9 * s)).foregroundStyle(style.secondary).frame(width: 40 * s, alignment: .leading)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(style.tertiary)
                    Capsule().fill(style.tint(tint)).frame(width: max(4 * s, g.size.width * min(1, fraction ?? 0)))
                        .opacity(fraction == nil ? 0 : 1)
                }
            }
            .frame(height: 5 * s)
            Text(text ?? FaceValues.missing).font(style.valueFont(12 * s)).foregroundStyle(style.primary)
                .frame(width: 42 * s, alignment: .trailing).lineLimit(1).minimumScaleFactor(0.6)
        }
    }

    private func ring(_ label: String, _ fraction: Double?, _ tint: FaceTint) -> some View {
        HStack(spacing: 4 * scale) {
            Text(label).font(style.labelFont(8.5 * scale)).foregroundStyle(style.tint(tint))
            Text(fraction.map { "\(Int(($0 * 100).rounded())) %" } ?? FaceValues.missing).font(style.valueFont(11 * scale))
                .foregroundStyle(style.primary)
        }
    }
}

/// Una línea de texto (arriba o abajo de la esfera).
struct InlineSlot: View {
    let complication: FaceComplication
    let value: FaceValue
    let style: FaceStyle
    let scale: CGFloat

    var body: some View {
        HStack(spacing: 4 * scale) {
            if let symbol = value.symbol {
                Image(systemName: symbol).font(.system(size: 10 * scale, weight: .bold)).foregroundStyle(style.tint(value.tint))
            }
            Text(text).font(style.labelFont(11.5 * scale)).foregroundStyle(style.primary).lineLimit(1).minimumScaleFactor(0.6)
        }
    }

    private var text: String {
        switch complication {
        case .date: return [value.title, value.text, value.detail].compactMap { $0 }.joined(separator: " ")
        case .summary: return value.text
        case .workout: return [value.text, value.detail].compactMap { $0 }.joined(separator: " · ")
        case .race: return "\(value.textWithUnit) · \(value.title.capitalized)"
        case .weather: return [value.text, value.detail].compactMap { $0 }.joined(separator: " ")
        default: return "\(value.title) \(value.textWithUnit)"
        }
    }
}

/// Los tres anillos de actividad.
struct ActivityRings: View {
    let rings: FaceRings?
    let style: FaceStyle
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            ring(rings?.move, .move, inset: 0)
            ring(rings?.exercise, .exercise, inset: lineWidth * 1.15)
            ring(rings?.stand, .stand, inset: lineWidth * 2.3)
        }
    }

    private func ring(_ fraction: Double?, _ tint: FaceTint, inset: CGFloat) -> some View {
        let color = style.tint(tint)
        return ZStack {
            Circle().inset(by: inset + lineWidth / 2).stroke(color.opacity(0.25), lineWidth: lineWidth)
            Circle().inset(by: inset + lineWidth / 2).trim(from: 0, to: max(0.002, min(1, fraction ?? 0)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .opacity(fraction == nil ? 0 : 1)
        }
    }
}

/// Línea del pulso de la última hora.
struct FaceSparkline: View {
    let values: [Double]
    let color: Color
    let dim: Color

    var body: some View {
        Canvas { context, size in
            guard values.count >= 2, let lo = values.min(), let hi = values.max() else {
                context.stroke(Path { p in p.move(to: CGPoint(x: 0, y: size.height / 2)); p.addLine(to: CGPoint(x: size.width, y: size.height / 2)) },
                               with: .color(dim), lineWidth: 1)
                return
            }
            let span = max(hi - lo, 10)
            var path = Path()
            for (i, v) in values.enumerated() {
                let pt = CGPoint(x: size.width * CGFloat(i) / CGFloat(values.count - 1),
                                 y: size.height * (1 - CGFloat((v - lo) / span)) * 0.9 + size.height * 0.05)
                if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
            }
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            if let last = values.last {
                let y = size.height * (1 - CGFloat((last - lo) / span)) * 0.9 + size.height * 0.05
                context.fill(Path(ellipseIn: CGRect(x: size.width - 3, y: y - 3, width: 6, height: 6)), with: .color(color))
            }
        }
    }
}

/// Rosa de los vientos pequeña: la N apunta al norte de verdad.
struct CompassRose: View {
    let heading: Double?
    let style: FaceStyle
    let diameter: CGFloat

    var body: some View {
        let d = diameter
        let rotation = -(heading ?? 0)
        ZStack {
            Circle().inset(by: d * 0.04).stroke(style.tertiary, lineWidth: d * 0.06)
            ForEach(0..<4, id: \.self) { k in
                let angle = Angle.degrees(Double(k) * 90 + rotation)
                Text(["N", "E", "S", "O"][k]).font(style.labelFont(d * 0.2))
                    .foregroundStyle(k == 0 ? style.accent : style.secondary)
                    .offset(x: sin(angle.radians) * d * 0.31, y: -cos(angle.radians) * d * 0.31)
            }
            Text(heading.map { "\(Int($0.rounded()) % 360)°" } ?? FaceValues.missing).font(style.valueFont(d * 0.19))
                .foregroundStyle(style.primary)
        }
        .frame(width: d, height: d)
    }
}
