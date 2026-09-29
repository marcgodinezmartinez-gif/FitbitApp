import SwiftUI
import MetricsKit
import Insights

/// Barra de progreso fina con la marca de lo esperado a estas alturas de la semana.
struct PlanProgressBar: View {
    var fraction: Double
    var expected: Double? = nil
    var tint: Color = Palette.recoveryHigh

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.separator)
                Capsule().fill(tint).frame(width: fillWidth(geo.size.width))
                if let expected {
                    Rectangle().fill(Palette.textSecondary).frame(width: 2, height: geo.size.height + 6)
                        .offset(x: markOffset(geo.size.width, expected))
                }
            }
        }
        .frame(height: 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Int((fraction * 100).rounded())) por ciento")
    }

    private func fillWidth(_ full: CGFloat) -> CGFloat {
        let f = CGFloat(Swift.min(1.0, Swift.max(0.0, fraction)))
        return Swift.max(CGFloat(8), full * f)
    }

    private func markOffset(_ full: CGFloat, _ e: Double) -> CGFloat {
        let x = full * CGFloat(Swift.min(1.0, Swift.max(0.0, e)))
        return Swift.max(CGFloat(0), x - 1)
    }
}

/// Tarjeta de «Hoy» con el progreso del plan (RF-PLA-02).
struct WeeklyPlanCard: View {
    let progress: WeeklyPlanProgress

    var body: some View {
        NavigationLink(value: DetailRoute.weeklyPlan) {
            Card {
                HStack(alignment: .firstTextBaseline) {
                    SectionHeader(title: "Plan semanal")
                    Text("\(progress.percent) %").font(.metric(22, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(progress.overall >= progress.expected ? Palette.recoveryHigh : Palette.recoveryMedium)
                }
                PlanProgressBar(fraction: progress.overall, expected: progress.expected)
                if let behind = progress.mostBehind {
                    Text("Lo que más falta: \(behind.title) (\(behind.detail))")
                        .font(.footnote).foregroundStyle(Palette.textSecondary).lineLimit(2)
                } else if progress.overall >= 1 {
                    Text("¡Plan cumplido esta semana!").font(.footnote).foregroundStyle(Palette.recoveryHigh)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

/// Pantalla del plan: progreso de la semana, objetivos y edición (RF-PLA-01…03).
struct WeeklyPlanView: View {
    @Environment(AppModel.self) private var model
    @State private var editing = false
    @State private var draftTemplate: WeeklyPlan.Template?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !model.planAvailable {
                    StateCard(symbol: "hourglass", title: "Disponible tras 7 noches",
                              message: "El plan semanal se activa cuando haya al menos 7 noches con datos: así los objetivos parten de tu realidad.")
                } else if let progress = model.planProgress {
                    summary(progress)
                    Card {
                        SectionHeader(title: "Objetivos", trailing: "todos pesan igual")
                        ForEach(progress.items) { item in
                            goalRow(item, expected: progress.expected)
                            if item.id != progress.items.last?.id { Divider().overlay(Palette.separator) }
                        }
                    }
                    if let monday = model.lastWeekStart, let last = model.planProgress(weekStart: monday) {
                        Card {
                            SectionHeader(title: "Semana pasada", trailing: "\(last.percent) %")
                            PlanProgressBar(fraction: last.overall, tint: Palette.textSecondary)
                        }
                    }
                    Button { editing = true } label: {
                        Label("Editar el plan", systemImage: "slider.horizontal.3").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    Button(role: .destructive) { model.saveWeeklyPlan(WeeklyPlan()) } label: {
                        Text("Quitar el plan").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.recoveryLow)
                    .font(.subheadline)
                } else {
                    Text("Elige una plantilla para empezar; luego puedes ajustar cada objetivo.")
                        .font(.subheadline).foregroundStyle(Palette.textSecondary)
                    ForEach(WeeklyPlan.Template.allCases) { t in
                        Button { draftTemplate = t } label: { templateCard(t) }
                            .buttonStyle(.plain)
                    }
                }
                Text("El viernes te avisamos de cómo vas (si el aviso está activado) y el lunes el plan aparece en el informe semanal.")
                    .font(.caption).foregroundStyle(Palette.textSecondary)
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("Plan semanal")
        .sheet(isPresented: $editing) {
            WeeklyPlanEditor(plan: model.weeklyPlan)
        }
        .sheet(item: $draftTemplate) { t in
            WeeklyPlanEditor(plan: WeeklyPlan(goals: WeeklyPlan.goals(for: t), template: t, createdAt: Date()))
        }
    }

    private func summary(_ p: WeeklyPlanProgress) -> some View {
        HStack(spacing: 20) {
            RingDial(progress: p.overall, color: Palette.recoveryHigh, lineWidth: 14) {
                Text("\(p.percent)%").font(.metric(28)).monospacedDigit()
            }
            .frame(width: 120, height: 120)
            VStack(alignment: .leading, spacing: 6) {
                Text(model.weeklyPlan.template.title).font(.headline)
                Text("Día \(p.daysElapsed) de 7").font(.subheadline).foregroundStyle(Palette.textSecondary)
                Text(p.overall >= p.expected ? "Vas por delante de lo previsto." : "A estas alturas lo esperado sería un \(Int((p.expected * 100).rounded())) %.")
                    .font(.footnote).foregroundStyle(Palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private func goalRow(_ item: WeeklyPlanProgress.Item, expected: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : item.goal.kind.symbolName)
                    .foregroundStyle(item.isDone ? Palette.recoveryHigh : Palette.strain)
                    .frame(width: 22)
                Text(item.title).font(.subheadline.weight(.medium))
                Spacer()
                Text(item.detail).font(.caption).monospacedDigit().foregroundStyle(Palette.textSecondary)
            }
            PlanProgressBar(fraction: item.fraction, expected: expected, tint: item.isDone ? Palette.recoveryHigh : Palette.strain)
        }
        .padding(.vertical, 2)
    }

    private func templateCard(_ t: WeeklyPlan.Template) -> some View {
        Card {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(t.title).font(.headline)
                    Text(t.summary).font(.footnote).foregroundStyle(Palette.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Palette.textSecondary)
            }
        }
    }
}

/// Editor de objetivos: meta semanal, umbral diario y hábito del diario.
struct WeeklyPlanEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var plan: WeeklyPlan

    init(plan: WeeklyPlan) {
        _plan = State(initialValue: plan)
    }

    var body: some View {
        NavigationStack {
            Form {
                ForEach($plan.goals) { $goal in
                    Section(goal.kind.label) {
                        goalEditor($goal)
                        Button("Quitar este objetivo", role: .destructive) {
                            let id = goal.id
                            withAnimation { plan.goals.removeAll { $0.id == id } }
                        }
                    }
                }
                Section {
                    Menu {
                        ForEach(WeeklyPlan.Goal.Kind.allCases) { kind in
                            Button(kind.label) {
                                var g = WeeklyPlan.Goal(kind: kind)
                                if kind == .habitDays { g.habitKey = "alcohol"; g.habitDesired = false }
                                plan.goals.append(g)
                            }
                        }
                    } label: {
                        Label("Añadir objetivo", systemImage: "plus.circle.fill")
                    }
                } footer: {
                    if model.settings.demoMode {
                        Text("En el modo demostración el plan no se guarda.")
                    }
                }
            }
            .navigationTitle(plan.template.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        var p = plan
                        if p.createdAt.timeIntervalSince1970 == 0 { p.createdAt = Date() }
                        model.saveWeeklyPlan(p)
                        Haptics.success()
                        dismiss()
                    }
                    .disabled(plan.goals.isEmpty)
                }
            }
        }
    }

    @ViewBuilder
    private func goalEditor(_ goal: Binding<WeeklyPlan.Goal>) -> some View {
        let kind = goal.wrappedValue.kind
        if kind.countsDays {
            Stepper("\(Int(goal.wrappedValue.target)) \(kind == .sleepNights ? "noches" : "días") por semana",
                    value: goal.target, in: 1...7, step: 1)
        } else {
            Stepper("\(Int(goal.wrappedValue.target)) min por semana", value: goal.target, in: 10...900, step: 10)
        }
        switch kind {
        case .sleepNights:
            Stepper("Dormir \(Format.decimal(goal.wrappedValue.threshold ?? 7)) h o más",
                    value: Binding(get: { goal.wrappedValue.threshold ?? 7 }, set: { goal.wrappedValue.threshold = $0 }),
                    in: 5...10, step: 0.5)
        case .stepDays:
            Stepper("\(Format.decimal(goal.wrappedValue.threshold ?? 8000, digits: 0)) pasos o más",
                    value: Binding(get: { goal.wrappedValue.threshold ?? 8000 }, set: { goal.wrappedValue.threshold = $0 }),
                    in: 2000...25_000, step: 500)
        case .habitDays:
            Picker("Hábito", selection: Binding(get: { goal.wrappedValue.habitKey ?? "alcohol" }, set: { goal.wrappedValue.habitKey = $0 })) {
                ForEach(JournalCatalog.questions.filter { $0.answerType == .yesNo }) { q in
                    Text(q.shortLabel.capitalized).tag(q.key)
                }
            }
            Picker("Objetivo", selection: Binding(get: { goal.wrappedValue.habitDesired ?? true }, set: { goal.wrappedValue.habitDesired = $0 })) {
                Text("Hacerlo").tag(true)
                Text("Evitarlo").tag(false)
            }
            .pickerStyle(.segmented)
        default:
            EmptyView()
        }
    }
}
