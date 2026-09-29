import Foundation
import Insights
import MetricsKit
import Store

/// Notificación local que la app debe programar (catálogo del doc. 11 §8).
public struct PlannedNotification: Codable, Sendable, Hashable {
    public var id: String          // NOT-xx
    public var key: String         // clave única para no repetirla
    public var title: String
    public var body: String
    public var critical: Bool

    public init(id: String, key: String, title: String, body: String, critical: Bool = false) {
        self.id = id
        self.key = key
        self.title = title
        self.body = body
        self.critical = critical
    }
}

public enum NotificationPlanner {
    /// Decide qué avisos tocan tras una sincronización. `sent` son las claves ya enviadas (con su fecha).
    public static func plan(output: MetricsOutput, newWatchWorkoutIDs: [String], connection: ConnectionState, settings: AppSettings,
                            sent: [String: Date], now: Date, utcOffsetSeconds: Int,
                            weeklyPlan: WeeklyPlanProgress? = nil) -> [PlannedNotification] {
        var out: [PlannedNotification] = []
        let todayDate = LocalDate(now, utcOffsetSeconds: utcOffsetSeconds)
        let today = todayDate.isoString
        let showValues = settings.lockscreenShowsValues
        func allowed(_ id: String) -> Bool { settings.isOn(id) }
        func notSent(_ key: String) -> Bool { sent[key] == nil }

        if let cur = output.current {
            if allowed("NOT-01"), let score = cur.recovery.score, cur.sleep != nil, notSent("NOT-01:\(cur.date.isoString)") {
                out.append(PlannedNotification(id: "NOT-01", key: "NOT-01:\(cur.date.isoString)", title: "Recuperación lista",
                                               body: showValues ? "Tu recuperación de hoy: \(score) %." : "Tu recuperación de hoy está lista."))
            }
            if allowed("NOT-04"), cur.health?.combinedAlert == true, notSent("NOT-04:\(cur.date.isoString)") {
                out.append(PlannedNotification(id: "NOT-04", key: "NOT-04:\(cur.date.isoString)", title: "Métricas nocturnas",
                                               body: "Tus métricas nocturnas están fuera de tu rango habitual. Tómatelo con calma."))
            }
            if allowed("NOT-03"), let t = cur.target, cur.strain.strain >= t.low, notSent("NOT-03:\(today)") {
                out.append(PlannedNotification(id: "NOT-03", key: "NOT-03:\(today)", title: "Carga objetivo",
                                               body: "Has alcanzado tu carga objetivo de hoy."))
            }
            if allowed("NOT-09"), cur.stress.sustainedHigh, notSent("NOT-09:\(today)") {
                out.append(PlannedNotification(id: "NOT-09", key: "NOT-09:\(today)", title: "Estrés",
                                               body: "Llevas un rato con estrés alto. ¿Un minuto de respiración?"))
            }
        }

        // NOT-11 · revisión del plan semanal el viernes (RF-PLA-03).
        if allowed("NOT-11"), todayDate.isoWeekday == 5, let p = weeklyPlan, !p.items.isEmpty,
           notSent("NOT-11:\(p.weekStart.isoString)") {
            out.append(PlannedNotification(id: "NOT-11", key: "NOT-11:\(p.weekStart.isoString)", title: "Plan semanal",
                                           body: WeeklyPlanner.fridayReview(p)))
        }

        // NOT-05 · informe de la semana pasada, el lunes (RF-INF-01).
        if allowed("NOT-05"), todayDate.isoWeekday == 1 {
            let lastWeek = todayDate.adding(days: -7)
            let days = output.cycles.filter { $0.date >= lastWeek && $0.date < todayDate && $0.recovery.score != nil }.count
            if days >= 3, notSent("NOT-05:\(lastWeek.isoString)") {
                out.append(PlannedNotification(id: "NOT-05", key: "NOT-05:\(lastWeek.isoString)", title: "Informe semanal",
                                               body: "Tu informe semanal está listo."))
            }
        }

        // NOT-12 · carrera nueva del Apple Watch.
        if allowed("NOT-12") {
            for id in newWatchWorkoutIDs where notSent("NOT-12:\(id)") {
                guard let act = output.cycles.flatMap(\.activities).first(where: { $0.activity.members.contains { $0.id == id } }) else { continue }
                var body = "\(act.activity.name)"
                if let d = act.activity.distanceM, d > 0 { body += " de \(Format.km(d))" }
                body += " importada · carga \(Format.decimal(act.strain.strain))"
                out.append(PlannedNotification(id: "NOT-12", key: "NOT-12:\(id)", title: "Apple Watch", body: body))
            }
        }

        // NOT-06 · sin datos de la pulsera en 24 h.
        if allowed("NOT-06"), connection.googleStatus == .active, let last = connection.deviceLastSyncAt,
           now.timeIntervalSince(last) > 24 * 3600, (sent["NOT-06"].map { now.timeIntervalSince($0) > 24 * 3600 } ?? true) {
            out.append(PlannedNotification(id: "NOT-06", key: "NOT-06", title: "Sin datos",
                                           body: "No llegan datos desde ayer. ¿Está cargada y sincronizada la pulsera?"))
        }
        // NOT-07 · reconectar (crítica).
        if connection.googleStatus == .needsReauth, (sent["NOT-07"].map { now.timeIntervalSince($0) > 24 * 3600 } ?? true) {
            out.append(PlannedNotification(id: "NOT-07", key: "NOT-07", title: "Google Health", body: "Vuelve a conectar Google Health.",
                                           critical: true))
        }
        return limit(out, sent: sent, now: now, settings: settings, utcOffsetSeconds: utcOffsetSeconds)
    }

    /// Máximo 3 no críticas al día y horas de silencio (salvo críticas).
    static func limit(_ list: [PlannedNotification], sent: [String: Date], now: Date, settings: AppSettings,
                      utcOffsetSeconds: Int) -> [PlannedNotification] {
        let secs = ((Int(now.timeIntervalSince1970) + utcOffsetSeconds) % 86_400 + 86_400) % 86_400
        let minuteOfDay = secs / 60
        let quiet = settings.quietHoursStart > settings.quietHoursEnd
            ? (minuteOfDay >= settings.quietHoursStart || minuteOfDay < settings.quietHoursEnd)
            : (minuteOfDay >= settings.quietHoursStart && minuteOfDay < settings.quietHoursEnd)
        let sentToday = sent.values.filter { now.timeIntervalSince($0) < 86_400 }.count
        var budget = max(0, 3 - sentToday)
        var out: [PlannedNotification] = []
        for n in list {
            if n.critical { out.append(n); continue }
            if quiet && n.id != "NOT-01" { continue }
            if budget > 0 { out.append(n); budget -= 1 }
        }
        return out
    }
}
