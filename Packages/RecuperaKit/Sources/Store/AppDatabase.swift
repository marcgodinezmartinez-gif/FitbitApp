import Foundation
import GRDB
import MetricsKit

/// Base de datos local (SQLite con GRDB, doc. 09). Un solo usuario; todo vive en el iPhone.
public final class AppDatabase: Sendable {
    public let writer: any DatabaseWriter

    public init(_ writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    /// BD en fichero con protección de datos de iOS (la aplica la app al crear el fichero).
    public static func open(at url: URL) throws -> AppDatabase {
        var config = Configuration()
        config.foreignKeysEnabled = true
        let pool = try DatabasePool(path: url.path, configuration: config)
        return try AppDatabase(pool)
    }

    public static func inMemory() throws -> AppDatabase {
        try AppDatabase(DatabaseQueue(configuration: Configuration()))
    }

    static var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()
        m.registerMigration("v1") { db in
            try db.execute(sql: """
            CREATE TABLE app_state (key TEXT PRIMARY KEY, json TEXT NOT NULL);
            CREATE TABLE sync_state (data_type TEXT PRIMARY KEY, synced_until REAL, last_run_at REAL, last_error TEXT);
            CREATE TABLE sync_log (id INTEGER PRIMARY KEY AUTOINCREMENT, started_at REAL, finished_at REAL, source TEXT,
                                   kind TEXT, status TEXT, records INTEGER, error TEXT);
            CREATE TABLE hk_anchor (sample_type TEXT PRIMARY KEY, anchor BLOB, updated_at REAL);
            CREATE TABLE hr_minute (source TEXT NOT NULL, minute INTEGER NOT NULL, bpm_avg REAL NOT NULL, bpm_min REAL,
                                    bpm_max REAL, samples INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (source, minute)) WITHOUT ROWID;
            CREATE TABLE hr_sample (source TEXT NOT NULL, ts REAL NOT NULL, bpm REAL NOT NULL, activity_id TEXT,
                                    PRIMARY KEY (source, ts)) WITHOUT ROWID;
            CREATE INDEX hr_sample_activity ON hr_sample(activity_id);
            CREATE TABLE activity_minute (source TEXT NOT NULL, minute INTEGER NOT NULL, steps INTEGER NOT NULL,
                                          distance_m REAL NOT NULL, PRIMARY KEY (source, minute)) WITHOUT ROWID;
            CREATE TABLE sleep_session (id TEXT PRIMARY KEY, source TEXT NOT NULL, start_ts REAL NOT NULL, end_ts REAL NOT NULL,
                                        json TEXT NOT NULL);
            CREATE INDEX sleep_session_end ON sleep_session(end_ts);
            CREATE TABLE vitals (date TEXT PRIMARY KEY, json TEXT NOT NULL);
            CREATE TABLE daily_source_totals (date TEXT NOT NULL, source TEXT NOT NULL, steps INTEGER, distance_m REAL,
                                              calories REAL, PRIMARY KEY (date, source));
            CREATE TABLE vo2max (date TEXT NOT NULL, source TEXT NOT NULL, value REAL NOT NULL, PRIMARY KEY (date, source));
            CREATE TABLE activity (id TEXT PRIMARY KEY, source TEXT NOT NULL, source_record_id TEXT NOT NULL,
                                   start_ts REAL NOT NULL, end_ts REAL NOT NULL, kind TEXT NOT NULL, is_manual INTEGER NOT NULL,
                                   json TEXT NOT NULL, UNIQUE (source, source_record_id));
            CREATE INDEX activity_start ON activity(start_ts);
            CREATE TABLE activity_annotation (activity_id TEXT PRIMARY KEY, json TEXT NOT NULL);
            CREATE TABLE route_point (activity_id TEXT NOT NULL, ts REAL NOT NULL, lat REAL NOT NULL, lon REAL NOT NULL,
                                      alt REAL, speed REAL, h_acc REAL, PRIMARY KEY (activity_id, ts)) WITHOUT ROWID;
            CREATE TABLE activity_metric_sample (activity_id TEXT NOT NULL, metric TEXT NOT NULL, ts REAL NOT NULL,
                                                 value REAL NOT NULL, PRIMARY KEY (activity_id, metric, ts)) WITHOUT ROWID;
            CREATE TABLE journal_answer (date TEXT NOT NULL, question_key TEXT NOT NULL, yes INTEGER, number REAL, note TEXT,
                                         answered_at REAL, PRIMARY KEY (date, question_key));
            CREATE TABLE strain_mode (date TEXT PRIMARY KEY, mode TEXT NOT NULL);
            CREATE TABLE cycle_metrics (id TEXT PRIMARY KEY, date TEXT NOT NULL, start_ts REAL NOT NULL, end_ts REAL,
                                        is_open INTEGER NOT NULL, recovery INTEGER, strain REAL, sleep_performance REAL,
                                        hrv REAL, rhr REAL, stress REAL, steps INTEGER, json TEXT NOT NULL,
                                        algorithm_version TEXT NOT NULL, computed_at REAL NOT NULL);
            CREATE INDEX cycle_metrics_date ON cycle_metrics(date);
            CREATE TABLE fused_activity (id TEXT PRIMARY KEY, start_ts REAL NOT NULL, kind TEXT NOT NULL, strain REAL,
                                         json TEXT NOT NULL);
            CREATE INDEX fused_activity_start ON fused_activity(start_ts);
            CREATE TABLE day_analysis (id TEXT PRIMARY KEY, cycle_id TEXT NOT NULL, date TEXT NOT NULL, created_at REAL NOT NULL,
                                       kind TEXT NOT NULL, json TEXT NOT NULL, provider TEXT, model TEXT);
            CREATE INDEX day_analysis_date ON day_analysis(date);
            CREATE TABLE report (id TEXT PRIMARY KEY, type TEXT NOT NULL, period_start TEXT NOT NULL, json TEXT NOT NULL,
                                 created_at REAL NOT NULL);
            CREATE TABLE coach_thread (id TEXT PRIMARY KEY, title TEXT NOT NULL, provider TEXT NOT NULL, model TEXT NOT NULL,
                                       created_at REAL NOT NULL, updated_at REAL NOT NULL);
            CREATE TABLE coach_message (id TEXT PRIMARY KEY, thread_id TEXT NOT NULL REFERENCES coach_thread(id) ON DELETE CASCADE,
                                        role TEXT NOT NULL, model TEXT, content_json TEXT NOT NULL, display_text TEXT NOT NULL,
                                        input_tokens INTEGER NOT NULL DEFAULT 0, output_tokens INTEGER NOT NULL DEFAULT 0,
                                        cache_read INTEGER NOT NULL DEFAULT 0, cache_write INTEGER NOT NULL DEFAULT 0,
                                        cost_usd REAL NOT NULL DEFAULT 0, rating INTEGER, created_at REAL NOT NULL);
            CREATE INDEX coach_message_thread ON coach_message(thread_id, created_at);
            CREATE TABLE coach_memory (category TEXT NOT NULL, key TEXT NOT NULL, value TEXT NOT NULL, updated_at REAL NOT NULL,
                                       PRIMARY KEY (category, key));
            CREATE TABLE privacy_event (id INTEGER PRIMARY KEY AUTOINCREMENT, at REAL NOT NULL, action TEXT NOT NULL);
            """)
        }
        // v2 · Coach: contexto congelado de cada hilo (sistema + herramientas) y metadatos de cada mensaje.
        m.registerMigration("v2") { db in
            try db.execute(sql: """
            ALTER TABLE coach_thread ADD COLUMN context_json TEXT;
            ALTER TABLE coach_message ADD COLUMN meta_json TEXT;
            CREATE TABLE coach_spend (day TEXT PRIMARY KEY, questions INTEGER NOT NULL DEFAULT 0, cost_usd REAL NOT NULL DEFAULT 0);
            """)
        }
        // v3 · Carreras (doc. 18): datos ampliados de cada entreno y caché de su análisis.
        m.registerMigration("v3") { db in
            try db.execute(sql: """
            CREATE TABLE activity_detail (activity_id TEXT PRIMARY KEY, json TEXT NOT NULL);
            CREATE TABLE run_summary (activity_id TEXT PRIMARY KEY, version INTEGER NOT NULL, start_ts REAL NOT NULL, json TEXT NOT NULL);
            CREATE INDEX run_summary_start ON run_summary(start_ts);
            """)
        }
        return m
    }

    // MARK: - JSON

    nonisolated(unsafe) static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }()

    nonisolated(unsafe) static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()

    static func json<T: Encodable>(_ value: T) throws -> String {
        String(data: try encoder.encode(value), encoding: .utf8) ?? "{}"
    }

    static func decode<T: Decodable>(_ type: T.Type, _ string: String) throws -> T {
        try decoder.decode(T.self, from: Data(string.utf8))
    }

    /// Decodifica fusionando con los valores por defecto (así los ajustes nuevos no rompen los guardados).
    static func decodeMerging<T: Codable>(_ string: String, defaults: T) -> T {
        guard let stored = try? JSONSerialization.jsonObject(with: Data(string.utf8)) as? [String: Any],
              let base = try? JSONSerialization.jsonObject(with: encoder.encode(defaults)) as? [String: Any] else { return defaults }
        let merged = base.merging(stored) { _, new in new }
        guard let data = try? JSONSerialization.data(withJSONObject: merged),
              let value = try? decoder.decode(T.self, from: data) else { return defaults }
        return value
    }
}
