import SwiftUI
import FaceKit

/// Una esfera dibujada a pantalla completa. El reloj la redibuja cada segundo (o cada minuto con la pantalla atenuada);
/// la vista previa del iPhone, igual.
struct FaceView: View {
    let design: FaceDesign
    let data: FaceData
    let date: Date
    var night: Bool = false
    /// Pantalla siempre activa con la muñeca bajada: sin segundero y con menos brillo.
    var dimmed: Bool = false
    var calendar: Calendar = .current

    var body: some View {
        let style = FaceStyle(design: design, night: night, dimmed: dimmed)
        ZStack {
            FaceBackgroundView(background: design.background, style: style)
            switch design.template {
            case .ultraModular: UltraModularFace(design: design, data: data, date: date, style: style, calendar: calendar)
            case .wayfinder: WayfinderFace(design: design, data: data, date: date, style: style, calendar: calendar)
            case .recovery: RecoveryFace(design: design, data: data, date: date, style: style, calendar: calendar)
            case .analog: AnalogFace(design: design, data: data, date: date, style: style, calendar: calendar)
            case .digital: DigitalFace(design: design, data: data, date: date, style: style, calendar: calendar)
            }
        }
    }
}

/// Coloca vistas en coordenadas de la pantalla de 45 mm (198 × 242) escaladas al tamaño real.
private struct FaceLayout {
    let size: CGSize
    var sx: CGFloat { size.width / 198 }
    var sy: CGFloat { size.height / 242 }
    /// Escala para tamaños (la menor de las dos).
    var s: CGFloat { min(sx, sy) }
    func x(_ v: CGFloat) -> CGFloat { v * sx }
    func y(_ v: CGFloat) -> CGFloat { v * sy }
}

// MARK: - Ultra modular

/// Hora grande arriba a la izquierda, bisel al borde de la pantalla, un hueco redondo arriba, uno grande en el centro y
/// tres redondos abajo (al estilo del Modular Ultra).
struct UltraModularFace: View {
    let design: FaceDesign
    let data: FaceData
    let date: Date
    let style: FaceStyle
    let calendar: Calendar

    var body: some View {
        GeometryReader { geo in
            let l = FaceLayout(size: geo.size)
            let clock = FaceValues.clock(date, use24h: design.use24h, calendar: calendar)
            ZStack {
                if design.bezel != .none {
                    EdgeBezel(bezel: design.bezel, data: data, second: clock.second, style: style,
                              showProgress: !style.dimmed && (design.bezel != .seconds || design.showSeconds))
                }
                Text("\(clock.hours):\(clock.minutes)")
                    .font(style.timeFont(56 * l.s))
                    .foregroundStyle(style.accent)
                    .lineLimit(1).minimumScaleFactor(0.3)
                    .frame(width: l.x(110), height: l.y(58), alignment: .leading)
                    .position(x: l.x(26 + 55), y: l.y(51))
                slot("topRight", .circular, diameter: 40 * l.s).position(x: l.x(154), y: l.y(46))
                SlotView(kind: .rectangular, complication: design.complication("center"), data: data, date: date, style: style, scale: l.s,
                         width: l.x(148), height: l.y(62), calendar: calendar)
                    .position(x: l.x(99), y: l.y(116))
                slot("bottomLeft", .circular, diameter: 46 * l.s).position(x: l.x(46), y: l.y(184))
                slot("bottomCenter", .circular, diameter: 46 * l.s).position(x: l.x(99), y: l.y(184))
                slot("bottomRight", .circular, diameter: 46 * l.s).position(x: l.x(152), y: l.y(184))
            }
        }
    }

    private func slot(_ id: String, _ kind: SlotKind, diameter: CGFloat) -> some View {
        SlotView(kind: kind, complication: design.complication(id), data: data, date: date, style: style, scale: diameter / 46,
                 width: diameter, height: diameter, calendar: calendar)
    }
}

// MARK: - Explorador (al estilo Wayfinder)

/// Esfera redonda con bisel de brújula o de minutos, agujas, cuatro esquinas y tres subesferas.
struct WayfinderFace: View {
    let design: FaceDesign
    let data: FaceData
    let date: Date
    let style: FaceStyle
    let calendar: Calendar

    var body: some View {
        GeometryReader { geo in
            let l = FaceLayout(size: geo.size)
            let clock = FaceValues.clock(date, use24h: true, calendar: calendar)
            let dial = min(geo.size.width, geo.size.height) - 2 * l.s
            ZStack {
                Group {
                    Circle().fill(Color.white.opacity(style.night || style.dimmed ? 0 : 0.035))
                    DialBezel(bezel: design.bezel, data: data, second: clock.second, style: style, showProgress: !style.dimmed)
                    HourMarkers(dial: design.dial, radiusFraction: design.bezel == .none ? 0.95 : 0.76, style: style)
                    subdial("dialLeft", x: -38, y: 0, l: l)
                    subdial("dialRight", x: 38, y: 0, l: l)
                    subdial("dialBottom", x: 0, y: 40, l: l)
                    Hands(hour: clock.hour, minute: clock.minute, second: clock.second, showSeconds: design.showSeconds, style: style,
                          radiusFraction: design.bezel == .none ? 0.9 : 0.74)
                }
                .frame(width: dial, height: dial)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
                // En las esquinas, apartado del borde: la pantalla también es redondeada.
                corner("topLeft", .leading, l: l).position(x: l.x(44), y: l.y(21))
                corner("topRight", .trailing, l: l).position(x: l.x(154), y: l.y(21))
                corner("bottomLeft", .leading, l: l).position(x: l.x(44), y: l.y(221))
                corner("bottomRight", .trailing, l: l).position(x: l.x(154), y: l.y(221))
            }
        }
    }

    private func subdial(_ id: String, x: CGFloat, y: CGFloat, l: FaceLayout) -> some View {
        SlotView(kind: .circular, complication: design.complication(id), data: data, date: date, style: style, scale: l.s,
                 width: 36 * l.s, height: 36 * l.s, calendar: calendar)
            .offset(x: x * l.s, y: y * l.s)
    }

    private func corner(_ id: String, _ alignment: HorizontalAlignment, l: FaceLayout) -> some View {
        SlotView(kind: .corner, complication: design.complication(id), data: data, date: date, style: style, scale: l.s,
                 alignment: alignment, calendar: calendar)
            .frame(width: 54 * l.s, alignment: alignment == .leading ? .leading : .trailing)
    }
}

// MARK: - Recuperación

/// La hora arriba y la recuperación en un anillo grande, con la carga y el sueño por dentro.
struct RecoveryFace: View {
    let design: FaceDesign
    let data: FaceData
    let date: Date
    let style: FaceStyle
    let calendar: Calendar

    var body: some View {
        GeometryReader { geo in
            let l = FaceLayout(size: geo.size)
            let clock = FaceValues.clock(date, use24h: design.use24h, calendar: calendar)
            let d = 118 * l.s
            let zone = FaceValues.recoveryTint(data.recoveryZone)
            ZStack {
                SlotView(kind: .inline, complication: design.complication("top"), data: data, date: date, style: style, scale: l.s,
                         calendar: calendar)
                    .frame(width: l.x(170)).position(x: l.x(99), y: l.y(17))
                Text("\(clock.hours):\(clock.minutes)")
                    .font(style.timeFont(40 * l.s)).foregroundStyle(style.primary)
                    .lineLimit(1).minimumScaleFactor(0.4).frame(width: l.x(170))
                    .position(x: l.x(99), y: l.y(52))
                ZStack {
                    ring(data.recovery.map { Double($0) / 100 }, style.tint(zone), width: 11 * l.s, inset: 0)
                    ring(data.strain.map { $0 / 21 }, style.tint(.strain), width: 7 * l.s, inset: 14 * l.s)
                    ring(data.sleepPerformance.map { Double($0) / 100 }, style.tint(.sleep), width: 7 * l.s, inset: 24 * l.s)
                    VStack(spacing: -2 * l.s) {
                        Text(data.recovery.map { "\($0)" } ?? FaceValues.missing).font(style.valueFont(30 * l.s, weight: .bold))
                            .foregroundStyle(style.tint(zone))
                        Text("% REC").font(style.labelFont(9 * l.s)).foregroundStyle(style.secondary)
                    }
                }
                .frame(width: d, height: d)
                .position(x: l.x(99), y: l.y(142))
                SlotView(kind: .corner, complication: design.complication("bottomLeft"), data: data, date: date, style: style, scale: l.s,
                         alignment: .leading, calendar: calendar)
                    .frame(width: l.x(80), alignment: .leading).position(x: l.x(60), y: l.y(221))
                SlotView(kind: .corner, complication: design.complication("bottomRight"), data: data, date: date, style: style, scale: l.s,
                         alignment: .trailing, calendar: calendar)
                    .frame(width: l.x(80), alignment: .trailing).position(x: l.x(138), y: l.y(221))
            }
        }
    }

    private func ring(_ fraction: Double?, _ color: Color, width: CGFloat, inset: CGFloat) -> some View {
        ZStack {
            Circle().inset(by: inset + width / 2).stroke(color.opacity(0.22), lineWidth: width)
            Circle().inset(by: inset + width / 2).trim(from: 0, to: max(0.002, min(1, fraction ?? 0)))
                .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .opacity(fraction == nil ? 0 : 1)
        }
    }
}

// MARK: - Clásica

/// Agujas con bastones, números o romanos, con un dato arriba y otro abajo.
struct AnalogFace: View {
    let design: FaceDesign
    let data: FaceData
    let date: Date
    let style: FaceStyle
    let calendar: Calendar

    var body: some View {
        GeometryReader { geo in
            let l = FaceLayout(size: geo.size)
            let clock = FaceValues.clock(date, use24h: true, calendar: calendar)
            let dial = min(geo.size.width, geo.size.height) - 4 * l.s
            ZStack {
                if design.bezel == .minutes {
                    DialBezel(bezel: .minutes, data: data, second: clock.second, style: style, showProgress: false)
                }
                HourMarkers(dial: design.dial, radiusFraction: design.bezel == .minutes ? 0.8 : 0.94, style: style)
                SlotView(kind: .circular, complication: design.complication("top"), data: data, date: date, style: style, scale: l.s,
                         width: 40 * l.s, height: 40 * l.s, calendar: calendar)
                    .offset(y: -44 * l.s)
                SlotView(kind: .circular, complication: design.complication("bottom"), data: data, date: date, style: style, scale: l.s,
                         width: 40 * l.s, height: 40 * l.s, calendar: calendar)
                    .offset(y: 44 * l.s)
                Hands(hour: clock.hour, minute: clock.minute, second: clock.second, showSeconds: design.showSeconds, style: style,
                      radiusFraction: design.bezel == .minutes ? 0.78 : 0.9)
            }
            .frame(width: dial, height: dial)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
    }
}

// MARK: - Digital XL

/// Las horas y los minutos enormes, uno encima del otro, con una línea de datos arriba y otra abajo.
struct DigitalFace: View {
    let design: FaceDesign
    let data: FaceData
    let date: Date
    let style: FaceStyle
    let calendar: Calendar

    var body: some View {
        GeometryReader { geo in
            let l = FaceLayout(size: geo.size)
            let clock = FaceValues.clock(date, use24h: design.use24h, calendar: calendar)
            ZStack {
                SlotView(kind: .inline, complication: design.complication("top"), data: data, date: date, style: style, scale: l.s,
                         calendar: calendar)
                    .frame(width: l.x(176)).position(x: l.x(99), y: l.y(15))
                Text(clock.hours).font(style.timeFont(104 * l.s)).foregroundStyle(style.primary)
                    .lineLimit(1).minimumScaleFactor(0.4).frame(width: l.x(186), height: l.y(98))
                    .position(x: l.x(99), y: l.y(76))
                Text(clock.minutes).font(style.timeFont(104 * l.s)).foregroundStyle(style.accent)
                    .lineLimit(1).minimumScaleFactor(0.4).frame(width: l.x(186), height: l.y(98))
                    .position(x: l.x(99), y: l.y(168))
                if design.showSeconds && !style.dimmed {
                    Capsule().fill(style.tertiary).frame(width: l.x(150), height: 3 * l.s)
                        .overlay(alignment: .leading) {
                            Capsule().fill(style.accent).frame(width: l.x(150) * CGFloat(clock.second / 60), height: 3 * l.s)
                        }
                        .position(x: l.x(99), y: l.y(214))
                }
                SlotView(kind: .inline, complication: design.complication("bottom"), data: data, date: date, style: style, scale: l.s,
                         calendar: calendar)
                    .frame(width: l.x(176)).position(x: l.x(99), y: l.y(229))
            }
        }
    }
}
