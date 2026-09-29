import SwiftUI
import MetricsKit
import Insights

/// Tarjeta sobre fondo sólido (legibilidad por encima de los materiales, doc. 11 §2).
struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

struct SectionHeader: View {
    var title: String
    var trailing: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.headline).foregroundStyle(Palette.textPrimary)
            Spacer()
            if let trailing { Text(trailing).font(.footnote).foregroundStyle(Palette.textSecondary) }
        }
    }
}

/// Cifra grande con su unidad y una línea de contexto.
struct BigNumber: View {
    var value: String
    var unit: String? = nil
    var caption: String? = nil
    var color: Color = Palette.textPrimary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.metric(44)).monospacedDigit().foregroundStyle(color).contentTransition(.numericText())
                if let unit { Text(unit).font(.title3.weight(.semibold)).foregroundStyle(Palette.textSecondary) }
            }
            if let caption { Text(caption).font(.subheadline).foregroundStyle(Palette.textSecondary) }
        }
    }
}

/// Valor de la noche frente a tu referencia (flecha + diferencia).
struct VitalRow: View {
    enum Better { case higher, lower, neutral }

    var name: String
    var value: Double?
    var unit: String
    var usual: Double?
    var digits: Int = 0
    var better: Better = .neutral

    var body: some View {
        HStack {
            Text(name).foregroundStyle(Palette.textSecondary)
            Spacer()
            if let value {
                Text("\(Format.decimal(value, digits: digits)) \(unit)").monospacedDigit().foregroundStyle(Palette.textPrimary)
                if let usual {
                    let delta = value - usual
                    let threshold: Double = pow(10.0, Double(-digits)) / 2.0
                    Image(systemName: abs(delta) < threshold ? "equal" : (delta > 0 ? "arrow.up" : "arrow.down"))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(color(delta: delta, threshold: threshold))
                        .accessibilityLabel(abs(delta) < threshold ? "igual que lo habitual" : (delta > 0 ? "por encima de lo habitual" : "por debajo de lo habitual"))
                }
            } else {
                Text("—").foregroundStyle(Palette.textSecondary)
            }
        }
        .font(.subheadline)
    }

    private func color(delta: Double, threshold: Double) -> Color {
        guard abs(delta) >= threshold else { return Palette.textSecondary }
        switch better {
        case .higher: return delta > 0 ? Palette.recoveryHigh : Palette.recoveryMedium
        case .lower: return delta < 0 ? Palette.recoveryHigh : Palette.recoveryMedium
        case .neutral: return Palette.textSecondary
        }
    }
}

struct InsightCard: View {
    var text: String
    var symbol = "sparkle"
    var tint: Color = Palette.textPrimary

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.title3).foregroundStyle(tint).symbolRenderingMode(.hierarchical)
            Text(text).font(.body).foregroundStyle(Palette.textPrimary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Palette.surfaceElevated, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Palette.separator, lineWidth: 1))
    }
}

struct ConfidenceBadge: View {
    var confidence: Confidence

    var body: some View {
        if confidence != .high {
            Label(confidence == .low ? "Datos parciales" : "Confianza media", systemImage: "exclamationmark.circle")
                .font(.caption.weight(.medium))
                .foregroundStyle(Palette.recoveryMedium)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Palette.recoveryMedium.opacity(0.12), in: Capsule())
        }
    }
}

struct SourceBadges: View {
    var sources: [DataSourceKind]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(sources, id: \.self) { s in
                Image(systemName: s.symbol).font(.caption2).foregroundStyle(Palette.textSecondary)
                    .accessibilityLabel(s.label)
            }
        }
    }
}

/// Barra apilada de minutos por zona de FC (Z0…Z5).
struct ZoneBar: View {
    var minutes: [Int]

    private var total: Int { Swift.max(1, minutes.reduce(0, +)) }

    private func width(_ m: Int, of full: CGFloat) -> CGFloat {
        let share: CGFloat = full * CGFloat(m) / CGFloat(total)
        return Swift.max(CGFloat(3), share - CGFloat(2))
    }

    private func color(_ i: Int) -> Color { Palette.zones[Swift.min(i, Palette.zones.count - 1)] }

    private var labelIndices: [Int] { Array(minutes.indices.dropFirst()) }

    private var accessibilityText: String {
        labelIndices.map { "zona \($0): \(minutes[$0]) minutos" }.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(minutes.indices, id: \.self) { i in
                        if minutes[i] > 0 {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(color(i))
                                .frame(width: width(minutes[i], of: geo.size.width))
                        }
                    }
                }
            }
            .frame(height: 12)
            HStack {
                ForEach(labelIndices, id: \.self) { i in
                    Text("Z\(i) \(minutes[i])′").font(.caption2).monospacedDigit().foregroundStyle(Palette.textSecondary)
                    if i < minutes.count - 1 { Spacer(minLength: 2) }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }
}

struct ToneBadge: View {
    var tone: DayAnalysis.Tone

    var body: some View {
        let (symbol, color): (String, Color) = {
            switch tone {
            case .positivo: return ("diamond.fill", Palette.recoveryHigh)
            case .aVigilar: return ("triangle.fill", Palette.recoveryMedium)
            case .neutro: return ("circle.fill", Palette.textSecondary)
            }
        }()
        Image(systemName: symbol).font(.caption).foregroundStyle(color)
            .accessibilityLabel(tone == .positivo ? "positivo" : (tone == .aVigilar ? "a vigilar" : "neutro"))
    }
}

/// Estado especial (calibrando, sin datos, reconectar…, doc. 11 §7).
struct StateCard: View {
    var symbol: String
    var title: String
    var message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        Card {
            Label(title, systemImage: symbol).font(.headline).foregroundStyle(Palette.textPrimary)
            Text(message).font(.subheadline).foregroundStyle(Palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(.borderedProminent).padding(.top, 4)
            }
        }
    }
}

extension View {
    /// Fondo base de las pantallas.
    func screenBackground() -> some View {
        background(Palette.bg.ignoresSafeArea())
    }
}

/// Markdown en línea (negritas, listas simples) de las respuestas del Coach.
func markdown(_ text: String) -> AttributedString {
    (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
}
