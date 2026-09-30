import Foundation
import GRDB
import MetricsKit

// MARK: - Historial completo (más allá de la ventana del motor)

extension AppDatabase {
    /// Actividades de todas las fechas (o anteriores a `before`) con las anotaciones del usuario aplicadas.
    public func allActivities(before: Date? = nil) throws -> [ActivitySession] {
        try writer.read { db in
            let rows = try String.fetchAll(db, sql: "SELECT json FROM activity WHERE start_ts < ? ORDER BY start_ts",
                                           arguments: [before?.timeIntervalSince1970 ?? .greatestFiniteMagnitude])
            return Self.annotated(rows.compactMap { try? Self.decode(ActivitySession.self, $0) }, try Self.annotations(db))
        }
    }

    /// Guarda los ciclos de un tramo del pasado, [from, to), sin tocar los demás (los recientes los guarda `saveMetrics`).
    /// Los días sin ningún dato (antes de tener pulsera, o sin llevarla) no se guardan.
    public func saveHistoricalCycles(_ output: MetricsOutput, from: Date, to: Date, computedAt: Date = Date()) throws {
        let lo = from.timeIntervalSince1970, hi = to.timeIntervalSince1970
        let cycles = output.cycles.filter { c in
            let t = c.cycle.start.timeIntervalSince1970
            let hasData = c.sleepSession != nil || c.vitals != nil || !c.activities.isEmpty || c.strain.validHours > 0
            return !c.isOpen && t >= lo && t < hi && hasData
        }
        let rows = try cycles.map { c in (c, try Self.json(c)) }
        let fused = try cycles.flatMap(\.activities).map { a in (a, try Self.json(a)) }
        try writer.write { db in
            try db.execute(sql: "DELETE FROM cycle_metrics WHERE start_ts >= ? AND start_ts < ?", arguments: [lo, hi])
            try db.execute(sql: "DELETE FROM fused_activity WHERE start_ts >= ? AND start_ts < ?", arguments: [lo, hi])
            try Self.insert(db, cycles: rows, fused: fused, algorithmVersion: output.algorithmVersion, computedAt: computedAt)
        }
    }

    static func insert(_ db: Database, cycles rows: [(CycleMetrics, String)], fused: [(ActivityMetrics, String)],
                       algorithmVersion: String, computedAt: Date) throws {
        let st = try db.makeStatement(sql: """
            INSERT OR REPLACE INTO cycle_metrics(id, date, start_ts, end_ts, is_open, recovery, strain, sleep_performance, hrv, rhr,
            stress, steps, json, algorithm_version, computed_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
            """)
        for (c, json) in rows {
            let hrv = c.recovery.components.first { $0.kind == .hrv }?.value ?? c.vitals?.hrvRmssdAvg
            try st.execute(arguments: [c.id, c.date.isoString, c.cycle.start.timeIntervalSince1970, c.cycle.end?.timeIntervalSince1970,
                                       c.isOpen, c.recovery.score, c.strain.strain, c.sleep?.performance, hrv, c.vitals?.restingHR,
                                       c.stress.average, c.totals?.steps, json, algorithmVersion, computedAt.timeIntervalSince1970])
        }
        for (a, json) in fused {
            try db.execute(sql: "INSERT OR REPLACE INTO fused_activity(id, start_ts, kind, strain, json) VALUES (?,?,?,?,?)",
                           arguments: [a.id, a.activity.start.timeIntervalSince1970, a.activity.kind.rawValue, a.strain.strain, json])
        }
    }

    /// Ciclos guardados que empiezan antes de `before`, del más antiguo al más reciente (tendencias de un año o de siempre).
    public func cycleHistory(before: Date, since: Date? = nil) throws -> [CycleMetrics] {
        try writer.read { db in
            try String.fetchAll(db, sql: "SELECT json FROM cycle_metrics WHERE start_ts < ? AND start_ts >= ? AND is_open = 0 ORDER BY start_ts",
                                arguments: [before.timeIntervalSince1970, since?.timeIntervalSince1970 ?? 0])
                .compactMap { try? Self.decode(CycleMetrics.self, $0) }
        }
    }

    /// Carga diaria (TRIMP del día entero) de los ciclos guardados desde `since`: fecha → carga.
    public func dailyLoads(since: Date) throws -> [LocalDate: Double] {
        try writer.read { db in
            var out: [LocalDate: Double] = [:]
            for json in try String.fetchAll(db, sql: "SELECT json FROM cycle_metrics WHERE start_ts >= ? ORDER BY start_ts",
                                            arguments: [since.timeIntervalSince1970]) {
                if let c = try? Self.decode(CycleMetrics.self, json) { out[c.date] = c.strain.loadRaw }
            }
            return out
        }
    }

    /// Fecha del dato más antiguo guardado (sueño, entrenamiento o vitales), de una fuente o de las dos.
    public func oldestDataDate(source: DataSourceKind? = nil) throws -> Date? {
        try writer.read { db in
            var candidates: [Date] = []
            let filter = source.map { " WHERE source = '\($0.rawValue)'" } ?? ""
            if let t = try Double.fetchOne(db, sql: "SELECT MIN(start_ts) FROM sleep_session" + filter) {
                candidates.append(Date(timeIntervalSince1970: t))
            }
            if let t = try Double.fetchOne(db, sql: "SELECT MIN(start_ts) FROM activity" + filter) {
                candidates.append(Date(timeIntervalSince1970: t))
            }
            // Las vitales solo llegan de la Fitbit.
            if source == nil || source == .googleHealth,
               let d = try String.fetchOne(db, sql: "SELECT MIN(date) FROM vitals").flatMap({ LocalDate(isoString: $0) }) {
                candidates.append(d.startDate(utcOffsetSeconds: 0))
            }
            return candidates.min()
        }
    }
}
