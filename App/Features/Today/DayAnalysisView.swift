import SwiftUI
import MetricsKit
import Insights
import CoachKit

/// «Analizar mi día» (RF-ANA-01, RF-COA-18): primero la versión determinista (al instante y gratis) y, si el Coach está
/// activado, la redactada por la IA con el mismo esquema, validada; después se puede seguir preguntando en el mismo hilo.
struct DayAnalysisView: View {
    let date: LocalDate
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var analysis: DayAnalysis?
    @State private var isAI = false
    @State private var working = false
    @State private var status: String?
    @State private var note: String?
    @State private var threadID: String?
    @State private var modelName: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let analysis {
                        AnalysisContent(analysis: analysis)
                    } else {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                    }
                    if working {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text(status ?? "Analizando con la IA…").font(.footnote).foregroundStyle(Palette.textSecondary)
                        }
                    }
                    if let note {
                        Label(note, systemImage: "info.circle").font(.footnote).foregroundStyle(Palette.textSecondary)
                    }
                    if isAI {
                        Label("Respuesta generada por IA · \(modelName.map(ModelCatalog.displayName) ?? "Coach")", systemImage: "sparkles")
                            .font(.caption).foregroundStyle(Palette.textSecondary)
                    }
                    if let threadID {
                        NavigationLink {
                            CoachChatView(threadID: threadID)
                        } label: {
                            Label("Seguir preguntando", systemImage: "bubble.left.and.text.bubble.right")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassProminent)
                    }
                }
                .padding(16)
            }
            .screenBackground()
            .navigationTitle("Análisis del día")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
        .task { await run() }
    }

    private func run() async {
        guard let output = model.output, let cycle = output.cycle(on: date) else { return }
        let facts = DayAnalyzer.facts(for: cycle, output: output, profile: model.displayProfile, now: Date(),
                                      journalLabels: JournalCatalog.labels, journal: model.journal(on: date).answers)
        analysis = DayAnalyzer.analyze(facts)
        guard model.settings.coachEnabled, model.settings.coachMode == .personal, let coach = model.coach,
              let snapshot = model.coachSnapshot() else { return }
        working = true
        defer { working = false }
        do {
            let outcome = try await coach.analyzeDay(date, snapshot: snapshot) { event in
                Task { @MainActor in
                    switch event {
                    case .tool(let label): status = label + "…"
                    case .started(let m): modelName = m
                    default: break
                    }
                }
            }
            withAnimation(.snappy) {
                analysis = outcome.analysis
                isAI = outcome.isAI
                note = outcome.note
                threadID = outcome.threadID
            }
            model.refreshCoachSpend()
        } catch {
            note = error.localizedDescription
        }
    }
}

struct AnalysisContent: View {
    let analysis: DayAnalysis

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(analysis.titular).font(.title2.weight(.bold)).foregroundStyle(Palette.textPrimary)
            Text("Datos hasta las \(analysis.datosHasta)").font(.caption).foregroundStyle(Palette.textSecondary)
            Card {
                ForEach(Array(analysis.claves.enumerated()), id: \.offset) { _, key in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        ToneBadge(tone: key.tono)
                        Text(key.texto).font(.body).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if !analysis.actividades.isEmpty {
                Card {
                    SectionHeader(title: "Tus actividades")
                    ForEach(Array(analysis.actividades.enumerated()), id: \.offset) { _, a in
                        HStack {
                            Text(a.tipo).font(.subheadline.weight(.semibold))
                            Spacer()
                            if let km = a.distanciaKm { Text("\(Format.decimal(km)) km").font(.subheadline).monospacedDigit() }
                            if let pace = a.ritmoMinKm { Text("\(pace)/km").font(.subheadline).monospacedDigit() }
                            Text("carga \(Format.decimal(a.carga))").font(.subheadline).foregroundStyle(Palette.strain)
                        }
                        Text(a.fuentes.map(Self.sourceName).joined(separator: " + ")).font(.caption).foregroundStyle(Palette.textSecondary)
                    }
                }
            }
            Card {
                Label("Esta noche", systemImage: "moon.stars.fill").font(.headline).foregroundStyle(Palette.sleep)
                Text(analysis.estaNoche)
                Label("Mañana", systemImage: "sunrise.fill").font(.headline).foregroundStyle(Palette.recoveryMedium).padding(.top, 6)
                Text(analysis.manana)
            }
            DisclosureGroup("Datos usados") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(analysis.datosUsados.enumerated()), id: \.offset) { _, d in
                        Text("\(d.metrica) · \(d.fecha) · \(Self.sourceName(d.fuente))").font(.caption).foregroundStyle(Palette.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
            }
            .font(.subheadline)
            .tint(Palette.textSecondary)
        }
    }

    static func sourceName(_ id: String) -> String {
        switch id {
        case "fitbit_air": return "Fitbit Air"
        case "apple_watch": return "Apple Watch"
        case "manual": return "Manual"
        default: return id
        }
    }
}
