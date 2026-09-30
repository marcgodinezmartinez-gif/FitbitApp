import SwiftUI
import FaceKit

// Dibujo de las esferas (doc. 19), compartido por la app del iPhone (vista previa del editor) y la del Apple Watch.
// Todas las medidas salen del ancho de la pantalla de 45 mm (198 puntos) y se escalan al tamaño real.

extension Color {
    init(_ c: FaceColor) {
        self.init(red: c.red, green: c.green, blue: c.blue)
    }
}

/// Colores y letras de una esfera ya resueltos: con el modo noche todo va en rojo, y con la pantalla atenuada
/// (siempre activa) todo baja de brillo.
struct FaceStyle {
    let accent: Color
    let primary: Color
    let secondary: Color
    let tertiary: Color
    let night: Bool
    let dimmed: Bool
    let font: FaceFont

    init(design: FaceDesign, night: Bool, dimmed: Bool) {
        self.night = night
        self.dimmed = dimmed
        font = design.font
        let k = dimmed ? 0.62 : 1.0
        if night {
            let red = Color(FaceColor.night)
            accent = red.opacity(k)
            primary = red.opacity(k)
            secondary = red.opacity(0.62 * k)
            tertiary = red.opacity(0.3 * k)
        } else {
            accent = Color(design.accent).opacity(k)
            primary = Color.white.opacity(0.96 * k)
            secondary = Color.white.opacity(0.6 * k)
            tertiary = Color.white.opacity(0.24 * k)
        }
    }

    /// El color de un dato (en rojo con el modo noche).
    func tint(_ t: FaceTint) -> Color {
        if night { return t == .primary ? primary : accent }
        let k = dimmed ? 0.62 : 1.0
        switch t {
        case .accent: return accent
        case .primary: return primary
        case .recoveryHigh: return Color(red: 0.24, green: 0.86, blue: 0.52).opacity(k)
        case .recoveryMedium: return Color(red: 1.0, green: 0.82, blue: 0.25).opacity(k)
        case .recoveryLow: return Color(red: 1.0, green: 0.36, blue: 0.36).opacity(k)
        case .strain: return Color(red: 0.30, green: 0.64, blue: 1.0).opacity(k)
        case .sleep: return Color(red: 0.70, green: 0.55, blue: 1.0).opacity(k)
        case .heart: return Color(red: 1.0, green: 0.27, blue: 0.35).opacity(k)
        case .move: return Color(red: 0.98, green: 0.07, blue: 0.31).opacity(k)
        case .exercise: return Color(red: 0.57, green: 0.91, blue: 0.16).opacity(k)
        case .stand: return Color(red: 0.12, green: 0.92, blue: 0.94).opacity(k)
        case .weather: return Color(red: 0.45, green: 0.78, blue: 1.0).opacity(k)
        }
    }

    /// Letra de la hora.
    func timeFont(_ size: CGFloat) -> Font {
        switch font {
        case .ultra: return .system(size: size, weight: .semibold).width(.expanded)
        case .rounded: return .system(size: size, weight: .bold, design: .rounded)
        case .condensed: return .system(size: size, weight: .bold).width(.compressed)
        case .mono: return .system(size: size, weight: .medium, design: .monospaced)
        case .serif: return .system(size: size, weight: .regular, design: .serif)
        case .thin: return .system(size: size, weight: .thin)
        }
    }

    /// Letra de las cifras de los datos (redondeada salvo con remates o mono, para que case con la hora).
    func valueFont(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        switch font {
        case .serif: return .system(size: size, weight: weight, design: .serif)
        case .mono: return .system(size: size, weight: weight, design: .monospaced)
        case .ultra: return .system(size: size, weight: weight).width(.expanded)
        default: return .system(size: size, weight: weight, design: .rounded)
        }
    }

    /// Rótulos pequeños en mayúsculas.
    func labelFont(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }
}

/// Fondo: negro, color liso o un halo del color; con el modo noche o atenuada, negro.
struct FaceBackgroundView: View {
    let background: FaceBackground
    let style: FaceStyle

    var body: some View {
        GeometryReader { geo in
            if style.night || style.dimmed {
                Color.black
            } else {
                switch background {
                case .black:
                    Color.black
                case .solid(let c):
                    Color(c.darkened(0.55))
                case .glow(let c):
                    ZStack {
                        Color.black
                        RadialGradient(colors: [Color(c).opacity(0.55), Color(c).opacity(0.12), .clear],
                                       center: UnitPoint(x: 0.5, y: 0.3), startRadius: 0, endRadius: geo.size.height * 0.75)
                    }
                }
            }
        }
    }
}
