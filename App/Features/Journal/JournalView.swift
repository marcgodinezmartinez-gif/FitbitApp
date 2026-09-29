import SwiftUI
import MetricsKit
import Insights

/// Diario: preguntas rápidas sobre un día (sí/no, cantidad, 1–5) y una nota libre (doc. 11 §5).
struct JournalView: View {
    let date: LocalDate
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var answers: [String: JournalAnswer] = [:]
    @State private var note = ""
    @State private var saving = false

    var questions: [JournalQuestion] {
        JournalCatalog.questions.filter { model.settings.journalEnabled[$0.key] ?? $0.enabledByDefault }
    }

    var body: some View {
        Form {
            Section {
                Text("Responde sobre el \(Format.longDate(date).lowercased()). Tus respuestas sirven para medir qué hábitos afectan a tu recuperación.")
                    .font(.footnote).foregroundStyle(Palette.textSecondary)
            }
            let grouped = Dictionary(grouping: questions, by: \.category)
            ForEach(grouped.keys.sorted(), id: \.self) { category in
                Section(category.capitalized) {
                    ForEach(grouped[category] ?? []) { q in
                        QuestionRow(question: q, answer: binding(for: q))
                    }
                }
            }
            Section("Nota del día") {
                TextField("¿Algo que destacar?", text: $note, axis: .vertical)
                    .lineLimit(3...6)
            }
            Section {
                NavigationLink("Elegir preguntas") { JournalQuestionsSettings() }
            }
        }
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle("Diario")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Guardar") {
                    saving = true
                    Task {
                        await model.saveJournal(Array(answers.values), note: note, date: date)
                        saving = false
                        Haptics.success()
                        dismiss()
                    }
                }
                .disabled(saving || model.settings.demoMode)
            }
        }
        .task(id: date) {
            let stored = model.journal(on: date)
            answers = Dictionary(stored.answers.map { ($0.questionKey, $0) }, uniquingKeysWith: { _, b in b })
            note = stored.note
        }
    }

    private func binding(for q: JournalQuestion) -> Binding<JournalAnswer> {
        Binding(get: { answers[q.key] ?? JournalAnswer(date: date, questionKey: q.key) },
                set: { answers[q.key] = $0 })
    }
}

struct QuestionRow: View {
    let question: JournalQuestion
    @Binding var answer: JournalAnswer

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(question.text).font(.subheadline)
            switch question.answerType {
            case .yesNo:
                Picker(question.shortLabel, selection: Binding(get: { answer.yes.map { $0 ? 1 : 0 } ?? -1 },
                                                               set: { answer.yes = $0 < 0 ? nil : ($0 == 1) })) {
                    Text("Sí").tag(1)
                    Text("No").tag(0)
                    Text("—").tag(-1)
                }
                .pickerStyle(.segmented)
            case .number:
                Stepper(value: Binding(get: { answer.number ?? 0 }, set: { answer.number = $0 }), in: 0...20, step: 1) {
                    Text(answer.number.map { Format.decimal($0, digits: 0) } ?? "Sin respuesta").monospacedDigit()
                }
            case .scale:
                Picker(question.shortLabel, selection: Binding(get: { Int(answer.number ?? 0) }, set: { answer.number = $0 == 0 ? nil : Double($0) })) {
                    Text("—").tag(0)
                    ForEach(1...5, id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Qué preguntas aparecen en el diario.
struct JournalQuestionsSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List(JournalCatalog.questions) { q in
            Toggle(q.text, isOn: Binding(get: { model.settings.journalEnabled[q.key] ?? q.enabledByDefault },
                                         set: { v in model.updateSettings { $0.journalEnabled[q.key] = v } }))
                .font(.subheadline)
        }
        .navigationTitle("Preguntas del diario")
    }
}
