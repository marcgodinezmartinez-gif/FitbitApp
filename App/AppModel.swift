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
        if on {
            await loadDemo()
        } else {
            output = nil
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
