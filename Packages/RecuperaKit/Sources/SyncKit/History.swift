import Foundation
import HealthAPI
import MetricsKit
import Store

/// Por dónde va la importación del historial completo: todo lo anterior a la primera importación (180 días), de las dos
/// fuentes, hacia atrás y por tramos (doc. 10 §6, doc. 16 §6). Se guarda en `app_state` y se retoma donde se quedó.
public struct HistoryImportState: Codable, Sendable, Hashable {
    public enum Phase: String, Codable, Sendable {
        case apple, googleDaily, googleMinutes, metrics, done
    }

    /// Hasta dónde (hacia atrás) llega cada parte y desde dónde empezó.
    public var appleStart: Date?
    public var appleUntil: Date?
    public var appleEarliest: Date?
    public var appleDone = false
    public var googleDailyUntil: Date?
    public var googleEmptyChunks = 0
    public var googleDailyDone = false
    public var googleMinutesStart: Date?
    public var googleMinutesUntil: Date?
    public var googleMinutesDone = false
    public var metricsStart: Date?
    public var metricsUntil: Date?
    public var metricsDone = false
    /// El dato más antiguo encontrado en el historial.
    public var oldestData: Date?
    /// Entrenamientos del historial importados (de las dos fuentes).
    public var workouts = 0
    public var startedAt: Date?
    public var finishedAt: Date?
    public var lastError: String?
    /// Fallos seguidos en el mismo tramo: al tercero se salta (un tramo roto no puede bloquear el resto).
    public var failures = 0

    public init() {}

    public var phase: Phase {
        if !appleDone { return .apple }
        if !googleDailyDone { return .googleDaily }
        if !googleMinutesDone { return .googleMinutes }
        if !metricsDone { return .metrics }
        return .done
    }

    public var isComplete: Bool { phase == .done }

    /// Fase actual (1–4).
    public var step: Int {
        switch phase {
        case .apple: return 1
        case .googleDaily: return 2
        case .googleMinutes: return 3
        case .metrics, .done: return 4
        }
    }

    public var phaseLabel: String {
        switch phase {
        case .apple: return "Entrenamientos del Apple Watch"
        case .googleDaily: return "Noches, vitales y entrenamientos de la Fitbit"
        case .googleMinutes: return "Frecuencia cardiaca y pasos por minuto"
        case .metrics: return "Recalculando tus métricas del pasado"
        case .done: return "Historial completo"
        }
    }

    /// Progreso aproximado (0–1). La búsqueda en la Fitbit no sabe cuánto queda: cuenta como media fase.
    public var fraction: Double {
        func part(_ start: Date?, _ until: Date?, _ floor: Date?) -> Double {
            guard let start, let until, let floor, start > floor else { return 0 }
            return min(1, max(0, start.timeIntervalSince(until) / start.timeIntervalSince(floor)))
        }
        switch phase {
        case .apple: return 0.3 * part(appleStart, appleUntil, appleEarliest)
        case .googleDaily: return 0.3 + 0.3 * min(0.9, Double(googleEmptyChunks) / 8 + 0.3)
        case .googleMinutes: return 0.6 + 0.25 * part(googleMinutesStart, googleMinutesUntil, oldestData)
        case .metrics: return 0.85 + 0.15 * part(metricsStart, metricsUntil, oldestData)
        case .done: return 1
        }
    }

    mutating func noteOldest(_ date: Date?) {
        guard let date else { return }
        oldestData = min(oldestData ?? date, date)
    }
}

enum HistoryImportError: Error {
    /// La primera importación de Google aún no ha terminado: el historial va después.
    case waitingForFirstImport
}

extension SyncEngine {
    static let historyKey = "history_import"
    /// Lo que cubre la primera importación (algo menos, para solapar: los datos se guardan sin duplicarse).
    static let firstImportDays = 175.0
    static let appleChunkDays = 120.0
    static let googleDailyChunkDays = 90.0
    static let googleMinuteChunkDays = 14.0
    static let metricsChunkDays = 180.0
    /// Tramos seguidos sin nada en la Fitbit (≈ 2 años) para dar por encontrado el principio de tu cuenta.
    static let googleEmptyChunksToStop = 8

    public func historyState() -> HistoryImportState {
        (try? db.readState(Self.historyKey, default: HistoryImportState())) ?? HistoryImportState()
    }

    /// Al volver a vincular una fuente, su historial (y el recálculo) empiezan de nuevo.
    public func resetHistory(google: Bool, apple: Bool) {
        var s = historyState()
        if google {
            s.googleDailyUntil = nil
            s.googleEmptyChunks = 0
            s.googleDailyDone = false
            s.googleMinutesStart = nil
            s.googleMinutesUntil = nil
            s.googleMinutesDone = false
        }
        if apple {
            s.appleStart = nil
            s.appleUntil = nil
            s.appleEarliest = nil
            s.appleDone = false
        }
        s.metricsStart = nil
        s.metricsUntil = nil
        s.metricsDone = false
        s.finishedAt = nil
        s.failures = 0
        try? db.writeState(Self.historyKey, s)
    }

    /// Importa el historial completo hacia atrás, tramo a tramo, hasta terminar, agotar `budget` segundos o cancelarse la
    /// tarea. Guarda el estado tras cada tramo y avisa a `progress` (con `newData` si han llegado datos que enseñar).
    public func importHistory(budget: TimeInterval = .infinity,
                              progress: (@Sendable (HistoryImportState, _ newData: Bool) async -> Void)? = nil) async -> HistoryImportState {
        var state = historyState()
        guard !state.isComplete else { return state }
        let clock = Date()
        if state.startedAt == nil { state.startedAt = now() }
        while !state.isComplete, !Task.isCancelled, Date().timeIntervalSince(clock) < budget {
            let before = state
            do {
                let newData = try await historyStep(&state)
                state.lastError = nil
                state.failures = 0
                if state.isComplete { state.finishedAt = now() }
                try? db.writeState(Self.historyKey, state)
                await progress?(state, newData)
            } catch HistoryImportError.waitingForFirstImport {
                break
            } catch {
                state = before
                state.lastError = String(describing: error)
                // Sin conexión o sin permiso se reintenta más tarde; otro fallo repetido salta el tramo.
                if !Self.isTransient(error) {
                    state.failures += 1
                    if state.failures >= 3 {
                        skipChunk(&state)
                        state.failures = 0
                    }
                }
                try? db.writeState(Self.historyKey, state)
                try? db.log(SyncLogEntry(startedAt: clock, finishedAt: now(), source: "history", kind: before.phase.rawValue,
                                         status: "error", records: 0, error: state.lastError))
                await progress?(state, false)
                break
            }
        }
        return state
    }

    static func isTransient(_ error: Error) -> Bool {
        if let e = error as? HealthAPIError {
            switch e {
            case .reauthorizationRequired, .notConfigured: return true
            default: break
            }
        }
        return error is URLError || (error as NSError).domain == NSURLErrorDomain
    }

    /// Da por hecho el tramo actual (tras tres fallos seguidos).
    func skipChunk(_ s: inout HistoryImportState) {
        let day: TimeInterval = 86_400
        switch s.phase {
        case .apple:
            s.appleUntil = s.appleUntil.map { $0.addingTimeInterval(-Self.appleChunkDays * day) }
            if let u = s.appleUntil, let e = s.appleEarliest, u <= e { s.appleDone = true }
            if s.appleUntil == nil { s.appleDone = true }
        case .googleDaily:
            s.googleDailyUntil = s.googleDailyUntil.map { $0.addingTimeInterval(-Self.googleDailyChunkDays * day) }
            s.googleEmptyChunks += 1
            if s.googleDailyUntil == nil || s.googleEmptyChunks >= Self.googleEmptyChunksToStop { s.googleDailyDone = true }
        case .googleMinutes:
            s.googleMinutesUntil = s.googleMinutesUntil.map { $0.addingTimeInterval(-Self.googleMinuteChunkDays * day) }
            if s.googleMinutesUntil == nil { s.googleMinutesDone = true }
        case .metrics:
            s.metricsUntil = s.metricsUntil.map { $0.addingTimeInterval(-Self.metricsChunkDays * day) }
            if s.metricsUntil == nil { s.metricsDone = true }
        case .done:
            break
        }
    }

    /// Un tramo de la fase actual; devuelve si ha llegado algún dato nuevo.
    func historyStep(_ s: inout HistoryImportState) async throws -> Bool {
        let conn = (try? db.connection()) ?? ConnectionState()
        let settings = (try? db.settings()) ?? AppSettings()
        let day: TimeInterval = 86_400
        switch s.phase {
        case .apple:
            guard let apple, apple.isAvailable, settings.healthKitEnabled else {
                s.appleDone = true
                return false
            }
            if s.appleEarliest == nil {
                guard let earliest = await apple.earliestSampleDate() else {
                    s.appleDone = true
                    return false
                }
                s.appleEarliest = earliest
            }
            let start = s.appleStart ?? (conn.healthKitConnectedAt ?? now()).addingTimeInterval(-Self.firstImportDays * day)
            s.appleStart = start
            let upper = s.appleUntil ?? start
            let floor = s.appleEarliest ?? upper
            guard upper > floor else {
                s.appleDone = true
                return false
            }
            let lower = max(floor.addingTimeInterval(-day), upper.addingTimeInterval(-Self.appleChunkDays * day))
            let imp = try await apple.importHistory(from: lower, to: upper)
            try saveApple(imp)
            s.workouts += imp.workouts.count
            s.appleUntil = lower
            if lower <= floor { s.appleDone = true }
            s.noteOldest(imp.workouts.map(\.start).min())
            return !imp.workouts.isEmpty || !imp.vo2max.isEmpty

        case .googleDaily:
            guard let google, await google.isConnected() else {
                s.googleDailyDone = true
                s.googleMinutesDone = true
                return false
            }
            guard conn.backfillCompleted else { throw HistoryImportError.waitingForFirstImport }
            let upper = s.googleDailyUntil ?? (conn.connectedAt ?? now()).addingTimeInterval(-Self.firstImportDays * day)
            let lower = upper.addingTimeInterval(-Self.googleDailyChunkDays * day)
            let workoutsBefore = (try? db.activityIDs(source: .googleHealth).count) ?? 0
            let records = try await importGoogleDaily(google, from: lower, to: upper, utcOffset: utcOffset(), devices: false)
            s.workouts += max(0, ((try? db.activityIDs(source: .googleHealth).count) ?? 0) - workoutsBefore)
            s.googleDailyUntil = lower
            s.googleEmptyChunks = records == 0 ? s.googleEmptyChunks + 1 : 0
            if s.googleEmptyChunks >= Self.googleEmptyChunksToStop || lower < now().addingTimeInterval(-20 * 365 * day) {
                s.googleDailyDone = true
            }
            if records > 0 { s.noteOldest(try? db.oldestDataDate(source: .googleHealth)) }
            return records > 0

        case .googleMinutes:
            guard let google, await google.isConnected() else {
                s.googleMinutesDone = true
                return false
            }
            let start = s.googleMinutesStart ?? (conn.connectedAt ?? now()).addingTimeInterval(-Self.firstImportDays * day)
            s.googleMinutesStart = start
            let upper = s.googleMinutesUntil ?? start
            guard let floor = try db.oldestDataDate(source: .googleHealth), upper > floor else {
                s.googleMinutesDone = true
                return false
            }
            let lower = max(floor.addingTimeInterval(-day), upper.addingTimeInterval(-Self.googleMinuteChunkDays * day))
            let records = try await importGoogleMinutes(google, from: lower, to: upper)
            s.googleMinutesUntil = lower
            if lower <= floor { s.googleMinutesDone = true }
            return records > 0

        case .metrics:
            // Los ciclos anteriores a la ventana del motor (200 días), por tramos de 180 días con 6 semanas de rodaje.
            let start = s.metricsStart ?? now().addingTimeInterval(-195 * day)
            s.metricsStart = start
            let upper = s.metricsUntil ?? start
            guard let floor = try db.oldestDataDate(), upper > floor.addingTimeInterval(day) else {
                s.metricsDone = true
                return false
            }
            s.noteOldest(floor)
            let lower = max(floor, upper.addingTimeInterval(-Self.metricsChunkDays * day))
            let input = try db.metricsInput(from: lower.addingTimeInterval(-42 * day), until: upper.addingTimeInterval(2 * day),
                                            utcOffsetSeconds: utcOffset())
            // El motor, fuera del actor: una sincronización normal no espera a este cálculo.
            let out = await Task.detached(priority: .utility) { MetricsEngine.run(input) }.value
            try db.saveHistoricalCycles(out, from: lower, to: upper, computedAt: now())
            s.metricsUntil = lower
            if lower <= floor { s.metricsDone = true }
            return true

        case .done:
            return false
        }
    }
}
