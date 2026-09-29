import SwiftUI
import Observation
import MetricsKit
import HealthAPI
import Store
import Insights
import CoachKit
import SyncKit

/// Estado global de la app. Todo vive en el iPhone: BD local, Llavero y las dos fuentes (doc. 08).
@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable {
        case loading, onboarding, ready
        case failed(String)
    }

    var phase: Phase = .loading
    var output: MetricsOutput?
    var settings = AppSettings()
    var profile = UserProfile()
    var connection = ConnectionState()
    var isSyncing = false
    var syncMessage: String?
    /// Día que se está viendo en «Hoy» (`nil` = ciclo actual).
    var selectedDate: LocalDate?
    var coachMonthSpend: Double = 0
    /// Se incrementa cada vez que cambian los datos (las vistas que leen de la BD se recargan).
    var dataVersion = 0
    /// Plan semanal (en el modo demostración, uno de ejemplo que no se guarda).
    var weeklyPlan = WeeklyPlan()
    /// Resumen matinal de hoy e informe de la semana pasada redactados por la IA.
    var morningReport: AIReport?
    var weeklyAIReport: AIReport?
    var isWritingReport = false
    /// Respiración guiada abierta desde un aviso (NOT-09) o desde «+».
    var showBreathing = false
    let liveWorkout = LiveWorkout()

    let db: AppDatabase?
    let keychain = Keychain(service: "recupera.secrets")
    let googleConfig: OAuthConfig
    let healthKit = HealthKitProvider()
    @ObservationIgnored private(set) var google: GoogleHealthClient?
    @ObservationIgnored private(set) var syncEngine: SyncEngine?
    @ObservationIgnored private(set) var coach: CoachEngine?
    @ObservationIgnored private let auth = GoogleAuthSession()
    @ObservationIgnored private var deliveryStarted = false
    @ObservationIgnored private var demoProfile = UserProfile()
    @ObservationIgnored private var demoJournal: [JournalAnswer] = []
    @ObservationIgnored private var demoStrength: [String: [StrengthSet]] = [:]
    @ObservationIgnored private var reportAttempts: [String: Date] = [:]

    init() {
        let info = Bundle.main.infoDictionary ?? [:]
        googleConfig = OAuthConfig(clientID: info["RecuperaGoogleClientID"] as? String ?? "",
                                   reversedClientID: info["RecuperaGoogleReversedClientID"] as? String ?? "")
        var openError: String?
        let database: AppDatabase?
        do {
            database = try Self.openDatabase()
        } catch {
            database = nil
            openError = error.localizedDescription
        }
        db = database
        if let database {
            if googleConfig.isConfigured {
                google = GoogleHealthClient(config: googleConfig, tokens: KeychainTokenStore(keychain: keychain))
            }
            syncEngine = SyncEngine(db: database, google: google, apple: healthKit)
            let keychain = self.keychain
            coach = CoachEngine(db: database, keys: { provider in keychain.string("ai.\(provider)") })
        }
        if let openError { phase = .failed(openError) }
    }

    // MARK: Capturas de pantalla (CI)

    /// Valor de un argumento de arranque (`-Nombre valor`).
    static func argument(_ name: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    /// Pantalla pedida por `scripts/screenshots.sh` (`-RecuperaScreenshots -RecuperaScreen hoy…`); `nil` en uso normal.
    static var screenshotScreen: String? {
        guard ProcessInfo.processInfo.arguments.contains("-RecuperaScreenshots") else { return nil }
        return argument("-RecuperaScreen") ?? "today"
    }

    static var initialTab: AppTab {
        switch screenshotScreen {
        case "trends"?, "report"?: return .trends
        case "coach"?: return .coach
        case "profile"?: return .profile
        default: return .today
        }
    }

    static func databaseDirectory() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Recupera", isDirectory: true)
    }

    /// BD con protección de datos de iOS (disponible en segundo plano tras el primer desbloqueo) y fuera de la copia de iCloud.
    static func openDatabase() throws -> AppDatabase {
        var dir = try databaseDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? dir.setResourceValues(values)
        return try AppDatabase.open(at: dir.appendingPathComponent("recupera.sqlite"))
    }

    // MARK: Arranque y sincronización

    func bootstrap() async {
        if case .failed = phase { return }
        reloadState()
        if let screen = Self.screenshotScreen, screen != "onboarding" {
            // Capturas automáticas en CI: datos de demostración, sin conexiones y sin guardar nada.
            settings.demoMode = true
            settings.onboardingCompleted = true
            if Self.argument("-RecuperaTheme") == "light" { settings.theme = .light }
            phase = .ready
            await loadDemo()
            return
        }
        phase = settings.onboardingCompleted ? .ready : .onboarding
        if settings.demoMode {
            await loadDemo()
            return
        }
        await recompute()
        startHealthKitDeliveryIfNeeded()
        if phase == .ready { await sync(.open) }
        BackgroundSync.schedule(usualWakeMinutes: profile.usualWakeMinutes)
    }

    func reloadState() {
        guard let db else { return }
        settings = (try? db.settings()) ?? AppSettings()
        profile = (try? db.profile()) ?? UserProfile()
        connection = (try? db.connection()) ?? ConnectionState()
        if !settings.demoMode { weeklyPlan = (try? db.weeklyPlan()) ?? WeeklyPlan() }
        refreshCoachSpend()
    }

    /// Sincroniza las dos fuentes a la vez (Apple Health aparece al instante; Google en cuanto llega) y recalcula.
    func sync(_ reason: SyncReason) async {
        guard let syncEngine, !settings.demoMode else { return }
        isSyncing = true
        defer { isSyncing = false }
        let report = await syncEngine.sync(reason, backfillDays: 90)
        if let out = report.output {
            output = out
            dataVersion += 1
        }
        reloadState()
        LocalNotifications.deliver(report.notifications)
        if let snapshot = report.snapshot { SharedSnapshot.write(snapshot) }
        scheduleBedtimeReminder()
        loadReports()
        // Los informes de la IA se redactan aparte para no alargar la sincronización.
        Task { await generateReportsIfNeeded() }
        var problems: [String] = []
        if let e = report.google.error { problems.append("Google Health: \(e)") }
        if let e = report.apple.error { problems.append("Apple Health: \(e)") }
        syncMessage = problems.isEmpty ? nil : problems.joined(separator: "\n")
        if reason == .pull { Haptics.soft() }
    }

    func recompute() async {
        if settings.demoMode {
            await loadDemo()
            return
        }
        guard let syncEngine else { return }
        if let out = try? await syncEngine.recompute() {
            output = out
            dataVersion += 1
            loadReports()
        }
    }

    // MARK: Conexiones

    var googleAvailable: Bool { googleConfig.isConfigured }

    func connectGoogle() async throws {
        guard googleConfig.isConfigured, let syncEngine else { throw HealthAPIError.notConfigured }
        let (code, pkce) = try await auth.authorize(config: googleConfig)
        try await syncEngine.connectGoogle(code: code, pkce: pkce)
        reloadState()
        await sync(.backfill)
    }

    func disconnectGoogle() async {
        await syncEngine?.disconnectGoogle()
        reloadState()
    }

    func connectAppleHealth() async throws {
        try await healthKit.requestAuthorization()
        updateSettings { $0.healthKitEnabled = true }
        startHealthKitDeliveryIfNeeded()
        await sync(.open)
    }

    func disconnectAppleHealth() {
        updateSettings { $0.healthKitEnabled = false }
        try? db?.recordPrivacyEvent("desactivación Apple Health")
    }

    func startHealthKitDeliveryIfNeeded() {
        guard settings.healthKitEnabled, healthKit.isAvailable, !deliveryStarted else { return }
        deliveryStarted = true
        healthKit.startBackgroundDelivery { [weak self] in
            await self?.sync(.healthKitDelivery)
        }
    }

    // MARK: Ajustes y perfil

    func updateSettings(_ change: (inout AppSettings) -> Void) {
        change(&settings)
        try? db?.saveSettings(settings)
    }

    func saveProfile(_ p: UserProfile) async {
        profile = p
        try? db?.saveProfile(p)
        BackgroundSync.schedule(usualWakeMinutes: p.usualWakeMinutes)
        await recompute()
    }

    func completeOnboarding() async {
        updateSettings {
            $0.onboardingCompleted = true
            $0.disclaimerVersionAccepted = 1
        }
        phase = .ready
        if !settings.demoMode { await sync(connection.backfillCompleted ? .open : .backfill) }
    }

    func setExcludedFromBackup(_ excluded: Bool) {
        updateSettings { $0.excludeFromICloudBackup = excluded }
        if var dir = try? Self.databaseDirectory() {
            var values = URLResourceValues()
            values.isExcludedFromBackup = excluded
            try? dir.setResourceValues(values)
        }
    }

    // MARK: Modo demostración (datos sintéticos, sin conexiones)

    func setDemoMode(_ on: Bool) async {
        updateSettings { $0.demoMode = on }
        selectedDate = nil
        morningReport = nil
        weeklyAIReport = nil
        if on {
            await loadDemo()
        } else {
            output = nil
            weeklyPlan = (try? db?.weeklyPlan()) ?? WeeklyPlan()
            await recompute()
            await sync(.open)
        }
    }

    func loadDemo() async {
        let offset = TimeZone.current.secondsFromGMT()
        let result = await Task.detached(priority: .userInitiated) { () -> (MetricsInput, MetricsOutput) in
            let input = SyntheticData.generate(days: 90, endingAt: Date(), utcOffsetSeconds: offset)
            return (input, MetricsEngine.run(input))
        }.value
        demoProfile = result.0.profile
        demoJournal = result.0.journal
        output = result.1
        weeklyPlan = WeeklyPlan(goals: WeeklyPlan.goals(for: .fitness), template: .fitness, createdAt: Date())
        loadDemoReports()
        dataVersion += 1
    }

    var displayProfile: UserProfile { settings.demoMode ? demoProfile : profile }

    // MARK: Días y referencias

    var displayedCycle: CycleMetrics? {
        guard let output else { return nil }
        if let d = selectedDate, let c = output.cycle(on: d) { return c }
        return output.current
    }

    var isShowingToday: Bool { selectedDate == nil || selectedDate == output?.current?.date }

    func shiftDay(_ delta: Int) {
        guard let output, let current = output.current else { return }
        let target = (selectedDate ?? current.date).adding(days: delta)
        guard target <= current.date, let first = output.cycles.first?.date, target >= first else { return }
        selectedDate = target == current.date ? nil : target
        Haptics.selection()
    }

    /// Mediana de las 30 noches anteriores (la «referencia» que se muestra junto a cada vital).
    func usualVital(_ key: KeyPath<NightlyVitals, Double?>, before date: LocalDate) -> Double? {
        guard let output else { return nil }
        let values = output.cycles.filter { $0.date < date }.suffix(30).compactMap { $0.vitals?[keyPath: key] }
        guard values.count >= 5 else { return nil }
        return Stats.median(values)
    }

    var tonightBedtimeMinutes: Int? {
        guard let output, let need = output.tonightNeed else { return nil }
        let goal = SleepCalculator.PlannerGoal(rawValue: settings.plannerGoal) ?? .peak
        return SleepCalculator.bedtime(wakeMinutes: displayProfile.usualWakeMinutes, needMin: need.totalMin, goal: goal,
                                       usualEfficiency: output.usualEfficiency, usualLatency: output.usualLatency, params: .default)
    }

    func scheduleBedtimeReminder() {
        guard let bed = tonightBedtimeMinutes, let need = output?.tonightNeed else { return }
        LocalNotifications.scheduleBedtime(at: bed,
                                           body: "Para dormir \(Format.duration(minutes: need.totalMin)), acuéstate a las \(Format.clock(minutes: bed)).",
                                           enabled: settings.bedtimeReminder && settings.isOn("NOT-02"))
    }

    // MARK: Diario y anotaciones

    func journal(on date: LocalDate) -> (answers: [JournalAnswer], note: String) {
        guard let db else { return ([], "") }
        return ((try? db.journalAnswers(on: date)) ?? [], (try? db.journalNote(on: date)) ?? "")
    }

    func saveJournal(_ answers: [JournalAnswer], note: String, date: LocalDate) async {
        guard let db else { return }
        for a in answers { try? db.saveJournalAnswer(a) }
        try? db.saveJournalAnswer(JournalAnswer(date: date, questionKey: "note"), note: note)
        await recompute()
    }

    // MARK: Plan semanal

    func saveWeeklyPlan(_ plan: WeeklyPlan) {
        weeklyPlan = plan
        if !settings.demoMode { try? db?.saveWeeklyPlan(plan) }
    }

    func planProgress(weekStart: LocalDate) -> WeeklyPlanProgress? {
        guard weeklyPlan.isActive, let output, let today = output.current?.date else { return nil }
        let end = min(today, weekStart.adding(days: 6))
        let journal: [JournalAnswer] = settings.demoMode
            ? demoJournal.filter { $0.date >= weekStart && $0.date <= end }
            : ((try? db?.journalAnswers(from: weekStart, to: end)) ?? [])
        return WeeklyPlanner.progress(plan: weeklyPlan, cycles: output.cycles, journal: journal, weekStart: weekStart, today: end)
    }

    /// Progreso de esta semana.
    var planProgress: WeeklyPlanProgress? {
        guard let today = output?.current?.date else { return nil }
        return planProgress(weekStart: WeeklyPlanner.weekStart(of: today))
    }

    var planAvailable: Bool { WeeklyPlanner.isAvailable(cycles: output?.cycles ?? []) }

    // MARK: Fuerza y entrenamientos creados en la app

    /// Series registradas de una actividad (en la anotación de cualquiera de sus fuentes).
    func strengthSets(for activity: FusedActivity) -> [StrengthSet] {
        if settings.demoMode { return demoStrength[activity.id] ?? Self.demoSets(for: activity) }
        for member in activity.members {
            if let sets = (try? db?.annotation(for: member.id))?.strengthSets, !sets.isEmpty { return sets }
        }
        return []
    }

    func saveStrength(_ sets: [StrengthSet], rpe: Double?, for activity: FusedActivity) async {
        if settings.demoMode {
            demoStrength[activity.id] = sets
            dataVersion += 1
            return
        }
        guard let db else { return }
        let id = activity.primary.id
        var a = (try? db.annotation(for: id)) ?? ActivityAnnotation(activityID: id)
        a.strengthSets = sets
        if let rpe { a.rpe = rpe }
        try? db.saveAnnotation(a)
        await recompute()
    }

    /// Crea una actividad en la app (fin del entrenamiento con la Live Activity o una sesión de fuerza). Devuelve su id.
    @discardableResult
    func saveManualActivity(kind: ActivityKind, start: Date, end: Date, rpe: Double?, notes: String? = nil,
                            sets: [StrengthSet]? = nil) async -> String? {
        guard !settings.demoMode, let db else { return nil }
        let session = ActivitySession(source: .manual, sourceRecordID: UUID().uuidString, kind: kind, start: start, end: end,
                                      utcOffsetSeconds: TimeZone.current.secondsFromGMT(for: start), isManual: true, rpe: rpe,
                                      notes: notes)
        try? db.saveManualActivity(session, strengthSets: sets)
        await recompute()
        return session.id
    }

    func deleteManualActivity(id: String) async {
        guard !settings.demoMode else { return }
        try? db?.deleteManualActivity(id: id)
        await recompute()
    }

    /// Mejor 1RM estimado de cada ejercicio antes de una fecha (para marcar récords).
    func previousBests(before date: Date) -> [String: Double] {
        if settings.demoMode {
            let earlier = (output?.fusedActivities ?? []).filter { $0.kind.isStrength && $0.start < date }
            return StrengthRecords.bestOneRepMax(earlier.map { demoStrength[$0.id] ?? Self.demoSets(for: $0) })
        }
        let sessions = (try? db?.strengthSessions(before: date)) ?? []
        return StrengthRecords.bestOneRepMax(sessions.map(\.sets))
    }

    /// Series de ejemplo para las sesiones de fuerza del modo demostración (con una progresión suave).
    static func demoSets(for activity: FusedActivity) -> [StrengthSet] {
        guard activity.kind.isStrength else { return [] }
        let week = Double(LocalDate(activity.start, utcOffsetSeconds: activity.primary.utcOffsetSeconds).dayNumber / 7 % 12)
        func sets(_ name: String, _ count: Int, _ reps: Int, _ kg: Double?) -> [StrengthSet] {
            (0..<count).map { i in StrengthSet(id: "\(activity.id)-\(name)-\(i)", exercise: name, reps: reps, weightKg: kg) }
        }
        return sets("Sentadilla", 4, 5, 90 + 1.25 * week) + sets("Press de banca", 4, 6, 67.5 + week)
            + sets("Remo con barra", 3, 8, 60 + week) + sets("Dominadas", 3, 8, nil)
    }

    func saveRPE(_ rpe: Double?, activity: FusedActivity) async {
        guard let db else { return }
        for member in activity.members {
            var a = (try? db.annotation(for: member.id)) ?? ActivityAnnotation(activityID: member.id)
            a.rpe = rpe
            try? db.saveAnnotation(a)
        }
        await recompute()
    }

    // MARK: Coach

    func aiKey(_ provider: String) -> String? { keychain.string("ai.\(provider)") }

    func setAIKey(_ key: String?, provider: String) { keychain.setString(key, "ai.\(provider)") }

    // MARK: Informes redactados por la IA (RF-COA-05/06)

    var lastWeekStart: LocalDate? {
        output?.current.map { WeeklyPlanner.weekStart(of: $0.date).adding(days: -7) }
    }

    func loadReports() {
        guard !settings.demoMode, let db, let today = output?.current?.date else { return }
        morningReport = db.aiReport(.morning, periodStart: today)
        weeklyAIReport = lastWeekStart.flatMap { db.aiReport(.weekly, periodStart: $0) }
    }

    /// Tras sincronizar: resumen de esta mañana (cuando ya hay sueño) e informe de la semana pasada, si están activados.
    /// Un intento fallido no se repite hasta pasadas 3 horas.
    func generateReportsIfNeeded() async {
        guard !settings.demoMode, settings.coachEnabled, settings.coachMode == .personal, let cur = output?.current else { return }
        if settings.aiMorningSummary, cur.sleep != nil, morningReport?.periodStart != cur.date.isoString,
           shouldAttempt("morning:\(cur.date.isoString)") {
            _ = await writeMorningSummary(force: false)
        }
        if settings.aiWeeklyReport, let monday = lastWeekStart, weeklyAIReport?.periodStart != monday.isoString,
           shouldAttempt("weekly:\(monday.isoString)") {
            _ = await writeWeeklyReport(force: false)
        }
    }

    private func shouldAttempt(_ key: String) -> Bool {
        if let last = reportAttempts[key], Date().timeIntervalSince(last) < 3 * 3600 { return false }
        reportAttempts[key] = Date()
        return true
    }

    /// Redacta (o rehace) el resumen de esta mañana. Devuelve el error para mostrarlo, si lo hay.
    func writeMorningSummary(force: Bool) async -> String? {
        guard let coach, let snapshot = coachSnapshot() else { return "Todavía no hay datos." }
        isWritingReport = true
        defer { isWritingReport = false }
        do {
            morningReport = try await coach.morningSummary(snapshot: snapshot, bedtimeMinutes: tonightBedtimeMinutes, force: force)
            refreshCoachSpend()
            return nil
        } catch {
            refreshCoachSpend()
            return error.localizedDescription
        }
    }

    func writeWeeklyReport(force: Bool) async -> String? {
        guard let coach, let snapshot = coachSnapshot(), let monday = lastWeekStart else { return "Todavía no hay datos." }
        isWritingReport = true
        defer { isWritingReport = false }
        do {
            weeklyAIReport = try await coach.weeklyNarrative(snapshot: snapshot, weekStart: monday, plan: planProgress(weekStart: monday),
                                                             force: force)
            refreshCoachSpend()
            return nil
        } catch {
            refreshCoachSpend()
            return error.localizedDescription
        }
    }

    /// Textos de ejemplo del modo demostración (se marcan como ejemplo; no se llama a ninguna IA).
    private func loadDemoReports() {
        guard let output, let cur = output.current else { return }
        let score = cur.recovery.score ?? 0
        let zone = cur.recovery.zone ?? .medium
        let title: String
        let activity: String
        switch zone {
        case .high:
            title = "Llegas con buena energía"
            activity = "buen día para un entrenamiento exigente"
        case .medium:
            title = "Día para mantener"
            activity = "encaja un rodaje suave o técnica"
        case .low:
            title = "Hoy toca recuperar"
            activity = "mejor algo suave: paseo, movilidad o descanso"
        }
        var summary = "Tu recuperación es del \(score) %"
        if let s = cur.sleep {
            summary += " tras dormir \(Format.duration(minutes: s.asleepMin)) de las \(Format.duration(minutes: s.need.totalMin)) que necesitabas"
        }
        summary += "."
        if let worst = cur.recovery.components.min(by: { $0.z < $1.z }), worst.z < -0.5 {
            switch worst.kind {
            case .hrv: summary += " Tu VFC está por debajo de lo habitual."
            case .restingHR: summary += " Tu FC en reposo está por encima de lo habitual."
            case .sleep: summary += " Lo que más te resta es el sueño."
            default: summary += " Algún vital nocturno está fuera de tu rango habitual."
            }
        } else {
            summary += " Tus vitales nocturnos están en tu rango habitual."
        }
        let target = cur.target.map { "Carga objetivo de \(Format.decimal($0.low)) a \(Format.decimal($0.high)): \(activity)." }
            ?? "Aún no hay carga objetivo: muévete a tu ritmo."
        let bed = tonightBedtimeMinutes.map { "Acuéstate a las \(Format.clock(minutes: $0)) para dormir lo que necesitas esta noche." }
            ?? "Intenta acostarte a tu hora de siempre."
        let morning = MorningSummary(titulo: title, resumen: summary, cargaObjetivo: target, horaAcostarse: bed)
        morningReport = AIReport(kind: .morning, periodStart: cur.date.isoString, createdAt: Date(), provider: "demo", model: "ejemplo",
                                 costUSD: 0, morning: morning)
        if let monday = lastWeekStart {
            let r = WeeklyReportBuilder.build(output: output, weekStart: monday)
            let rec = r.avgRecovery.map { "\(Int($0.rounded())) %" } ?? "—"
            var logros = Array(r.best.prefix(3))
            if logros.count < 3 { logros.append("Constancia en la hora de despertar") }
            let narrative = WeeklyNarrative(
                resumen: "Semana equilibrada: recuperación media del \(rec) y \(r.runs) carreras sin acumular fatiga.",
                logros: logros,
                mejoras: ["Acuéstate 20 min antes el domingo", "Añade 10 min de movilidad tras la fuerza", "Evita la cafeína después de las 14:00"],
                comparacion: "Recuperación y carga muy parecidas a la semana anterior.")
            weeklyAIReport = AIReport(kind: .weekly, periodStart: monday.isoString, createdAt: Date(), provider: "demo", model: "ejemplo",
                                      costUSD: 0, weekly: narrative)
        }
    }

    func refreshCoachSpend() {
        let today = LocalDate(Date(), utcOffsetSeconds: TimeZone.current.secondsFromGMT())
        let monthStart = LocalDate(year: today.year, month: today.month, day: 1)
        coachMonthSpend = (try? db?.coachSpend(fromDay: monthStart.isoString))?.costUSD ?? 0
    }

    /// Datos que el Coach puede consultar con sus herramientas (solo lectura).
    func coachSnapshot() -> CoachDataSnapshot? {
        guard let output else { return nil }
        let now = Date()
        let offset = TimeZone.current.secondsFromGMT()
        let today = LocalDate(now, utcOffsetSeconds: offset)
        let from = today.adding(days: -180)
        let journal: [JournalAnswer] = settings.demoMode ? demoJournal : ((try? db?.journalAnswers(from: from, to: today)) ?? [])
        let notes: [String: String] = settings.demoMode ? [:] : ((try? db?.journalNotes(from: from, to: today)) ?? [:])
        let memory: [CoachMemoryItem] = (try? db?.memory()) ?? []
        return CoachDataSnapshot(output: output, profile: displayProfile, params: .default, journal: journal, journalNotes: notes,
                                 memory: memory, now: now, utcOffsetSeconds: offset)
    }

    // MARK: Privacidad

    func exportArchive() throws -> URL {
        guard let db else { throw CocoaError(.fileReadUnknown) }
        try? db.recordPrivacyEvent("exportación de datos")
        return try DataExport.makeArchive(files: db.exportAll())
    }

    /// «Borrar todos los datos» (RF-PRI-02): desconecta Google, vacía la BD, el Llavero y la instantánea de los *widgets*.
    func wipeAll() async {
        await syncEngine?.disconnectGoogle()
        try? db?.wipeAll()
        keychain.removeAll()
        SharedSnapshot.clear()
        output = nil
        selectedDate = nil
        reloadState()
        phase = .onboarding
    }
}
