import Foundation
import HealthAPI
import Insights
import MetricsKit
import Store

public enum SyncReason: String, Sendable {
    case open, pull, background, nightly, backfill, healthKitDelivery
}

public struct SourceResult: Sendable, Hashable {
    public var ok: Bool
    public var records: Int
    public var error: String?
    public var skipped: Bool

    public static let skippedResult = SourceResult(ok: true, records: 0, error: nil, skipped: true)
}

/// Avance de la primera importación del historial (RF-SYN-01): fase, fracción y, tras cada fase, las métricas recalculadas
/// para que la app enseñe tus datos sin esperar al final.
public struct ImportProgress: Sendable {
    public var phase: String
    public var fraction: Double
    public var output: MetricsOutput?

    public init(phase: String, fraction: Double, output: MetricsOutput? = nil) {
        self.phase = phase
        self.fraction = fraction
        self.output = output
    }
}

public typealias ImportProgressHandler = @Sendable (ImportProgress) async -> Void

public struct SyncReport: Sendable {
    public var google: SourceResult
    public var apple: SourceResult
    public var output: MetricsOutput?
    public var newWatchWorkoutIDs: [String]
    public var notifications: [PlannedNotification]
    public var snapshot: WidgetSnapshot?
}

/// Motor de sincronización: las dos fuentes a la vez y recálculo (RF-SYN-09, doc. 16 §6).
public actor SyncEngine {
    public let db: AppDatabase
    let google: GoogleHealthClient?
    let apple: AppleHealthProvider?
    let now: @Sendable () -> Date
    let utcOffset: @Sendable () -> Int
    private var lastGoogleRun: Date?
    private var inFlight: Task<SyncReport, Never>?

    public init(db: AppDatabase, google: GoogleHealthClient?, apple: AppleHealthProvider?,
                now: @escaping @Sendable () -> Date = { Date() },
                utcOffset: @escaping @Sendable () -> Int = { TimeZone.current.secondsFromGMT() }) {
        self.db = db
        self.google = google
        self.apple = apple
        self.now = now
        self.utcOffset = utcOffset
    }

    /// Sincroniza las dos fuentes en paralelo, recalcula y decide los avisos. Si ya hay una en curso, espera a esa.
    /// En la primera importación (`.backfill`), `progress` recibe cada fase con las métricas ya recalculadas.
    public func sync(_ reason: SyncReason, backfillDays: Int = 90, progress: ImportProgressHandler? = nil) async -> SyncReport {
        if let inFlight { return await inFlight.value }
        let task = Task { await self.run(reason, backfillDays: backfillDays, progress: progress) }
        inFlight = task
        let r = await task.value
        inFlight = nil
        return r
    }

    private func run(_ reason: SyncReason, backfillDays: Int, progress: ImportProgressHandler?) async -> SyncReport {
        let start = now()
        let settings = (try? db.settings()) ?? AppSettings()
        // Google como mucho una vez por minuto al volver a la app (RF-SYN-03).
        let googleDue = reason == .backfill || reason == .nightly || reason == .background
            || lastGoogleRun.map { start.timeIntervalSince($0) >= 60 } ?? true
        async let appleResult = runApple(settings: settings, backfillDays: backfillDays, reason: reason)
        async let googleResult: SourceResult = googleDue ? runGoogle(reason: reason, backfillDays: backfillDays, progress: progress)
            : .skippedResult
        let (a, g) = await (appleResult, googleResult)
        if googleDue { lastGoogleRun = start }

        var output: MetricsOutput?
        var planned: [PlannedNotification] = []
        var snapshot: WidgetSnapshot?
        do {
            let out = try recompute()
            output = out
            let conn = (try? db.connection()) ?? ConnectionState()
            let sent = sentNotifications()
            let today = LocalDate(now(), utcOffsetSeconds: utcOffset())
            planned = NotificationPlanner.plan(output: out, newWatchWorkoutIDs: a.newIDs, connection: conn, settings: settings,
                                               sent: sent, now: now(), utcOffsetSeconds: utcOffset(),
                                               weeklyPlan: try? db.weeklyPlanProgress(output: out, today: today, utcOffsetSeconds: utcOffset()))
            markSent(planned)
            snapshot = makeSnapshot(out)
        } catch {
            try? db.log(SyncLogEntry(startedAt: start, finishedAt: now(), source: "engine", kind: reason.rawValue, status: "error",
                                     records: 0, error: String(describing: error)))
        }
        return SyncReport(google: g, apple: a.result, output: output, newWatchWorkoutIDs: a.newIDs, notifications: planned, snapshot: snapshot)
    }

    // MARK: Recalcular

    @discardableResult
    public func recompute() throws -> MetricsOutput {
        let n = now()
        let input = try db.metricsInput(now: n, utcOffsetSeconds: utcOffset())
        let out = MetricsEngine.run(input)
        try db.saveMetrics(out, computedAt: n)
        return out
    }

    func makeSnapshot(_ out: MetricsOutput) -> WidgetSnapshot? {
        guard let cur = out.current, let profile = try? db.profile() else { return nil }
        var bedtime: String?
        if let need = out.tonightNeed {
            bedtime = Format.clock(minutes: SleepCalculator.bedtime(wakeMinutes: profile.usualWakeMinutes, needMin: need.totalMin, goal: .peak,
                                                                    usualEfficiency: out.usualEfficiency, usualLatency: out.usualLatency,
                                                                    params: .default))
        }
        return WidgetSnapshot(date: cur.date.isoString, updatedAt: now(), sleepPerformance: cur.sleep.map { Int($0.performance.rounded()) },
                              recovery: cur.recovery.score, recoveryZone: cur.recovery.zone?.rawValue, strain: cur.strain.strain,
                              targetLow: cur.target?.low, targetHigh: cur.target?.high,
                              recommendation: TodayRecommendation.text(for: cur, output: out, profile: profile), bedtime: bedtime,
                              showValuesOnLockScreen: (try? db.settings())?.lockscreenShowsValues)
    }

    func sentNotifications() -> [String: Date] {
        let raw = (try? db.readState("notified", default: [String: Double]())) ?? [:]
        return raw.mapValues { Date(timeIntervalSince1970: $0) }
    }

    func markSent(_ list: [PlannedNotification]) {
        guard !list.isEmpty else { return }
        var raw = (try? db.readState("notified", default: [String: Double]())) ?? [:]
        let t = now().timeIntervalSince1970
        for n in list { raw[n.key] = t }
        raw = raw.filter { t - $0.value < 14 * 86_400 }
        try? db.writeState("notified", raw)
    }

    // MARK: Apple Health (Apple Watch)

    private func runApple(settings: AppSettings, backfillDays: Int, reason: SyncReason) async -> (result: SourceResult, newIDs: [String]) {
        guard let apple, apple.isAvailable, settings.healthKitEnabled else { return (.skippedResult, []) }
        let start = now()
        do {
            let imp = try await apple.importChanges(anchors: db, backfillDays: max(backfillDays, 180))
            let known = (try? db.activityIDs(source: .appleHealth)) ?? []
            try db.upsertActivities(imp.workouts)
            try db.deleteActivities(source: .appleHealth, sourceRecordIDs: imp.deletedWorkoutIDs)
            try db.upsertHRMinutes(imp.heartRateMinutes)
            for (rid, samples) in imp.workoutHeartRate { try db.upsertHRSamples(samples, activityID: "apple_health:\(rid)") }
            for (rid, points) in imp.routes { try db.saveRoute(points, activityID: "apple_health:\(rid)") }
            for (rid, ms) in imp.metricSamples { try db.saveMetricSamples(ms, activityID: "apple_health:\(rid)") }
            try db.upsertVO2(imp.vo2max)
            try db.updateConnection {
                $0.healthKitLastImportAt = self.now()
                if $0.healthKitConnectedAt == nil { $0.healthKitConnectedAt = self.now() }
                $0.healthKitEarliestAuthorized = imp.earliestAuthorized
            }
            let records = imp.workouts.count + imp.heartRateMinutes.count + imp.vo2max.count
            try? db.log(SyncLogEntry(startedAt: start, finishedAt: now(), source: "apple_health", kind: reason.rawValue, status: "ok", records: records))
            let newIDs = imp.workouts.map(\.id).filter { !known.contains($0) }
            return (SourceResult(ok: true, records: records, error: nil, skipped: false), newIDs)
        } catch {
            try? db.log(SyncLogEntry(startedAt: start, finishedAt: now(), source: "apple_health", kind: reason.rawValue, status: "error",
                                     records: 0, error: String(describing: error)))
            return (SourceResult(ok: false, records: 0, error: String(describing: error), skipped: false), [])
        }
    }

    // MARK: Google Health (Fitbit Air)

    private func runGoogle(reason: SyncReason, backfillDays: Int, progress: ImportProgressHandler?) async -> SourceResult {
        guard let google, await google.isConnected() else { return .skippedResult }
        let start = now()
        let off = utcOffset()
        let lastSynced = try? db.syncedUntil("google")
        let from: Date
        switch reason {
        case .backfill: from = start.addingTimeInterval(-Double(backfillDays) * 86_400)
        case .nightly: from = start.addingTimeInterval(-7 * 86_400)
        default:
            let recent = start.addingTimeInterval(-48 * 3600)
            from = min(recent, lastSynced.map { max($0.addingTimeInterval(-48 * 3600), start.addingTimeInterval(-Double(backfillDays) * 86_400)) } ?? start.addingTimeInterval(-Double(backfillDays) * 86_400))
        }
        do {
            let records = reason == .backfill
                ? try await backfillGoogle(google, from: from, to: start, utcOffset: off, progress: progress)
                : try await importGoogle(google, from: from, to: start, utcOffset: off)
            try db.setSynced("google", until: start)
            try db.updateConnection {
                $0.googleStatus = .active
                $0.lastSuccessSyncAt = self.now()
                $0.lastError = nil
                if reason == .backfill { $0.backfillCompleted = true }
            }
            try? db.log(SyncLogEntry(startedAt: start, finishedAt: now(), source: "google_health", kind: reason.rawValue, status: "ok", records: records))
            return SourceResult(ok: true, records: records, error: nil, skipped: false)
        } catch let e as HealthAPIError {
            try? db.updateConnection {
                if e == .reauthorizationRequired { $0.googleStatus = .needsReauth }
                $0.lastError = e.errorDescription
            }
            try? db.log(SyncLogEntry(startedAt: start, finishedAt: now(), source: "google_health", kind: reason.rawValue, status: "error",
                                     records: 0, error: e.errorDescription))
            return SourceResult(ok: false, records: 0, error: e.errorDescription, skipped: false)
        } catch {
            try? db.updateConnection { $0.lastError = String(describing: error) }
            return SourceResult(ok: false, records: 0, error: String(describing: error), skipped: false)
        }
    }

    /// Sincronización normal: todo el intervalo de una vez.
    func importGoogle(_ g: GoogleHealthClient, from: Date, to: Date, utcOffset off: Int) async throws -> Int {
        try await importGoogleMinutes(g, from: from, to: to) + importGoogleDaily(g, from: from, to: to, utcOffset: off)
    }

    /// Primera importación por fases (doc. 10 §5): 1) noches, vitales, entrenamientos y totales de todo el periodo (pocas
    /// peticiones: el sueño y la recuperación aparecen en segundos); 2) FC y pasos por minuto de los últimos 14 días (carga y
    /// estrés de hoy); 3) el resto de minutos, de lo más reciente a lo más antiguo. Tras cada fase se recalcula.
    func backfillGoogle(_ g: GoogleHealthClient, from: Date, to: Date, utcOffset off: Int,
                        progress: ImportProgressHandler?) async throws -> Int {
        let fortnight: TimeInterval = 14 * 86_400
        var records = try await importGoogleDaily(g, from: from, to: to, utcOffset: off)
        await progress?(ImportProgress(phase: "Tus noches y vitales", fraction: 0.25, output: try? recompute()))
        let recent = max(from, to.addingTimeInterval(-fortnight))
        records += try await importGoogleMinutes(g, from: recent, to: to)
        await progress?(ImportProgress(phase: "Tus últimos 14 días", fraction: 0.4, output: try? recompute()))
        let older = recent.timeIntervalSince(from)
        var end = recent
        while end > from {
            let start = max(from, end.addingTimeInterval(-fortnight))
            records += try await importGoogleMinutes(g, from: start, to: end)
            end = start
            let done = older > 0 ? recent.timeIntervalSince(end) / older : 1
            await progress?(ImportProgress(phase: "El resto de tu historial", fraction: 0.4 + 0.6 * done,
                                           output: end <= from ? try? recompute() : nil))
        }
        return records
    }

    /// FC, pasos y distancia por minuto.
    func importGoogleMinutes(_ g: GoogleHealthClient, from: Date, to: Date) async throws -> Int {
        var records = 0
        let hr = GoogleMapping.hrMinutes(try await g.rollUp(.heartRate, from: from, to: to))
        try db.upsertHRMinutes(hr)
        records += hr.count
        let steps = try await g.rollUp(.steps, from: from, to: to)
        let dist = try await g.rollUp(.distance, from: from, to: to)
        let mins = GoogleMapping.activityMinutes(steps: steps, distance: dist)
        try db.upsertActivityMinutes(mins)
        records += mins.count
        return records
    }

    /// Dispositivo, sueño, entrenamientos, vitales diarios, VO₂ máx. y totales del día.
    func importGoogleDaily(_ g: GoogleHealthClient, from: Date, to: Date, utcOffset off: Int) async throws -> Int {
        var records = 0
        if let devices = try? await g.pairedDevices() {
            let tracker = devices.first { $0.deviceType == "TRACKER" } ?? devices.first
            try db.updateConnection {
                $0.deviceLastSyncAt = GoogleTime.date(tracker?.lastSyncTime) ?? $0.deviceLastSyncAt
                $0.deviceBattery = tracker?.batteryLevel ?? $0.deviceBattery
                $0.deviceName = tracker?.deviceVersion ?? $0.deviceName
            }
        }

        let sleepFilter = HealthFilter.make(.sleep, from: from, to: to.addingTimeInterval(3600), utcOffsetSeconds: off)
        let sleepPoints: [APIDataPoint]
        do { sleepPoints = try await g.reconcile(.sleep, filter: sleepFilter) } catch { sleepPoints = try await g.list(.sleep, filter: sleepFilter) }
        let sleeps = GoogleMapping.sleepSessions(sleepPoints)
        try db.upsertSleepSessions(sleeps)
        records += sleeps.count

        let exercises = GoogleMapping.activities(try await g.list(.exercise, filter: HealthFilter.make(.exercise, from: from, to: to, utcOffsetSeconds: off)))
        try db.upsertActivities(exercises)
        records += exercises.count
        for e in exercises.suffix(8) where e.durationMinutes >= 10 {
            let pts = try? await g.list(.heartRate, filter: HealthFilter.make(.heartRate, from: e.start, to: e.end, utcOffsetSeconds: off),
                                        pageSize: 10_000, maxPages: 2)
            try db.upsertHRSamples(GoogleMapping.hrSamples(pts ?? []), activityID: e.id)
        }

        let dFrom = from.addingTimeInterval(-3 * 86_400)
        let dTo = to.addingTimeInterval(86_400)
        func daily(_ t: HealthDataType) async throws -> [APIDataPoint] {
            try await g.list(t, filter: HealthFilter.make(t, from: dFrom, to: dTo, utcOffsetSeconds: off))
        }
        let vit = GoogleMapping.vitals(hrv: try await daily(.dailyHeartRateVariability), rhr: try await daily(.dailyRestingHeartRate),
                                       spo2: try await daily(.dailyOxygenSaturation), rr: try await daily(.dailyRespiratoryRate),
                                       temp: try await daily(.dailySleepTemperatureDerivations))
        try db.mergeVitals(vit)
        records += vit.count
        try db.upsertVO2(GoogleMapping.vo2(try await daily(.dailyVo2Max)))

        let a = LocalDate(dFrom, utcOffsetSeconds: off), b = LocalDate(dTo, utcOffsetSeconds: off)
        let range = ((a.year, a.month, a.day), (b.year, b.month, b.day))
        let totals = GoogleMapping.dailyTotals(steps: try await g.dailyRollUp(.steps, from: range.0, to: range.1),
                                               distance: try await g.dailyRollUp(.distance, from: range.0, to: range.1),
                                               calories: try await g.dailyRollUp(.totalCalories, from: range.0, to: range.1))
        try db.upsertDailyTotals(totals, source: .googleHealth)
        return records
    }

    // MARK: Conexión

    public func connectGoogle(code: String, pkce: PKCE) async throws {
        guard let google else { throw HealthAPIError.notConfigured }
        let tokens = try await google.exchange(code: code, pkce: pkce)
        let identity = try? await google.identity()
        let settings = try? await google.settings()
        try db.updateConnection {
            $0.googleStatus = .active
            $0.connectedAt = self.now()
            $0.grantedScopes = tokens.grantedScopes
            $0.healthUserId = identity?.healthUserId
            $0.timeZone = settings?.timeZone
            $0.lastError = nil
        }
        try db.recordPrivacyEvent("vinculación Google Health")
    }

    public func disconnectGoogle() async {
        await google?.disconnect()
        try? db.updateConnection {
            $0.googleStatus = .disconnected
            $0.healthUserId = nil
            $0.grantedScopes = []
        }
        try? db.recordPrivacyEvent("desvinculación Google Health")
    }
}
