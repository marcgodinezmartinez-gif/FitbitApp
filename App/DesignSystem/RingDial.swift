import SwiftUI

/// Anillo grueso con degradado angular, extremo redondeado y brillo sutil; opcionalmente con la banda objetivo
/// superpuesta. Se llena con animación de muelle y respeta «Reducir movimiento» (doc. 11 §2).
struct RingDial<Center: View>: View {
    var progress: Double
    var color: Color
    var lineWidth: CGFloat = 14
    var target: ClosedRange<Double>? = nil
    var delay: Double = 0
    @ViewBuilder var center: () -> Center

    @State private var shown: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static func clamp(_ v: Double) -> CGFloat { CGFloat(Swift.min(1.0, Swift.max(0.0, v))) }

    private var fill: CGFloat { Swift.max(CGFloat(0.002), Self.clamp(shown)) }

    private var gradient: AngularGradient {
        let end: Double = Swift.max(1.0, 360.0 * Double(Self.clamp(shown)))
        return AngularGradient(gradient: Gradient(colors: [color.opacity(0.55), color]), center: .center,
                               startAngle: .degrees(0), endAngle: .degrees(end))
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.14), lineWidth: lineWidth)
            if let target {
                Circle()
                    .trim(from: Self.clamp(target.lowerBound), to: Self.clamp(target.upperBound))
                    .stroke(Palette.textPrimary.opacity(0.28), style: StrokeStyle(lineWidth: lineWidth + 8, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
            Circle()
                .trim(from: 0, to: fill)
                .stroke(gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.45), radius: 6)
            center()
        }
        .padding(lineWidth / 2 + 4)
        .onAppear { animate(to: progress) }
        .onChange(of: progress) { _, newValue in animate(to: newValue) }
    }

    private func animate(to value: Double) {
        if reduceMotion {
            shown = value
        } else {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.82).delay(delay)) { shown = value }
        }
    }
}
