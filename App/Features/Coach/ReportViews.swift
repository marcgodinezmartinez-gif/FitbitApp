import SwiftUI
import MetricsKit
import Insights
import CoachKit

/// Etiqueta de los textos redactados por la IA, con el proveedor y el modelo (RNF de transparencia, doc. 06).
struct AIReportLabel: View {
    let report: AIReport

    var body: some View {
        Label(text, systemImage: "sparkles")
            .font(.caption.weight(.medium))
            .foregroundStyle(Palette.textSecondary)
    }

    private var text: String {
        if report.provider == "demo" { return "IA · ejemplo del modo demostración" }
        var t = "Redactado por IA · \(ModelCatalog.displayName(report.model))"
        if report.usedFallback == true { t += " (reserva)" }
        return t
    }
}

/// Resumen matinal redactado (RF-COA-05): sustituye a la recomendación determinista cuando existe.
struct MorningSummaryCard: View {
    @Environment(AppModel.self) private var model
    let report: AIReport
    let tint: Color
    @State private var error: String?

    var body: some View {
        if let m = report.morning {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: "sun.horizon.fill").foregroundStyle(tint).symbolRenderingMode(.hierarchical)
                    Text(m.titulo).font(.headline).foregroundStyle(Palette.textPrimary)
                    Spacer(minLength: 0)
                }
                Text(m.resumen).font(.body).foregroundStyle(Palette.textPrimary).fixedSize(horizontal: false, vertical: true)
                Label(m.cargaObjetivo, systemImage: "flame.fill").font(.subheadline).foregroundStyle(Palette.textPrimary)
                    .labelStyle(TintedIconLabel(tint: Palette.strain))
                Label(m.horaAcostarse, systemImage: "bed.double.fill").font(.subheadline).foregroundStyle(Palette.textPrimary)
                    .labelStyle(TintedIconLabel(tint: Palette.sleep))
                HStack {
                    AIReportLabel(report: report)
                    Spacer()
                    if report.provider != "demo" {
                        Button {
                            Task { error = await model.writeMorningSummary(force: true) }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .disabled(model.isWritingReport)
                        .accessibilityLabel("Volver a redactar")
                    }
                }
                if let error { Text(error).font(.caption).foregroundStyle(Palette.recoveryLow) }
            }
            .padding(16)
            .background(Palette.surfaceElevated, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Palette.separator, lineWidth: 1))
        }
    }
}

/// Icono coloreado y texto normal.
struct TintedIconLabel: LabelStyle {
    var tint: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            configuration.icon.foregroundStyle(tint).frame(width: 20)
            configuration.title.fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Informe semanal redactado por la IA (RF-COA-06), bajo el informe determinista.
struct AIWeeklyReportCard: View {
    @Environment(AppModel.self) private var model
    let weekStart: LocalDate
    @State private var error: String?

    var body: some View {
        if let report = model.weeklyAIReport, report.periodStart == weekStart.isoString, let w = report.weekly {
            Card {
                SectionHeader(title: "Tu semana, en palabras")
                Text(w.resumen).font(.body).fixedSize(horizontal: false, vertical: true)
                Text("Logros").font(.subheadline.weight(.semibold)).padding(.top, 4)
                ForEach(w.logros, id: \.self) { l in
                    Label(l, systemImage: "checkmark.seal.fill").font(.subheadline).labelStyle(TintedIconLabel(tint: Palette.recoveryHigh))
                }
                Text("Para esta semana").font(.subheadline.weight(.semibold)).padding(.top, 4)
                ForEach(w.mejoras, id: \.self) { m in
                    Label(m, systemImage: "arrow.forward.circle.fill").font(.subheadline).labelStyle(TintedIconLabel(tint: Palette.strain))
                }
                if !w.comparacion.isEmpty {
                    Text(w.comparacion).font(.footnote).foregroundStyle(Palette.textSecondary).padding(.top, 2)
                }
                AIReportLabel(report: report)
            }
        } else if model.settings.coachEnabled && model.settings.coachMode == .personal && !model.settings.demoMode {
            Card {
                SectionHeader(title: "Tu semana, en palabras")
                Text("El Coach puede redactar el resumen de la semana pasada con 3 logros y 3 cosas que mejorar.")
                    .font(.footnote).foregroundStyle(Palette.textSecondary)
                Button {
                    Task { error = await model.writeWeeklyReport(force: false) }
                } label: {
                    Label(model.isWritingReport ? "Redactando…" : "Redactar con IA", systemImage: "sparkles")
                }
                .buttonStyle(.glass)
                .disabled(model.isWritingReport)
                if let error { Text(error).font(.caption).foregroundStyle(Palette.recoveryLow) }
            }
        }
    }
}
