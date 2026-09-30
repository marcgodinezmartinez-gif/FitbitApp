import Foundation
import GRDB
import MetricsKit

// MARK: - Estado de la app

extension AppDatabase {
    public func readState<T: Codable>(_ key: String, default value: T) throws -> T {
        try writer.read { db in
            guard let json = try String.fetchOne(db, sql: "SELECT json FROM app_state WHERE key = ?", arguments: [key]) else { return value }
            return Self.decodeMerging(json, defaults: value)
        }
    }

    public func writeState<T: Codable>(_ key: String, _ value: T) throws {
        let json = try Self.json(value)
        try writer.write { db in
            try db.execute(sql: "INSERT INTO app_state(key, json) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET json = excluded.json",
                           arguments: [key, json])
        }
    }

    public func settings() throws -> AppSettings { try readState("settings", default: AppSettings()) }
    public func saveSettings(_ s: AppSettings) throws { try writeState("settings", s) }
    public func updateSettings(_ change: (inout AppSettings) -> Void) throws {
        var s = try settings()
        change(&s)
        try saveSettings(s)
    }

    public func profile() throws -> UserProfile { try readState("profile", default: UserProfile()) }
    public func saveProfile(_ p: UserProfile) throws { try writeState("profile", p) }

    public func connection() throws -> ConnectionState { try readState("connection", default: ConnectionState()) }
    public func saveConnection(_ c: ConnectionState) throws { try writeState("connection", c) }
    public func updateConnection(_ change: (inout ConnectionState) -> Void) throws {
        var c = try connection()
        change(&c)
        try saveConnection(c)
    }

    public func engineSummary() throws -> EngineSummary? {
        try writer.read { db in
            try String.fetchOne(db, sql: "SELECT json FROM app_state WHERE key = 'engine'").flatMap { try? Self.decode(EngineSummary.self, $0) }
        }
    }

    // MARK: Sincronización

    public func syncedUntil(_ dataType: String) throws -> Date? {
        try writer.read { db in
            try Double.fetchOne(db, sql: "SELECT synced_until FROM sync_state WHERE data_type = ?", arguments: [dataType])
                .map { Date(timeIntervalSince1970: $0) }
        }
    }

    public func setSynced(_ dataType: String, until: Date, error: String? = nil) throws {
        try writer.write { db in
            try db.execute(sql: """
                INSERT INTO sync_state(data_type, synced_until, last_run_at, last_error) VALUES (?, ?, ?, ?)
                ON CONFLICT(data_type) DO UPDATE SET synced_until = excluded.synced_until, last_run_at = excluded.last_run_at,
                last_error = excluded.last_error
                """, arguments: [dataType, until.timeIntervalSince1970, Date().timeIntervalSince1970, error])
        }
    }

    public func log(_ e: SyncLogEntry) throws {
        try writer.write { db in
            try db.execute(sql: "INSERT INTO sync_log(started_at, finished_at, source, kind, status, records, error) VALUES (?,?,?,?,?,?,?)",
                           arguments: [e.startedAt.timeIntervalSince1970, e.finishedAt.timeIntervalSince1970, e.source, e.kind, e.status,
                                       e.records, e.error])
            try db.execute(sql: "DELETE FROM sync_log WHERE id NOT IN (SELECT id FROM sync_log ORDER BY id DESC LIMIT 200)")
        }
    }

    public func recentSyncLog(limit: Int = 30) throws -> [SyncLogEntry] {
        try writer.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM sync_log ORDER BY id DESC LIMIT ?", arguments: [limit]).map { r in
                SyncLogEntry(startedAt: Date(timeIntervalSince1970: r["started_at"]), finishedAt: Date(timeIntervalSince1970: r["finished_at"]),
                             source: r["source"], kind: r["kind"], status: r["status"], records: r["records"], error: r["error"])
            }
        }
    }

    public func anchor(for sampleType: String) throws -> Data? {
        try writer.read { db in try Data.fetchOne(db, sql: "SELECT anchor FROM hk_anchor WHERE sample_type = ?", arguments: [sampleType]) }
    }

    public func setAnchor(_ data: Data?, for sampleType: String) throws {
        try writer.write { db in
            try db.execute(sql: "INSERT INTO hk_anchor(sample_type, anchor, updated_at) VALUES (?,?,?) ON CONFLICT(sample_type) DO UPDATE SET anchor = excluded.anchor, updated_at = excluded.updated_at",
                           arguments: [sampleType, data, Date().timeIntervalSince1970])
        }
    }

    public func recordPrivacyEvent(_ action: String) throws {
        try writer.write { db in
            try db.execute(sql: "INSERT INTO privacy_event(at, action) VALUES (?, ?)", arguments: [Date().timeIntervalSince1970, action])
        }
    }
}

// MARK: - Datos de origen

extension AppDatabase {
    public func upsertHRMinutes(_ minutes: [HRMinute]) throws {
        guard !minutes.isEmpty else { return }
        try writer.write { db in
            let st = try db.makeStatement(sql: """
                INSERT INTO hr_minute(source, minute, bpm_avg, bpm_min, bpm_max, samples) VALUES (?,?,?,?,?,?)
                ON CONFLICT(source, minute) DO UPDATE SET bpm_avg = excluded.bpm_avg, bpm_min = excluded.bpm_min,
                bpm_max = excluded.bpm_max, samples = excluded.samples
                """)
            for m in minutes {
                try st.execute(arguments: [m.source.rawValue, m.minute, m.bpmAvg, m.bpmMin, m.bpmMax, m.samples])
            }
        }
    }

    public func upsertHRSamples(_ samples: [HRSample], activityID: String?) throws {
        guard !samples.isEmpty else { return }
        try writer.write { db in
            let st = try db.makeStatement(sql: """
                INSERT INTO hr_sample(source, ts, bpm, activity_id) VALUES (?,?,?,?)
                ON CONFLICT(source, ts) DO UPDATE SET bpm = excluded.bpm, activity_id = excluded.activity_id
                """)
            for s in samples { try st.execute(arguments: [s.source.rawValue, s.time.timeIntervalSince1970, s.bpm, activityID]) }
        }
    }

    public func upsertActivityMinutes(_ minutes: [ActivityMinute]) throws {
        guard !minutes.isEmpty else { return }
        try writer.write { db in
            let st = try db.makeStatement(sql: """
                INSERT INTO activity_minute(source, minute, steps, distance_m) VALUES (?,?,?,?)
                ON CONFLICT(source, minute) DO UPDATE SET steps = excluded.steps, distance_m = excluded.distance_m
                """)
            for m in minutes { try st.execute(arguments: [m.source.rawValue, m.minute, m.steps, m.distanceM]) }
        }
    }

    public func upsertSleepSessions(_ sessions: [SleepSession]) throws {
        try writer.write { db in
            for s in sessions {
                try db.execute(sql: """
                    INSERT INTO sleep_session(id, source, start_ts, end_ts, json) VALUES (?,?,?,?,?)
                    ON CONFLICT(id) DO UPDATE SET start_ts = excluded.start_ts, end_ts = excluded.end_ts, json = excluded.json
                    """, arguments: [s.id, s.source.rawValue, s.start.timeIntervalSince1970, s.end.timeIntervalSince1970, try Self.json(s)])
            }
        }
    }

    /// Fusiona campos parciales de los vitales del día (cada tipo diario llega por separado).
    public func mergeVitals(_ items: [NightlyVitals]) throws {
        try writer.write { db in
            for v in items {
                var merged = v
                if let json = try String.fetchOne(db, sql: "SELECT json FROM vitals WHERE date = ?", arguments: [v.date.isoString]),
                   let old = try? Self.decode(NightlyVitals.self, json) {
                    merged.restingHR = v.restingHR ?? old.restingHR
                    merged.hrvRmssdAvg = v.hrvRmssdAvg ?? old.hrvRmssdAvg
                    merged.hrvRmssdDeep = v.hrvRmssdDeep ?? old.hrvRmssdDeep
                    merged.nremHR = v.nremHR ?? old.nremHR
                    merged.respiratoryRate = v.respiratoryRate ?? old.respiratoryRate
                    merged.skinTempC = v.skinTempC ?? old.skinTempC
                    merged.spo2Avg = v.spo2Avg ?? old.spo2Avg
                }
                try db.execute(sql: "INSERT INTO vitals(date, json) VALUES (?, ?) ON CONFLICT(date) DO UPDATE SET json = excluded.json",
                               arguments: [v.date.isoString, try Self.json(merged)])
            }
        }
    }

    public func upsertDailyTotals(_ totals: [LocalDate: DailySourceTotals], source: DataSourceKind) throws {
        try writer.write { db in
            for (d, t) in totals {
                try db.execute(sql: """
                    INSERT INTO daily_source_totals(date, source, steps, distance_m, calories) VALUES (?,?,?,?,?)
                    ON CONFLICT(date, source) DO UPDATE SET steps = COALESCE(excluded.steps, steps),
                    distance_m = COALESCE(excluded.distance_m, distance_m), calories = COALESCE(excluded.calories, calories)
                    """, arguments: [d.isoString, source.rawValue, t.steps, t.distanceM, t.caloriesKcal])
            }
        }
    }

    public func upsertVO2(_ values: [VO2MaxValue]) throws {
        try writer.write { db in
            for v in values {
                try db.execute(sql: "INSERT INTO vo2max(date, source, value) VALUES (?,?,?) ON CONFLICT(date, source) DO UPDATE SET value = excluded.value",
                               arguments: [v.date.isoString, v.source.rawValue, v.value])
            }
        }
    }

    public func activityIDs(source: DataSourceKind) throws -> Set<String> {
        try writer.read { db in Set(try String.fetchAll(db, sql: "SELECT id FROM activity WHERE source = ?", arguments: [source.rawValue])) }
    }

    public func upsertActivities(_ activities: [ActivitySession]) throws {
        try writer.write { db in
            for a in activities {
                try db.execute(sql: """
                    INSERT INTO activity(id, source, source_record_id, start_ts, end_ts, kind, is_manual, json) VALUES (?,?,?,?,?,?,?,?)
                    ON CONFLICT(id) DO UPDATE SET start_ts = excluded.start_ts, end_ts = excluded.end_ts, kind = excluded.kind,
                    json = excluded.json
                    """, arguments: [a.id, a.source.rawValue, a.sourceRecordID, a.start.timeIntervalSince1970, a.end.timeIntervalSince1970,
                                     a.kind.rawValue, a.isManual, try Self.json(a)])
            }
        }
    }

    /// Borra actividades de una fuente (p. ej. un entrenamiento borrado en Salud) con sus muestras.
    public func deleteActivities(source: DataSourceKind, sourceRecordIDs: [String]) throws {
        try writer.write { db in
            for rid in sourceRecordIDs {
                let id = "\(source.rawValue):\(rid)"
                try db.execute(sql: "DELETE FROM activity WHERE id = ?", arguments: [id])
                try db.execute(sql: "DELETE FROM route_point WHERE activity_id = ?", arguments: [id])
                try db.execute(sql: "DELETE FROM activity_metric_sample WHERE activity_id = ?", arguments: [id])
                try db.execute(sql: "DELETE FROM hr_sample WHERE activity_id = ?", arguments: [id])
                try db.execute(sql: "DELETE FROM activity_detail WHERE activity_id = ?", arguments: [id])
            }
        }
    }

    public func deleteSleepSessions(ids: [String]) throws {
        try writer.write { db in for id in ids { try db.execute(sql: "DELETE FROM sleep_session WHERE id = ?", arguments: [id]) } }
    }

    public func saveRoute(_ points: [RoutePoint], activityID: String) throws {
        try writer.write { db in
            try db.execute(sql: "DELETE FROM route_point WHERE activity_id = ?", arguments: [activityID])
            let st = try db.makeStatement(sql: "INSERT OR REPLACE INTO route_point(activity_id, ts, lat, lon, alt, speed, h_acc) VALUES (?,?,?,?,?,?,?)")
            for p in points {
                try st.execute(arguments: [activityID, p.time.timeIntervalSince1970, p.latitude, p.longitude, p.altitude, p.speed, p.horizontalAccuracy])
            }
        }
    }

    public func route(activityID: String) throws -> [RoutePoint] {
        try writer.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM route_point WHERE activity_id = ? ORDER BY ts", arguments: [activityID]).map { r in
                RoutePoint(time: Date(timeIntervalSince1970: r["ts"]), latitude: r["lat"], longitude: r["lon"], altitude: r["alt"],
                           speed: r["speed"], horizontalAccuracy: r["h_acc"])
            }
        }
    }

    public func saveMetricSamples(_ samples: [MetricSample], activityID: String) throws {
        try writer.write { db in
            let st = try db.makeStatement(sql: "INSERT OR REPLACE INTO activity_metric_sample(activity_id, metric, ts, value) VALUES (?,?,?,?)")
            for s in samples { try st.execute(arguments: [activityID, s.metric, s.time.timeIntervalSince1970, s.value]) }
        }
    }

    public func metricSamples(activityID: String) throws -> [MetricSample] {
        try writer.read { db in
            try Row.fetchAll(db, sql: "SELECT metric, ts, value FROM activity_metric_sample WHERE activity_id = ? ORDER BY ts", arguments: [activityID])
                .map { MetricSample(metric: $0["metric"], time: Date(timeIntervalSince1970: $0["ts"]), value: $0["value"]) }
        }
    }

    public func annotation(for activityID: String) throws -> ActivityAnnotation? {
        try writer.read { db in
            try String.fetchOne(db, sql: "SELECT json FROM activity_annotation WHERE activity_id = ?", arguments: [activityID])
                .flatMap { try? Self.decode(ActivityAnnotation.self, $0) }
        }
    }

    public func saveAnnotation(_ a: ActivityAnnotation) throws {
        try writer.write { db in
            try db.execute(sql: "INSERT INTO activity_annotation(activity_id, json) VALUES (?, ?) ON CONFLICT(activity_id) DO UPDATE SET json = excluded.json",
                           arguments: [a.activityID, try Self.json(a)])
        }
    }

    /// Sesiones con series de fuerza registradas, de la más antigua a la más reciente (para récords y progresión).
    public func strengthSessions(before: Date? = nil) throws -> [StrengthSession] {
        try writer.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT a.activity_id AS id, a.json AS json, act.start_ts AS start_ts FROM activity_annotation a
                JOIN activity act ON act.id = a.activity_id ORDER BY act.start_ts
                """)
            return rows.compactMap { r -> StrengthSession? in
                let start = Date(timeIntervalSince1970: r["start_ts"])
                if let before, start >= before { return nil }
                guard let ann = try? Self.decode(ActivityAnnotation.self, r["json"]), let sets = ann.strengthSets, !sets.isEmpty else { return nil }
                return StrengthSession(activityID: r["id"], start: start, sets: sets)
            }
        }
    }

    /// Guarda una actividad creada en la app (entrenamiento con la Live Activity o sesión de fuerza) con sus series.
    public func saveManualActivity(_ a: ActivitySession, strengthSets: [StrengthSet]? = nil) throws {
        try upsertActivities([a])
        if let strengthSets {
            var ann = try annotation(for: a.id) ?? ActivityAnnotation(activityID: a.id)
            ann.strengthSets = strengthSets
            try saveAnnotation(ann)
        }
    }

    /// Borra una actividad creada en la app y su anotación.
    public func deleteManualActivity(id: String) throws {
        try writer.write { db in
            try db.execute(sql: "DELETE FROM activity WHERE id = ? AND is_manual = 1", arguments: [id])
            try db.execute(sql: "DELETE FROM activity_annotation WHERE activity_id = ?", arguments: [id])
        }
    }

    /// FC por minuto de las dos fuentes en un intervalo (para las curvas de FC).
    public func hrMinutes(from: Date, to: Date) throws -> [HRMinute] {
        try writer.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM hr_minute WHERE minute >= ? AND minute < ? ORDER BY minute",
                             arguments: [Int(from.timeIntervalSince1970), Int(to.timeIntervalSince1970)]).map(Self.hrMinute)
        }
    }

    static func hrMinute(_ r: Row) -> HRMinute {
        HRMinute(minute: r["minute"], bpmAvg: r["bpm_avg"], bpmMin: r["bpm_min"], bpmMax: r["bpm_max"], samples: r["samples"],
                 source: DataSourceKind(rawValue: r["source"]) ?? .googleHealth)
    }
}

// MARK: - Entrada y salida del motor de métricas

extension AppDatabase {
    /// Construye la entrada del motor con los datos desde `since` (por defecto, 200 días).
    public func metricsInput(now: Date, utcOffsetSeconds: Int, days: Int = 200, params: AlgorithmParams = .default) throws -> MetricsInput {
        try metricsInput(since: now.addingTimeInterval(-Double(days) * 86_400), until: nil, now: now,
                         utcOffsetSeconds: utcOffsetSeconds, params: params)
    }

    /// Entrada del motor para un tramo del pasado, [from, until): calcula como si «ahora» fuera `until` (historial completo).
    public func metricsInput(from: Date, until: Date, utcOffsetSeconds: Int, params: AlgorithmParams = .default) throws -> MetricsInput {
        try metricsInput(since: from, until: until, now: until, utcOffsetSeconds: utcOffsetSeconds, params: params)
    }

    /// Anotaciones del usuario (tipo, nombre, RPE y notas) aplicadas a cada actividad.
    static func annotated(_ acts: [ActivitySession], _ annotations: [String: ActivityAnnotation]) -> [ActivitySession] {
        acts.map { a in
            guard let ann = annotations[a.id] else { return a }
            var x = a
            if let r = ann.rpe { x.rpe = r }
            if let n = ann.notes { x.notes = n }
            if let k = ann.kindOverride { x.kind = k }
            if let nm = ann.nameOverride { x.name = nm }
            return x
        }
    }

    static func annotations(_ db: Database) throws -> [String: ActivityAnnotation] {
        var annotations: [String: ActivityAnnotation] = [:]
        for r in try Row.fetchAll(db, sql: "SELECT json FROM activity_annotation") {
            if let a = try? decode(ActivityAnnotation.self, r["json"]) { annotations[a.activityID] = a }
        }
        return annotations
    }

    private func metricsInput(since: Date, until: Date?, now: Date, utcOffsetSeconds: Int, params: AlgorithmParams) throws -> MetricsInput {
        let sinceTS = since.timeIntervalSince1970
        let untilTS = until?.timeIntervalSince1970 ?? .greatestFiniteMagnitude
        let sinceDate = LocalDate(since, utcOffsetSeconds: utcOffsetSeconds).isoString
        let untilDate = until.map { LocalDate($0, utcOffsetSeconds: utcOffsetSeconds).isoString } ?? "9999-12-31"
        let profile = try self.profile()
        let settings = try self.settings()
        var p = params
        p.fusion.hrWorkoutPriority = settings.hrWorkoutPriority
        return try writer.read { db in
            let sleeps = try String.fetchAll(db, sql: "SELECT json FROM sleep_session WHERE end_ts >= ? AND start_ts < ? ORDER BY end_ts",
                                             arguments: [sinceTS, untilTS])
                .compactMap { try? Self.decode(SleepSession.self, $0) }
            let vitals = try String.fetchAll(db, sql: "SELECT json FROM vitals WHERE date >= ? AND date <= ?", arguments: [sinceDate, untilDate])
                .compactMap { try? Self.decode(NightlyVitals.self, $0) }
            let minuteRange: StatementArguments = [Int(sinceTS), Int(min(untilTS, Double(Int.max / 2)))]
            let hr = try Row.fetchAll(db, sql: "SELECT * FROM hr_minute WHERE minute >= ? AND minute < ?", arguments: minuteRange).map(Self.hrMinute)
            let mins = try Row.fetchAll(db, sql: "SELECT * FROM activity_minute WHERE source = 'google_health' AND minute >= ? AND minute < ?",
                                        arguments: minuteRange).map {
                ActivityMinute(minute: $0["minute"], steps: $0["steps"], distanceM: $0["distance_m"], source: .googleHealth)
            }
            let acts = Self.annotated(try String.fetchAll(db, sql: "SELECT json FROM activity WHERE end_ts >= ? AND start_ts < ?",
                                                          arguments: [sinceTS, untilTS])
                .compactMap { try? Self.decode(ActivitySession.self, $0) }, try Self.annotations(db))
            var totals: [LocalDate: DailySourceTotals] = [:]
            for r in try Row.fetchAll(db, sql: "SELECT * FROM daily_source_totals WHERE source = 'google_health' AND date >= ? AND date <= ?",
                                      arguments: [sinceDate, untilDate]) {
                if let d = LocalDate(isoString: r["date"]) {
                    totals[d] = DailySourceTotals(steps: r["steps"], distanceM: r["distance_m"], caloriesKcal: r["calories"])
                }
            }
            let vo2 = try Row.fetchAll(db, sql: "SELECT * FROM vo2max WHERE date <= ?", arguments: [untilDate]).compactMap { r -> VO2MaxValue? in
                guard let d = LocalDate(isoString: r["date"]), let s = DataSourceKind(rawValue: r["source"]) else { return nil }
                return VO2MaxValue(date: d, value: r["value"], source: s)
            }
            let journal = try Row.fetchAll(db, sql: "SELECT * FROM journal_answer WHERE date >= ? AND date <= ?",
                                           arguments: [sinceDate, untilDate]).compactMap { r -> JournalAnswer? in
                guard let d = LocalDate(isoString: r["date"]) else { return nil }
                let yes: Int? = r["yes"]
                return JournalAnswer(date: d, questionKey: r["question_key"], yes: yes.map { $0 != 0 }, number: r["number"])
            }
            var modes: [LocalDate: StrainMode] = [:]
            for r in try Row.fetchAll(db, sql: "SELECT * FROM strain_mode") {
                if let d = LocalDate(isoString: r["date"]), let m = StrainMode(rawValue: r["mode"]) { modes[d] = m }
            }
            var samples: [String: [HRSample]] = [:]
            for r in try Row.fetchAll(db, sql: "SELECT * FROM hr_sample WHERE ts >= ? AND ts < ? AND activity_id IS NOT NULL",
                                      arguments: [now.timeIntervalSince1970 - 180 * 86_400, untilTS]) {
                let id: String = r["activity_id"]
                samples[id, default: []].append(HRSample(time: Date(timeIntervalSince1970: r["ts"]), bpm: r["bpm"],
                                                         source: DataSourceKind(rawValue: r["source"]) ?? .googleHealth))
            }
            return MetricsInput(profile: profile, params: p, now: now, utcOffsetSeconds: utcOffsetSeconds, sleepSessions: sleeps,
                                vitals: vitals, hrFitbit: hr.filter { $0.source == .googleHealth },
                                hrWatch: hr.filter { $0.source == .appleHealth }, fitbitMinutes: mins, activities: acts,
                                dailyFitbitTotals: totals, vo2max: vo2, journal: journal, strainModes: modes, workoutSamples: samples)
        }
    }

    /// Guarda el resultado del motor (ciclos, actividades fusionadas y resumen global).
    public func saveMetrics(_ output: MetricsOutput, computedAt: Date = Date()) throws {
        let summary = try Self.json(EngineSummary(output: output, computedAt: computedAt))
        let rows = try output.cycles.map { c in (c, try Self.json(c)) }
        let fused = try output.cycles.flatMap(\.activities).map { a in (a, try Self.json(a)) }
        try writer.write { db in
            let first = output.cycles.first?.cycle.start.timeIntervalSince1970 ?? 0
            try db.execute(sql: "DELETE FROM cycle_metrics WHERE start_ts >= ?", arguments: [first])
            try db.execute(sql: "DELETE FROM fused_activity WHERE start_ts >= ?", arguments: [first])
            try Self.insert(db, cycles: rows, fused: fused, algorithmVersion: output.algorithmVersion, computedAt: computedAt)
            try db.execute(sql: "INSERT INTO app_state(key, json) VALUES ('engine', ?) ON CONFLICT(key) DO UPDATE SET json = excluded.json",
                           arguments: [summary])
        }
    }

    public func recentCycles(limit: Int = 60) throws -> [CycleMetrics] {
        try writer.read { db in
            try String.fetchAll(db, sql: "SELECT json FROM cycle_metrics ORDER BY start_ts DESC LIMIT ?", arguments: [limit])
                .compactMap { try? Self.decode(CycleMetrics.self, $0) }.reversed()
        }
    }

    public func cycles(from: LocalDate, to: LocalDate) throws -> [CycleMetrics] {
        try writer.read { db in
            try String.fetchAll(db, sql: "SELECT json FROM cycle_metrics WHERE date >= ? AND date <= ? ORDER BY start_ts",
                                arguments: [from.isoString, to.isoString])
                .compactMap { try? Self.decode(CycleMetrics.self, $0) }
        }
    }

    public func activities(limit: Int = 100) throws -> [ActivityMetrics] {
        try writer.read { db in
            try String.fetchAll(db, sql: "SELECT json FROM fused_activity ORDER BY start_ts DESC LIMIT ?", arguments: [limit])
                .compactMap { try? Self.decode(ActivityMetrics.self, $0) }
        }
    }

    public func activity(id: String) throws -> ActivityMetrics? {
        try writer.read { db in
            try String.fetchOne(db, sql: "SELECT json FROM fused_activity WHERE id = ?", arguments: [id])
                .flatMap { try? Self.decode(ActivityMetrics.self, $0) }
        }
    }

    public func setStrainMode(_ mode: StrainMode, on date: LocalDate) throws {
        try writer.write { db in
            try db.execute(sql: "INSERT INTO strain_mode(date, mode) VALUES (?, ?) ON CONFLICT(date) DO UPDATE SET mode = excluded.mode",
                           arguments: [date.isoString, mode.rawValue])
        }
    }
}

// MARK: - Diario, análisis, informes y Coach

extension AppDatabase {
    public func saveJournalAnswer(_ a: JournalAnswer, note: String? = nil) throws {
        try writer.write { db in
            try db.execute(sql: """
                INSERT INTO journal_answer(date, question_key, yes, number, note, answered_at) VALUES (?,?,?,?,?,?)
                ON CONFLICT(date, question_key) DO UPDATE SET yes = excluded.yes, number = excluded.number, note = excluded.note,
                answered_at = excluded.answered_at
                """, arguments: [a.date.isoString, a.questionKey, a.yes, a.number, note, Date().timeIntervalSince1970])
        }
    }

    public func journalAnswers(on date: LocalDate) throws -> [JournalAnswer] {
        try writer.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM journal_answer WHERE date = ?", arguments: [date.isoString]).map { r in
                let yes: Int? = r["yes"]
                return JournalAnswer(date: date, questionKey: r["question_key"], yes: yes.map { $0 != 0 }, number: r["number"])
            }
        }
    }

    /// Respuestas del diario entre dos fechas (incluidas), para el Coach y las pantallas.
    public func journalAnswers(from: LocalDate, to: LocalDate) throws -> [JournalAnswer] {
        try writer.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM journal_answer WHERE date >= ? AND date <= ? AND question_key != 'note' ORDER BY date",
                             arguments: [from.isoString, to.isoString]).compactMap { r in
                guard let d = LocalDate(isoString: r["date"]) else { return nil }
                let yes: Int? = r["yes"]
                return JournalAnswer(date: d, questionKey: r["question_key"], yes: yes.map { $0 != 0 }, number: r["number"])
            }
        }
    }

    /// Notas libres del diario por fecha ISO.
    public func journalNotes(from: LocalDate, to: LocalDate) throws -> [String: String] {
        try writer.read { db in
            var out: [String: String] = [:]
            for r in try Row.fetchAll(db, sql: "SELECT date, note FROM journal_answer WHERE question_key = 'note' AND date >= ? AND date <= ?",
                                      arguments: [from.isoString, to.isoString]) {
                if let note: String = r["note"], !note.isEmpty { out[r["date"]] = note }
            }
            return out
        }
    }

    public func journalNote(on date: LocalDate) throws -> String? {
        try writer.read { db in
            try String.fetchOne(db, sql: "SELECT note FROM journal_answer WHERE date = ? AND question_key = 'note'", arguments: [date.isoString])
        }
    }

    public func saveDayAnalysis(_ a: StoredDayAnalysis) throws {
        try writer.write { db in
            try db.execute(sql: "INSERT OR REPLACE INTO day_analysis(id, cycle_id, date, created_at, kind, json, provider, model) VALUES (?,?,?,?,?,?,?,?)",
                           arguments: [a.id, a.cycleID, a.date, a.createdAt.timeIntervalSince1970, a.kind, a.json, a.provider, a.model])
        }
    }

    public func dayAnalyses(date: String) throws -> [StoredDayAnalysis] {
        try writer.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM day_analysis WHERE date = ? ORDER BY created_at DESC", arguments: [date]).map { r in
                StoredDayAnalysis(id: r["id"], cycleID: r["cycle_id"], date: r["date"], createdAt: Date(timeIntervalSince1970: r["created_at"]),
                                  kind: r["kind"], json: r["json"], provider: r["provider"], model: r["model"])
            }
        }
    }

    public func saveReport(id: String, type: String, periodStart: String, json: String) throws {
        try writer.write { db in
            try db.execute(sql: "INSERT OR REPLACE INTO report(id, type, period_start, json, created_at) VALUES (?,?,?,?,?)",
                           arguments: [id, type, periodStart, json, Date().timeIntervalSince1970])
        }
    }

    public func report(type: String, periodStart: String) throws -> String? {
        try writer.read { db in
            try String.fetchOne(db, sql: "SELECT json FROM report WHERE type = ? AND period_start = ? ORDER BY created_at DESC LIMIT 1",
                                arguments: [type, periodStart])
        }
    }

    public func reports(type: String) throws -> [(periodStart: String, json: String)] {
        try writer.read { db in
            try Row.fetchAll(db, sql: "SELECT period_start, json FROM report WHERE type = ? ORDER BY period_start DESC", arguments: [type])
                .map { ($0["period_start"], $0["json"]) }
        }
    }

    public func saveThread(_ t: CoachThread) throws {
        try writer.write { db in
            try db.execute(sql: """
                INSERT OR REPLACE INTO coach_thread(id, title, provider, model, created_at, updated_at, context_json) VALUES (?,?,?,?,?,?,?)
                """, arguments: [t.id, t.title, t.provider, t.model, t.createdAt.timeIntervalSince1970, t.updatedAt.timeIntervalSince1970,
                                 t.contextJSON])
        }
    }

    public func threads() throws -> [CoachThread] {
        try writer.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM coach_thread ORDER BY updated_at DESC").map(Self.thread)
        }
    }

    public func thread(id: String) throws -> CoachThread? {
        try writer.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM coach_thread WHERE id = ?", arguments: [id]).map(Self.thread)
        }
    }

    public func renameThread(id: String, title: String) throws {
        try writer.write { db in try db.execute(sql: "UPDATE coach_thread SET title = ? WHERE id = ?", arguments: [title, id]) }
    }

    static func thread(_ r: Row) -> CoachThread {
        CoachThread(id: r["id"], title: r["title"], provider: r["provider"], model: r["model"],
                    createdAt: Date(timeIntervalSince1970: r["created_at"]), updatedAt: Date(timeIntervalSince1970: r["updated_at"]),
                    contextJSON: r["context_json"])
    }

    public func deleteThread(id: String) throws {
        try writer.write { db in
            try db.execute(sql: "DELETE FROM coach_message WHERE thread_id = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM coach_thread WHERE id = ?", arguments: [id])
        }
    }

    public func deleteAllThreads() throws {
        try writer.write { db in
            try db.execute(sql: "DELETE FROM coach_message")
            try db.execute(sql: "DELETE FROM coach_thread")
        }
    }

    public func appendMessage(_ m: CoachMessageRecord) throws {
        try writer.write { db in
            try db.execute(sql: """
                INSERT OR REPLACE INTO coach_message(id, thread_id, role, model, content_json, display_text, input_tokens, output_tokens,
                cache_read, cache_write, cost_usd, rating, created_at, meta_json) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                """, arguments: [m.id, m.threadID, m.role, m.model, m.contentJSON, m.displayText, m.inputTokens, m.outputTokens,
                                 m.cacheReadTokens, m.cacheWriteTokens, m.costUSD, m.rating, m.createdAt.timeIntervalSince1970, m.metaJSON])
            try db.execute(sql: "UPDATE coach_thread SET updated_at = ? WHERE id = ?", arguments: [m.createdAt.timeIntervalSince1970, m.threadID])
        }
    }

    public func messages(threadID: String) throws -> [CoachMessageRecord] {
        try writer.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM coach_message WHERE thread_id = ? ORDER BY rowid", arguments: [threadID]).map { r in
                CoachMessageRecord(id: r["id"], threadID: r["thread_id"], role: r["role"], model: r["model"], contentJSON: r["content_json"],
                                   displayText: r["display_text"], inputTokens: r["input_tokens"], outputTokens: r["output_tokens"],
                                   cacheReadTokens: r["cache_read"], cacheWriteTokens: r["cache_write"], costUSD: r["cost_usd"],
                                   rating: r["rating"], createdAt: Date(timeIntervalSince1970: r["created_at"]), metaJSON: r["meta_json"])
            }
        }
    }

    public func rateMessage(id: String, rating: Int) throws {
        try writer.write { db in try db.execute(sql: "UPDATE coach_message SET rating = ? WHERE id = ?", arguments: [rating, id]) }
    }

    /// Gasto y nº de preguntas del Coach desde una fecha (límites de RF-COA-13).
    public func coachUsage(since: Date) throws -> (questions: Int, costUSD: Double) {
        try writer.read { db in
            let q = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM coach_message WHERE role = 'user' AND created_at >= ?",
                                     arguments: [since.timeIntervalSince1970]) ?? 0
            let c = try Double.fetchOne(db, sql: "SELECT COALESCE(SUM(cost_usd), 0) FROM coach_message WHERE created_at >= ?",
                                        arguments: [since.timeIntervalSince1970]) ?? 0
            return (q, c)
        }
    }

    /// Gasto del Coach por día local (se conserva aunque borres los hilos; límites de RF-COA-13).
    public func addCoachSpend(day: String, questions: Int, costUSD: Double) throws {
        try writer.write { db in
            try db.execute(sql: """
                INSERT INTO coach_spend(day, questions, cost_usd) VALUES (?,?,?)
                ON CONFLICT(day) DO UPDATE SET questions = questions + excluded.questions, cost_usd = cost_usd + excluded.cost_usd
                """, arguments: [day, questions, costUSD])
        }
    }

    /// Preguntas y gasto acumulados desde un día local (incluido), en formato AAAA-MM-DD.
    public func coachSpend(fromDay day: String) throws -> (questions: Int, costUSD: Double) {
        try writer.read { db in
            let row = try Row.fetchOne(db, sql: "SELECT COALESCE(SUM(questions), 0) AS q, COALESCE(SUM(cost_usd), 0) AS c FROM coach_spend WHERE day >= ?",
                                       arguments: [day])
            return (row?["q"] ?? 0, row?["c"] ?? 0)
        }
    }

    public func memory() throws -> [CoachMemoryItem] {
        try writer.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM coach_memory ORDER BY category, key").map {
                CoachMemoryItem(category: $0["category"], key: $0["key"], value: $0["value"], updatedAt: Date(timeIntervalSince1970: $0["updated_at"]))
            }
        }
    }

    public func saveMemory(_ m: CoachMemoryItem) throws {
        try writer.write { db in
            try db.execute(sql: "INSERT OR REPLACE INTO coach_memory(category, key, value, updated_at) VALUES (?,?,?,?)",
                           arguments: [m.category, m.key, m.value, m.updatedAt.timeIntervalSince1970])
        }
    }

    public func deleteMemory(category: String, key: String) throws {
        try writer.write { db in try db.execute(sql: "DELETE FROM coach_memory WHERE category = ? AND key = ?", arguments: [category, key]) }
    }

    /// Exportación completa en JSON legible (RF-PRI-01): un fichero por tabla, sin *tokens* ni claves.
    public func exportAll() throws -> [String: String] {
        try writer.read { db in
            var files: [String: String] = [:]
            let tables = ["app_state", "sync_log", "sleep_session", "vitals", "daily_source_totals", "vo2max", "activity",
                          "activity_annotation", "journal_answer", "strain_mode", "cycle_metrics", "fused_activity", "day_analysis",
                          "report", "coach_thread", "coach_message", "coach_memory", "coach_spend", "privacy_event", "activity_detail"]
            for table in tables {
                let rows = try Row.fetchAll(db, sql: "SELECT * FROM \(table)")
                let objects: [[String: Any]] = rows.map { row in
                    var o: [String: Any] = [:]
                    for (column, value) in row {
                        switch value.storage {
                        case .null: o[column] = NSNull()
                        case .int64(let i): o[column] = i
                        case .double(let d): o[column] = d
                        case .string(let s): o[column] = s
                        case .blob(let b): o[column] = b.base64EncodedString()
                        }
                    }
                    return o
                }
                let data = try JSONSerialization.data(withJSONObject: objects, options: [.prettyPrinted, .sortedKeys])
                files["\(table).json"] = String(decoding: data, as: UTF8.self)
            }
            return files
        }
    }

    /// «Borrar todos los datos» (RF-PRI-02): vacía todas las tablas.
    public func wipeAll() throws {
        try writer.write { db in
            for t in ["app_state", "sync_state", "sync_log", "hk_anchor", "hr_minute", "hr_sample", "activity_minute", "sleep_session",
                      "vitals", "daily_source_totals", "vo2max", "activity", "activity_annotation", "route_point",
                      "activity_metric_sample", "journal_answer", "strain_mode", "cycle_metrics", "fused_activity", "day_analysis",
                      "report", "coach_message", "coach_thread", "coach_memory", "coach_spend", "privacy_event",
                      "activity_detail", "run_summary"] {
                try db.execute(sql: "DELETE FROM \(t)")
            }
        }
        try writer.vacuum()
    }
}
