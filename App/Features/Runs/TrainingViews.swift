import SwiftUI
import UniformTypeIdentifiers
import WorkoutKit
import MetricsKit
import Insights
import RunKit

// MARK: - Formatos

extension RunFormat {
    static func goal(_ g: StepGoal) -> String {
        switch g {
        case .distance(let m): return distance(m)
        case .time(let s): return s >= 60 && s.truncatingRemainder(dividingBy: 60) == 0 ? "\(Int(s / 60)) min" : time(s)
        case .open: return "Libre"
        }
    }

    static func target(_ t: WorkoutTarget) -> String? {
        if let f = t.paceFast, let s = t.paceSlow { return "\(pace(f))–\(pace(s)) /km" }
        if let z = t.heartRateZone { return "Zona \(z) de FC" }
        return nil
    }

    static func weekday(_ d: LocalDate) -> String { Format.weekdayName(d).capitalized }

    /// «1:45:00», «45:30» o «45» (minutos) → segundos.
    static func parseTime(_ text: String) -> Double? {
        let parts = text.split(separator: ":").map { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }) else { return nil }
        let v = parts.compactMap { $0 }
        switch v.count {
        case 1: return v[0] * 60
        case 2: return v[0] * 60 + v[1]
        case 3: return v[0] * 3600 + v[1] * 60 + v[2]
        default: return nil
        }
    }
}

extension SessionKind {
    var symbol: String {
        switch self {
        case .easy, .recovery: return "figure.walk.motion"
        case .long: return "road.lanes"
        case .strides: return "hare"
        case .hills: return "mountain.2"
        case .race: return "flag.checkered"
        default: return "bolt.heart"
        }
    }

    var color: Color {
        switch self {
        case .easy, .recovery, .strides: return Palette.recoveryHigh
        case .long: return Palette.sleep
        case .race: return Palette.recoveryLow
        default: return Palette.strain
        }
    }
}

// MARK: - Carrera objetivo

struct GoalRaceCard: View {
    @Environment(AppModel.self) private var model
    let runs: RunsModel
    @State private var editing = false

    var body: some View {
        Card {
            if let goal = runs.goal {
                let days = LocalDate(goal.date, utcOffsetSeconds: runs.offset).days(since: runs.today)
                HStack(alignment: .firstTextBaseline) {
                    Text(goal.name.isEmpty ? "Carrera objetivo" : goal.name).font(.headline).lineLimit(1)
                    Spacer()
                    Button("Editar") { editing = true }.font(.subheadline)
                }
                Text(Self.when(goal, days: days)).font(.caption).foregroundStyle(Palette.textSecondary)
                if let p = runs.goalPrediction {
                    BigNumber(value: RunFormat.time(p.totalSeconds),
                              caption: "predicción · \(RunFormat.pace(p.totalSeconds / goal.distanceM * 1000)) /km")
                    RunRow(name: "En llano y con fresco", value: RunFormat.time(p.flatSeconds))
                    if p.hillSeconds >= 1 {
                        RunRow(name: "Desnivel (+\(Int(goal.elevationGainM)) / −\(Int(goal.elevationLossM)) m)", value: "+" + RunFormat.time(p.hillSeconds))
                    }
                    if p.heatSeconds >= 1 {
                        RunRow(name: "Calor (\(Format.decimal(p.heatSlowdownPct)) %)", value: "+" + RunFormat.time(p.heatSeconds))
                    }
                    if let target = goal.targetSeconds {
                        let gap = target - p.totalSeconds
                        Text(gap >= 0 ? "Tu objetivo (\(RunFormat.time(target))) está a tu alcance: \(RunFormat.time(gap)) de margen."
                                      : "Tu objetivo (\(RunFormat.time(target))) pide \(RunFormat.time(-gap)) más de lo que marca tu forma de hoy.")
                            .font(.subheadline).foregroundStyle(gap >= 0 ? Palette.recoveryHigh : Palette.recoveryMedium)
                    }
                    if let text = Self.conditions(goal, p) {
                        Text(text).font(.caption).foregroundStyle(Palette.textSecondary)
                    }
                    if p.tooHot {
                        Text("Demasiado calor para ir a tope: sal más despacio y bebe.").font(.caption.weight(.semibold)).foregroundStyle(Palette.recoveryLow)
                    }
                    if !p.splits.isEmpty {
                        NavigationLink {
                            RaceSplitsView(goal: goal, prediction: p)
                        } label: {
                            Label("Ritmo por km a esfuerzo constante", systemImage: "chart.bar.xaxis").font(.subheadline.weight(.semibold))
                        }
                    }
                } else {
                    Text("Con alguna carrera más con FC o una marca de 3 km o más calcularemos tu predicción.")
                        .font(.subheadline).foregroundStyle(Palette.textSecondary)
                }
            } else {
                SectionHeader(title: "Carrera objetivo")
                Text("Añade tu próxima carrera: verás tu predicción ajustada al desnivel del recorrido y al tiempo que haga, y un plan para llegar en forma.")
                    .font(.subheadline).foregroundStyle(Palette.textSecondary)
                Button {
                    editing = true
                } label: {
                    Label("Añadir carrera", systemImage: "flag.checkered").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .sheet(isPresented: $editing) { GoalRaceEditor(goal: runs.goal) }
    }

    static func when(_ goal: GoalRace, days: Int) -> String {
        var text = goal.date.formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute())
        text += " · " + RunFormat.distance(goal.distanceM)
        if days > 0 { text += " · faltan " + RunFormat.count(days, "día", "días") }
        return text
    }

    static func conditions(_ goal: GoalRace, _ p: RacePrediction) -> String? {
        guard let t = goal.temperatureC else { return nil }
        var text = "Con \(Int(t.rounded())) °C"
        if let h = goal.humidityPct { text += " y \(Int(h.rounded())) % de humedad" }
        if let dew = p.dewPointC { text += " (rocío \(Int(dew.rounded())) °C)" }
        if let source = goal.weatherSource { text += " · " + source }
        return text + "."
    }
}

struct RaceSplitsView: View {
    let goal: GoalRace
    let prediction: RacePrediction

    var body: some View {
        List {
            Section {
                ForEach(prediction.splits) { s in
                    HStack {
                        Text("\(s.km)").font(.caption.weight(.bold)).frame(width: 26, alignment: .leading)
                        Text("\(RunFormat.pace(s.paceSeconds)) /km").monospacedDigit().fontWeight(.semibold)
                        Spacer()
                        Text(Format.signed(s.gradePct, digits: 1) + " %").monospacedDigit().foregroundStyle(Palette.textSecondary)
                        Text(RunFormat.time(s.cumulativeSeconds)).monospacedDigit().frame(width: 70, alignment: .trailing)
                    }
                    .font(.subheadline)
                }
            } footer: {
                Text("A esfuerzo constante: más despacio en las subidas y algo más rápido en las bajadas, para llegar en \(RunFormat.time(prediction.totalSeconds)) sin cebarte.")
            }
        }
        .navigationTitle("Ritmo por km")
    }
}

/// Alta y edición de la carrera objetivo: distancia, fecha, recorrido (desnivel o GPX) y tiempo el día de la carrera.
struct GoalRaceEditor: View {
    let goal: GoalRace?
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    enum Preset: String, CaseIterable, Identifiable {
        case k5, k10, half, marathon, other
        var id: String { rawValue }
        var label: String {
            switch self {
            case .k5: return "5 km"
            case .k10: return "10 km"
            case .half: return "Media"
            case .marathon: return "Maratón"
            case .other: return "Otra"
            }
        }
        var meters: Double? {
            switch self {
            case .k5: return 5000
            case .k10: return 10_000
            case .half: return 21_097.5
            case .marathon: return 42_195
            case .other: return nil
            }
        }
    }

    @State private var name = ""
    @State private var date = Calendar.current.date(byAdding: .day, value: 56, to: Date()) ?? Date()
    @State private var preset: Preset = .k10
    @State private var customKm = ""
    @State private var gain = 0.0
    @State private var loss = 0.0
    @State private var profile: [CoursePoint]?
    @State private var courseInfo: String?
    @State private var temperature = 15.0
    @State private var humidity = 60.0
    @State private var hasWeather = false
    @State private var weatherSource: String?
    @State private var location: RaceLocation?
    @State private var query = ""
    @State private var places: [RaceLocation] = []
    @State private var target = ""
    @State private var importing = false
    @State private var working = false
    @State private var message: String?
    @State private var confirmDelete = false

    private var distanceM: Double? {
        preset.meters ?? Double(customKm.replacingOccurrences(of: ",", with: ".")).map { $0 * 1000 }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Carrera") {
                    TextField("Nombre (p. ej. 10K de Valencia)", text: $name)
                    DatePicker("Salida", selection: $date, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    Picker("Distancia", selection: $preset) {
                        ForEach(Preset.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if preset == .other {
                        TextField("Km", text: $customKm).keyboardType(.decimalPad)
                    }
                }
                Section {
                    Stepper("Subida: \(Int(gain)) m", value: $gain, in: 0...5000, step: 10)
                    Stepper("Bajada: \(Int(loss)) m", value: $loss, in: 0...5000, step: 10)
                    Button {
                        importing = true
                    } label: {
                        Label(profile == nil ? "Importar el recorrido (GPX)" : "Cambiar el recorrido (GPX)", systemImage: "map")
                    }
                    if let courseInfo { Text(courseInfo).font(.caption).foregroundStyle(Palette.textSecondary) }
                } header: {
                    Text("Recorrido")
                } footer: {
                    Text("Con el GPX de la web de la carrera, la predicción usa cada subida y bajada y te da el ritmo de cada km.")
                }
                Section {
                    Toggle("Tener en cuenta el tiempo", isOn: $hasWeather)
                    if hasWeather {
                        Stepper("Temperatura: \(Int(temperature)) °C", value: $temperature, in: -10...45)
                        Stepper("Humedad: \(Int(humidity)) %", value: $humidity, in: 5...100, step: 5)
                        HStack {
                            TextField("Ciudad de la carrera", text: $query).submitLabel(.search).onSubmit { Task { await search() } }
                            Button("Buscar") { Task { await search() } }.disabled(query.trimmingCharacters(in: .whitespaces).count < 2)
                        }
                        ForEach(places) { p in
                            Button {
                                location = p
                                places = []
                                query = p.name
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(p.name)
                                    if let d = p.detail { Text(d).font(.caption).foregroundStyle(Palette.textSecondary) }
                                }
                            }
                        }
                        if let location {
                            Button(working ? "Buscando…" : "Usar el tiempo previsto en \(location.name)") { Task { await fetchWeather(location) } }
                                .disabled(working)
                        }
                        if let weatherSource { Text("Ahora: \(weatherSource).").font(.caption).foregroundStyle(Palette.textSecondary) }
                    }
                } header: {
                    Text("Tiempo el día de la carrera")
                } footer: {
                    Text("Si faltan 16 días o menos, la previsión; si no, el tiempo que hizo ese día a esa hora en los últimos tres años. Datos de Open-Meteo.com: solo se envía la ciudad de la carrera.")
                }
                Section {
                    TextField("h:mm:ss (opcional)", text: $target).keyboardType(.numbersAndPunctuation)
                } header: {
                    Text("Tu objetivo")
                }
                if let message {
                    Section { Text(message).font(.footnote) }
                }
                if goal != nil {
                    Section {
                        Button("Quitar la carrera objetivo", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(goal == nil ? "Carrera objetivo" : "Editar carrera")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Guardar") { save() }.disabled(distanceM == nil) }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [UTType(filenameExtension: "gpx") ?? .xml, .xml]) { result in
                if case .success(let url) = result { importGPX(url) }
            }
            .confirmationDialog("¿Quitar la carrera objetivo?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Quitar", role: .destructive) {
                    model.runs.saveGoal(nil, model: model)
                    dismiss()
                }
            } message: {
                Text("También se borra el plan de entrenamiento.")
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard let g = goal else { return }
        name = g.name
        date = g.date
        preset = Preset.allCases.first { $0.meters.map { abs($0 - g.distanceM) < 1 } ?? false } ?? .other
        if preset == .other { customKm = Format.decimal(g.distanceM / 1000, digits: 2) }
        gain = g.elevationGainM
        loss = g.elevationLossM
        profile = g.profile
        if g.profile != nil { courseInfo = "Recorrido importado." }
        if let t = g.temperatureC {
            hasWeather = true
            temperature = t
            humidity = g.humidityPct ?? humidity
        }
        weatherSource = g.weatherSource
        location = g.location
        query = g.location?.name ?? ""
        target = g.targetSeconds.map { RunFormat.time($0) } ?? ""
    }

    private func save() {
        guard let meters = distanceM, meters >= 1000 else {
            message = "Pon una distancia de al menos 1 km."
            return
        }
        let race = GoalRace(name: name.trimmingCharacters(in: .whitespaces), date: date, distanceM: meters, elevationGainM: gain,
                            elevationLossM: loss, profile: profile, temperatureC: hasWeather ? temperature : nil,
                            humidityPct: hasWeather ? humidity : nil, weatherSource: hasWeather ? (weatherSource ?? "lo pones tú") : nil,
                            location: location, targetSeconds: RunFormat.parseTime(target))
        model.runs.saveGoal(race, model: model)
        Haptics.success()
        dismiss()
    }

    private func importGPX(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), let course = GPXReader.course(from: data, name: name.isEmpty ? "Salida" : name) else {
            message = "No se ha podido leer el recorrido del GPX."
            return
        }
        profile = course.profile.isEmpty ? nil : course.profile
        gain = (course.gainM / 5).rounded() * 5
        loss = (course.lossM / 5).rounded() * 5
        if preset == .other || distanceM == nil { customKm = Format.decimal(course.distanceM / 1000, digits: 2) }
        courseInfo = "GPX: \(RunFormat.distance(course.distanceM)), +\(Int(course.gainM)) / −\(Int(course.lossM)) m\(course.profile.isEmpty ? " (sin altitud)" : "")."
        message = nil
    }

    private func search() async {
        guard let url = OpenMeteo.searchURL(query) else { return }
        working = true
        defer { working = false }
        guard let response = try? await URLSession.shared.data(from: url) else {
            message = "No se ha podido buscar la ciudad (¿sin conexión?)."
            return
        }
        places = OpenMeteo.places(from: response.0)
        if places.isEmpty { message = "No encuentro esa ciudad." }
    }

    private func fetchWeather(_ loc: RaceLocation) async {
        working = true
        defer { working = false }
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        let day = LocalDate(date, utcOffsetSeconds: TimeZone.current.secondsFromGMT(for: date))
        let daysAway = day.days(since: LocalDate(Date(), utcOffsetSeconds: TimeZone.current.secondsFromGMT()))
        var list: [RaceConditions] = []
        if daysAway <= OpenMeteo.forecastDays, let url = OpenMeteo.forecastURL(loc, day: day),
           let response = try? await URLSession.shared.data(from: url), let c = OpenMeteo.conditions(from: response.0, hour: hour) {
            list = [c]
            weatherSource = "previsión para \(loc.name)"
        } else {
            for back in 1...3 {
                let past = LocalDate(year: day.year - back, month: day.month, day: min(day.day, 28))
                guard let url = OpenMeteo.archiveURL(loc, day: past), let response = try? await URLSession.shared.data(from: url),
                      let c = OpenMeteo.conditions(from: response.0, hour: hour) else { continue }
                list.append(c)
            }
            weatherSource = "lo típico en \(loc.name) ese día (últimos \(list.count) años)"
        }
        guard let avg = OpenMeteo.average(list) else {
            weatherSource = nil
            message = "No hay datos del tiempo para ese día y sitio."
            return
        }
        temperature = avg.temperatureC.rounded()
        humidity = (avg.humidityPct / 5).rounded() * 5
        message = nil
    }
}

// MARK: - Plan de entrenamiento

struct TrainingCard: View {
    @Environment(AppModel.self) private var model
    let runs: RunsModel
    @State private var settingUp = false

    var body: some View {
        Card {
            if let plan = runs.plan {
                let week = plan.week(containing: runs.today)
                SectionHeader(title: "Tu plan", trailing: week.map { "semana \($0.index) de \(plan.weeks.count) · \($0.phase.label)" })
                if let adherence = PlanBuilder.adherence(plan, runs: runs.summaries, today: runs.today) {
                    Text("Has hecho el \(Int((adherence * 100).rounded())) % de las sesiones hasta hoy.").font(.caption).foregroundStyle(Palette.textSecondary)
                }
                let upcoming = week?.sessions ?? plan.next(from: runs.today).map { [$0] } ?? []
                ForEach(upcoming) { s in
                    NavigationLink {
                        WorkoutDetailView(workout: s.workout, date: s.date)
                    } label: {
                        SessionRow(session: s, status: runs.status(of: s), today: runs.today)
                    }
                    .buttonStyle(.plain)
                }
                NavigationLink {
                    PlanView()
                } label: {
                    Label("Ver el plan completo", systemImage: "calendar").font(.subheadline.weight(.semibold))
                }
            } else {
                SectionHeader(title: "Entrenamiento")
                if runs.goal != nil {
                    Text("Crea un plan hacia tu carrera: semanas con rodajes, tirada larga y sesiones de calidad con tus ritmos, que puedes mandar al Apple Watch.")
                        .font(.subheadline).foregroundStyle(Palette.textSecondary)
                    Button {
                        settingUp = true
                    } label: {
                        Label("Crear mi plan", systemImage: "calendar.badge.plus").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(runs.context.vdot == nil)
                } else {
                    Text("Añade una carrera objetivo para tener un plan, o elige un entreno suelto con tus ritmos y mándalo al Apple Watch.")
                        .font(.subheadline).foregroundStyle(Palette.textSecondary)
                }
            }
            if runs.context.vdot != nil {
                NavigationLink {
                    WorkoutLibraryView()
                } label: {
                    Label("Entrenos sueltos para el Watch", systemImage: "applewatch").font(.subheadline.weight(.semibold))
                }
            }
        }
        .sheet(isPresented: $settingUp) { PlanSetupSheet() }
    }
}

struct SessionRow: View {
    let session: PlannedSession
    let status: SessionStatus
    let today: LocalDate

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: session.workout.kind.symbol).font(.subheadline).foregroundStyle(session.workout.kind.color)
                .frame(width: 34, height: 34).background(session.workout.kind.color.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(session.workout.title).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.textPrimary).lineLimit(2)
                Text(detail).font(.caption).foregroundStyle(Palette.textSecondary)
            }
            Spacer(minLength: 4)
            statusIcon
        }
    }

    private var detail: String {
        let day = session.date == today ? "Hoy" : RunFormat.weekday(session.date) + " \(session.date.day)"
        return day + " · " + RunFormat.distance(session.workout.estimatedMeters) + " · "
            + Format.duration(minutes: session.workout.estimatedSeconds / 60)
    }

    @ViewBuilder private var statusIcon: some View {
        switch status {
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.recoveryHigh)
        case .partial: Image(systemName: "circle.lefthalf.filled").foregroundStyle(Palette.recoveryMedium)
        case .missed: Image(systemName: "xmark.circle").foregroundStyle(Palette.textSecondary)
        case .today: Image(systemName: "star.circle.fill").foregroundStyle(Palette.strain)
        case .upcoming: Image(systemName: "circle").foregroundStyle(Palette.textSecondary)
        }
    }
}

struct PlanSetupSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var days = 4
    @State private var longDay = 7

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper("Días de carrera a la semana: \(days)", value: $days, in: 3...6)
                    Picker("Tirada larga", selection: $longDay) {
                        // 28/9/2026 fue lunes: de ahí, los siete días.
                        ForEach(1...7, id: \.self) { d in
                            Text(Format.weekdayName(LocalDate(year: 2026, month: 9, day: 28).adding(days: d - 1)).capitalized).tag(d)
                        }
                    }
                } footer: {
                    Text("El plan parte de lo que has corrido las últimas 4 semanas: sube el volumen poco a poco, con una semana de descarga cada cuatro, y la tirada larga nunca crece más de un 10 % sobre la más larga reciente. Las sesiones de calidad usan tus ritmos del VDOT.")
                }
            }
            .navigationTitle("Tu plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Crear") {
                        model.runs.createPlan(daysPerWeek: days, longRunWeekday: longDay, model: model)
                        Haptics.success()
                        dismiss()
                    }
                }
            }
            .onAppear {
                if let plan = model.runs.plan {
                    days = plan.daysPerWeek
                    longDay = plan.longRunWeekday
                }
            }
        }
        .presentationDetents([.medium])
    }
}

struct PlanView: View {
    @Environment(AppModel.self) private var model
    @State private var settingUp = false
    @State private var confirmDelete = false
    @State private var sending = false
    @State private var message: String?

    var body: some View {
        let runs = model.runs
        List {
            if let plan = runs.plan {
                Section {
                    LabeledContent("Carrera", value: plan.goal.name.isEmpty ? RunFormat.distance(plan.goal.distanceM) : plan.goal.name)
                    LabeledContent("Fecha", value: plan.goal.date.formatted(.dateTime.day().month(.wide).year()))
                    LabeledContent("Sesiones por semana", value: "\(plan.daysPerWeek)")
                    if let message { Text(message).font(.footnote) }
                }
                ForEach(plan.weeks) { week in
                    Section {
                        ForEach(week.sessions) { s in
                            NavigationLink {
                                WorkoutDetailView(workout: s.workout, date: s.date)
                            } label: {
                                SessionRow(session: s, status: runs.status(of: s), today: runs.today)
                            }
                        }
                    } header: {
                        Text("Semana \(week.index) · \(week.phase.label) · \(Int(week.targetKm.rounded())) km\(week.isCutback ? " · descarga" : "")")
                    } footer: {
                        if week.index == 1 || week.phase != plan.weeks[max(0, week.index - 2)].phase { Text(week.phase.purpose) }
                    }
                }
            } else {
                Text("No hay plan.").foregroundStyle(Palette.textSecondary)
            }
        }
        .navigationTitle("Plan de entrenamiento")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        Task { await sendUpcoming() }
                    } label: { Label("Mandar las próximas sesiones al Watch", systemImage: "applewatch") }
                        .disabled(sending || !WatchWorkouts.isSupported)
                    Button { settingUp = true } label: { Label("Rehacer el plan", systemImage: "arrow.clockwise") }
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Borrar el plan", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $settingUp) { PlanSetupSheet() }
        .confirmationDialog("¿Borrar el plan?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Borrar", role: .destructive) { model.runs.deletePlan(model: model) }
        }
    }

    private func sendUpcoming() async {
        guard let plan = model.runs.plan else { return }
        sending = true
        defer { sending = false }
        let today = model.runs.today
        let upcoming = plan.sessions.filter { $0.date >= today && $0.date <= today.adding(days: 13) }
        do {
            let n = try await WatchWorkouts.schedule(upcoming)
            message = "\(RunFormat.count(n, "sesión mandada", "sesiones mandadas")) al Watch: están en Entreno › Programados."
            Haptics.success()
        } catch {
            message = error.localizedDescription
        }
    }
}

// MARK: - Entreno estructurado

struct WorkoutDetailView: View {
    let workout: StructuredWorkout
    var date: LocalDate?
    @Environment(AppModel.self) private var model
    @State private var preview = false
    @State private var sending = false
    @State private var message: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Card {
                    HStack(spacing: 12) {
                        Image(systemName: workout.kind.symbol).font(.title3).foregroundStyle(workout.kind.color)
                            .frame(width: 44, height: 44).background(workout.kind.color.opacity(0.14), in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(workout.title).font(.headline)
                            Text(workout.kind.label + (date.map { " · \(RunFormat.weekday($0)) \($0.day)" } ?? ""))
                                .font(.caption).foregroundStyle(Palette.textSecondary)
                        }
                    }
                    Text(workout.purpose).font(.subheadline).foregroundStyle(Palette.textSecondary)
                    RunStatGrid(items: [("Distancia aprox.", RunFormat.distance(workout.estimatedMeters)),
                                        ("Duración aprox.", Format.duration(minutes: workout.estimatedSeconds / 60))])
                }
                Card {
                    SectionHeader(title: "Pasos")
                    if let w = workout.warmup { stepRow(w) }
                    ForEach(Array(workout.blocks.enumerated()), id: \.offset) { _, block in
                        VStack(alignment: .leading, spacing: 6) {
                            if block.iterations > 1 {
                                Text("Repite \(block.iterations) veces").font(.caption.weight(.semibold)).foregroundStyle(Palette.strain)
                            }
                            ForEach(Array(block.steps.enumerated()), id: \.offset) { _, s in stepRow(s) }
                        }
                        .padding(.leading, block.iterations > 1 ? 10 : 0)
                        .overlay(alignment: .leading) {
                            if block.iterations > 1 { Rectangle().fill(Palette.strain.opacity(0.5)).frame(width: 3) }
                        }
                    }
                    if let c = workout.cooldown { stepRow(c) }
                }
                VStack(spacing: 10) {
                    Button {
                        Task { await send() }
                    } label: {
                        Label(sending ? "Mandando…" : "Mandar al Apple Watch", systemImage: "applewatch").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(sending || !WatchWorkouts.isSupported)
                    Button {
                        preview = true
                    } label: {
                        Label("Vista previa", systemImage: "eye").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    if !WatchWorkouts.isSupported {
                        Text("Hace falta un Apple Watch emparejado con watchOS 10 o posterior.").font(.caption).foregroundStyle(Palette.textSecondary)
                    }
                    if let message { Text(message).font(.footnote).foregroundStyle(Palette.textSecondary).multilineTextAlignment(.center) }
                }
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle(workout.kind.label)
        .navigationBarTitleDisplayMode(.inline)
        .workoutPreview(WatchWorkouts.plan(workout), isPresented: $preview)
    }

    private func stepRow(_ s: WorkoutStepPlan) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Circle().fill(color(s.purpose)).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(s.label).font(.subheadline.weight(.semibold))
                if let t = RunFormat.target(s.target) { Text(t).font(.caption).foregroundStyle(Palette.textSecondary).monospacedDigit() }
            }
            Spacer()
            Text(RunFormat.goal(s.goal)).font(.subheadline).monospacedDigit()
        }
    }

    private func color(_ p: WorkoutStepPlan.Purpose) -> Color {
        switch p {
        case .warmup, .cooldown: return Palette.textSecondary
        case .work: return Palette.strain
        case .recovery: return Palette.recoveryHigh
        case .steady: return Palette.sleep
        }
    }

    private func send() async {
        sending = true
        defer { sending = false }
        let day = date.map { max($0, model.runs.today) } ?? model.runs.today
        do {
            try await WatchWorkouts.schedule(workout, on: day)
            message = "Listo: en el Watch, en Entreno › Programados (\(day == model.runs.today ? "hoy" : "\(RunFormat.weekday(day)) \(day.day)"))."
            Haptics.success()
        } catch {
            message = error.localizedDescription
        }
    }
}

struct WorkoutLibraryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let vdot = model.runs.context.vdot ?? 40
        List {
            Section {
                ForEach(WorkoutLibrary.templates(vdot: vdot)) { w in
                    NavigationLink {
                        WorkoutDetailView(workout: w, date: nil)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: w.kind.symbol).foregroundStyle(w.kind.color).frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(w.title).font(.subheadline.weight(.semibold))
                                Text("\(RunFormat.distance(w.estimatedMeters)) · \(Format.duration(minutes: w.estimatedSeconds / 60))")
                                    .font(.caption).foregroundStyle(Palette.textSecondary)
                            }
                        }
                    }
                }
            } footer: {
                Text("Con tus ritmos de hoy (VDOT \(Format.decimal(vdot))). Cada paso lleva su aviso de ritmo o de zona en el reloj.")
            }
        }
        .navigationTitle("Entrenos sueltos")
    }
}
