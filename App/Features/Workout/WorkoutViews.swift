import SwiftUI
import MetricsKit
import Insights

/// Escala de esfuerzo percibido (RPE 0–10, Borg CR-10 simplificada).
enum RPEScale {
    static func label(_ v: Double) -> String {
        switch Int(v.rounded()) {
        case 0: return "Reposo"
        case 1: return "Muy, muy suave"
        case 2: return "Suave"
        case 3: return "Moderado"
        case 4: return "Algo duro"
        case 5, 6: return "Duro"
        case 7, 8: return "Muy duro"
        case 9: return "Casi al máximo"
        default: return "Máximo"
        }
    }
}

// MARK: - Empezar un entrenamiento (con Live Activity)

struct StartWorkoutView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var kind: ActivityKind = .running

    static let kinds: [ActivityKind] = [.running, .strength, .cycling, .walking, .hiit, .swimming, .rowing, .yoga, .sports, .other]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("El cronómetro sigue en la pantalla de bloqueo y en la Dynamic Island. Al terminar valoras el esfuerzo y la carga se calcula con la FC que registren tus pulseras en ese rato.")
                        .font(.subheadline).foregroundStyle(Palette.textSecondary)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(Self.kinds, id: \.self) { k in
                            Button {
                                kind = k
                                Haptics.selection()
                            } label: {
                                kindTile(k)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if model.settings.demoMode {
                        Text("En el modo demostración el entrenamiento no se guarda al terminar.")
                            .font(.caption).foregroundStyle(Palette.textSecondary)
                    }
                }
                .padding(16)
            }
            .screenBackground()
            .navigationTitle("Empezar entrenamiento")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Button {
                    let cur = model.output?.current
                    model.liveWorkout.start(kind: kind, dayStrain: cur?.strain.strain, target: cur?.target)
                    Haptics.success()
                    dismiss()
                } label: {
                    Label("Empezar \(kind.displayName.lowercased())", systemImage: "play.fill")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .padding(16)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
            }
        }
    }

    private func kindTile(_ k: ActivityKind) -> some View {
        let selected = k == kind
        return HStack(spacing: 10) {
            Image(systemName: k.symbolName).font(.title3)
                .foregroundStyle(selected ? Palette.bg : Palette.strain)
                .frame(width: 36, height: 36)
                .background(selected ? Palette.strain : Palette.strain.opacity(0.14), in: Circle())
            Text(k.displayName).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(selected ? Palette.strain : Color.clear, lineWidth: 2))
    }
}

/// Aviso en «Hoy» mientras hay un entrenamiento en curso.
struct LiveWorkoutBanner: View {
    @Environment(AppModel.self) private var model
    let session: LiveWorkout.Session
    var onFinish: (LiveWorkout.Finished) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: session.kind.symbolName).font(.title3).foregroundStyle(Palette.strain)
                .symbolEffect(.pulse)
            VStack(alignment: .leading, spacing: 0) {
                Text(session.kind.displayName).font(.subheadline.weight(.semibold))
                Text(timerInterval: session.start...Date.distantFuture, countsDown: false)
                    .font(.metric(22)).monospacedDigit()
            }
            Spacer()
            Button {
                Task {
                    if let finished = await model.liveWorkout.finish() { onFinish(finished) }
                }
            } label: {
                Label("Terminar", systemImage: "stop.fill").font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.glassProminent)
            .tint(Palette.recoveryLow)
        }
        .padding(14)
        .background(Palette.strain.opacity(0.12), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Al terminar: esfuerzo percibido y notas; se guarda como actividad manual (RF-ENT-04).
struct FinishWorkoutView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let finished: LiveWorkout.Finished
    @State private var rpe: Double = 6
    @State private var notes = ""
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Actividad", value: finished.kind.displayName)
                    LabeledContent("Duración", value: Format.duration(minutes: finished.minutes))
                }
                Section {
                    Slider(value: $rpe, in: 0...10, step: 1).tint(Palette.strain)
                    Text("\(Int(rpe)) · \(RPEScale.label(rpe))").font(.subheadline.weight(.semibold))
                } header: {
                    Text("¿Cuánto te ha costado? (RPE 0–10)")
                } footer: {
                    Text("La carga del entrenamiento se calcula con tu FC en ese intervalo; el RPE se guarda para el sRPE.")
                }
                Section("Notas") {
                    TextField("Opcional", text: $notes, axis: .vertical)
                }
                if model.settings.demoMode {
                    Section { Text("En el modo demostración no se guarda nada.").font(.footnote) }
                }
            }
            .navigationTitle("Entrenamiento terminado")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Descartar", role: .destructive) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        saving = true
                        Task {
                            await model.saveManualActivity(kind: finished.kind, start: finished.start, end: finished.end, rpe: rpe,
                                                           notes: notes.isEmpty ? nil : notes)
                            Haptics.success()
                            dismiss()
                        }
                    }
                    .disabled(saving || finished.minutes < 1)
                }
            }
        }
    }
}

// MARK: - Registro de fuerza (RF-ENT-05)

struct StrengthLogView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    /// Actividad existente (p. ej. «Fuerza» del Apple Watch) o `nil` para una sesión nueva.
    let activity: FusedActivity?
    @State private var start: Date
    @State private var durationMin: Int
    @State private var sets: [StrengthSet] = []
    @State private var exercise = StrengthCatalog.common[0]
    @State private var reps = 8
    @State private var weightText = ""
    @State private var rpe: Double = 7
    @State private var saving = false
    @State private var loaded = false

    init(activity: FusedActivity?, start: Date? = nil, end: Date? = nil) {
        self.activity = activity
        let s = activity?.start ?? start ?? Date().addingTimeInterval(-3600)
        let e = activity?.end ?? end ?? Date()
        _start = State(initialValue: s)
        _durationMin = State(initialValue: Swift.max(10, Int((e.timeIntervalSince(s) / 60).rounded())))
    }

    var body: some View {
        NavigationStack {
            Form {
                if activity == nil {
                    Section("Sesión") {
                        DatePicker("Inicio", selection: $start)
                        Stepper("Duración: \(durationMin) min", value: $durationMin, in: 10...240, step: 5)
                    }
                }
                Section("Añadir serie") {
                    HStack {
                        TextField("Ejercicio", text: $exercise)
                        Menu {
                            ForEach(StrengthCatalog.common, id: \.self) { name in
                                Button(name) { exercise = name }
                            }
                        } label: {
                            Image(systemName: "list.bullet")
                        }
                        .accessibilityLabel("Elegir ejercicio")
                    }
                    Stepper("\(reps) repeticiones", value: $reps, in: 1...50)
                    HStack {
                        Text("Peso (kg)")
                        Spacer()
                        TextField("peso corporal", text: $weightText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 130)
                    }
                    Button {
                        addSet()
                    } label: {
                        Label("Añadir serie", systemImage: "plus.circle.fill")
                    }
                    .disabled(exercise.trimmingCharacters(in: .whitespaces).isEmpty)
                    if let last = sets.last {
                        Button {
                            sets.append(StrengthSet(exercise: last.exercise, reps: last.reps, weightKg: last.weightKg))
                            Haptics.selection()
                        } label: {
                            Label("Repetir la última (\(setText(last)))", systemImage: "arrow.counterclockwise")
                        }
                    }
                }
                if !sets.isEmpty {
                    let summary = StrengthSummary.of(sets)
                    let records = StrengthRecords.newRecords(session: sets, previousBest: model.previousBests(before: activity?.start ?? start))
                    Section {
                        ForEach(summary.exercises) { e in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(e.exercise).font(.subheadline.weight(.semibold))
                                        if records.contains(e.exercise) {
                                            Label("Récord", systemImage: "trophy.fill").font(.caption2.weight(.bold))
                                                .foregroundStyle(Palette.recoveryMedium)
                                        }
                                    }
                                    Text("\(e.sets) series · \(e.reps) rep.\(e.topWeightKg.map { " · máx. \(Format.decimal($0)) kg" } ?? "")")
                                        .font(.caption).foregroundStyle(Palette.textSecondary)
                                }
                                Spacer()
                                if let orm = e.bestOneRepMax {
                                    Text("1RM ≈ \(Format.decimal(orm, digits: 0)) kg").font(.caption).monospacedDigit()
                                        .foregroundStyle(Palette.textSecondary)
                                }
                            }
                        }
                    } header: {
                        Text("Resumen")
                    } footer: {
                        Text("\(summary.totalSets) series · \(summary.totalReps) repeticiones · volumen \(Format.decimal(summary.volumeKg, digits: 0)) kg. El 1RM es una estimación (Epley).")
                    }
                    Section("Series") {
                        ForEach(sets) { s in
                            HStack {
                                Text(s.exercise)
                                Spacer()
                                Text(setText(s)).monospacedDigit().foregroundStyle(Palette.textSecondary)
                            }
                            .font(.subheadline)
                        }
                        .onDelete { sets.remove(atOffsets: $0) }
                    }
                }
                Section {
                    Slider(value: $rpe, in: 0...10, step: 1).tint(Palette.strain)
                    Text("\(Int(rpe)) · \(RPEScale.label(rpe))").font(.subheadline.weight(.semibold))
                    if let load = StrengthSummary.muscularLoad(rpe: rpe, minutes: Double(minutes)) {
                        LabeledContent("Carga muscular (sRPE)", value: "\(Int(load.srpe)) · \(Format.decimal(load.strain)) en la escala de carga")
                            .font(.footnote)
                    }
                } header: {
                    Text("Esfuerzo de la sesión (RPE)")
                } footer: {
                    Text("sRPE = RPE × minutos. Si tu FC fue moderada, la carga del día suma la parte muscular que no refleja el pulso (ALG-CAR-05).")
                }
                if model.settings.demoMode {
                    Section { Text("En el modo demostración no se guarda nada.").font(.footnote) }
                }
            }
            .navigationTitle(activity?.name ?? "Registrar fuerza")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { save() }
                        .disabled(saving || (activity == nil && sets.isEmpty))
                }
            }
            .onAppear(perform: load)
        }
    }

    private var minutes: Int {
        if let activity { return Int(activity.durationMinutes.rounded()) }
        return durationMin
    }

    private func setText(_ s: StrengthSet) -> String {
        "\(s.reps) × \(s.weightKg.map { "\(Format.decimal($0)) kg" } ?? "peso corporal")"
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let activity {
            sets = model.strengthSets(for: activity)
            if let r = activity.rpe { rpe = r }
        }
        if let last = sets.last {
            exercise = last.exercise
            reps = last.reps
            weightText = last.weightKg.map { Format.decimal($0) } ?? ""
        }
    }

    private func addSet() {
        let name = exercise.trimmingCharacters(in: .whitespaces)
        let kg = Double(weightText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
        sets.append(StrengthSet(exercise: name, reps: reps, weightKg: (kg ?? 0) > 0 ? kg : nil))
        Haptics.selection()
    }

    private func save() {
        saving = true
        Task {
            if let activity {
                await model.saveStrength(sets, rpe: rpe, for: activity)
            } else {
                let end = start.addingTimeInterval(TimeInterval(durationMin * 60))
                await model.saveManualActivity(kind: .strength, start: start, end: end, rpe: rpe, sets: sets)
            }
            Haptics.success()
            dismiss()
        }
    }
}

/// Tarjeta del detalle de una actividad de fuerza: series registradas y carga muscular junto a la cardiovascular.
struct StrengthCard: View {
    @Environment(AppModel.self) private var model
    let metrics: ActivityMetrics
    @State private var editing = false

    var body: some View {
        let f = metrics.activity
        let sets = model.strengthSets(for: f)
        Card {
            SectionHeader(title: "Fuerza", trailing: sets.isEmpty ? nil : "\(StrengthSummary.of(sets).totalSets) series")
            if sets.isEmpty {
                Text("Registra ejercicios, series, repeticiones y peso para ver el volumen y tus récords.")
                    .font(.footnote).foregroundStyle(Palette.textSecondary)
            } else {
                let summary = StrengthSummary.of(sets)
                ForEach(summary.exercises) { e in
                    HStack {
                        Text(e.exercise).font(.subheadline)
                        Spacer()
                        Text("\(e.sets) × \(e.sets > 0 ? e.reps / e.sets : 0)\(e.topWeightKg.map { " · \(Format.decimal($0)) kg" } ?? "")")
                            .font(.subheadline).monospacedDigit().foregroundStyle(Palette.textSecondary)
                    }
                }
                LabeledContent("Volumen", value: "\(Format.decimal(summary.volumeKg, digits: 0)) kg").font(.subheadline)
            }
            HStack {
                loadColumn("Carga cardiovascular", Format.decimal(metrics.strain.strain))
                loadColumn("Carga muscular (sRPE)",
                           StrengthSummary.muscularLoad(rpe: f.rpe, minutes: f.durationMinutes).map { Format.decimal($0.strain) } ?? "—")
            }
            .padding(.top, 4)
            Button {
                editing = true
            } label: {
                Label(sets.isEmpty ? "Registrar series" : "Editar series", systemImage: "dumbbell.fill")
            }
            .buttonStyle(.glass)
        }
        .sheet(isPresented: $editing) { StrengthLogView(activity: f) }
    }

    private func loadColumn(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.metric(22, weight: .semibold)).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(Palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
