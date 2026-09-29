import Foundation

// MARK: - ALG-VAL · Validez de datos

public enum Validity {
    public static let hrRange: ClosedRange<Double> = 25...230

    public static func isValidBPM(_ bpm: Double) -> Bool { hrRange.contains(bpm) }

    /// Descarta muestras fuera de rango y saltos > 40 lpm en ≤ 2 s sin continuidad (artefactos).
    public static func filterSamples(_ samples: [HRSample]) -> [HRSample] {
        let sorted = samples.filter { isValidBPM($0.bpm) }.sorted { $0.time < $1.time }
        guard sorted.count > 2 else { return sorted }
        var out: [HRSample] = []
        for i in sorted.indices {
            let s = sorted[i]
            if i > 0, i < sorted.count - 1 {
                let prev = sorted[i - 1], next = sorted[i + 1]
                let jumpIn = abs(s.bpm - prev.bpm) > 40 && s.time.timeIntervalSince(prev.time) <= 2
                let jumpOut = abs(next.bpm - s.bpm) > 40 && next.time.timeIntervalSince(s.time) <= 2
                // Un pico aislado (sube y vuelve) es un artefacto; un cambio sostenido no.
                if jumpIn && jumpOut { continue }
            }
            out.append(s)
        }
        return out
    }

    /// Agrega muestras a minutos (media, mín., máx. y nº de muestras).
    public static func minutes(from samples: [HRSample], source: DataSourceKind) -> [HRMinute] {
        var buckets: [Int: [Double]] = [:]
        for s in filterSamples(samples) {
            buckets[s.time.minuteEpoch, default: []].append(s.bpm)
        }
        return buckets.keys.sorted().map { m in
            let v = buckets[m]!
            return HRMinute(minute: m, bpmAvg: v.reduce(0, +) / Double(v.count), bpmMin: v.min(), bpmMax: v.max(),
                            samples: v.count, source: source)
        }
    }

    /// Noche válida para líneas base: sueño principal con ≥ 180 min dormidos y HRV presente.
    public static func isValidNight(sleep: SleepSession?, vitals: NightlyVitals?) -> Bool {
        guard let sleep, let vitals else { return false }
        return sleep.minutesAsleep >= 180 && (vitals.hrvRmssdAvg != nil || vitals.hrvRmssdDeep != nil)
    }

    /// Cobertura de FC nocturna = minutos con FC válida / minutos dormidos.
    public static func nightCoverage(sleep: SleepSession, hr: [Int: Double]) -> Double {
        let asleep = sleep.minutesAsleep
        guard asleep > 0 else { return 0 }
        var covered = 0
        var m = sleep.start.minuteEpoch
        let end = sleep.end.minuteEpoch
        while m < end {
            if let v = hr[m], isValidBPM(v) { covered += 1 }
            m += 60
        }
        return min(1, Double(covered) / asleep)
    }
}

// MARK: - ALG-SUE-00 · Sueño principal y siestas

public enum SleepClassifier {
    /// Devuelve los identificadores de sesiones principales (una por noche como mucho).
    public static func mainSessions(_ sessions: [SleepSession]) -> Set<String> {
        var result = Set<String>()
        // Agrupa por fecha de despertar y elige una principal por día.
        let byDate = Dictionary(grouping: sessions, by: { $0.wakeDate })
        for (_, list) in byDate {
            if let flagged = list.filter({ $0.isMainFromSource == true }).max(by: { $0.minutesAsleep < $1.minutesAsleep }) {
                result.insert(flagged.id)
                continue
            }
            let candidates = list.filter { s in
                guard s.isNapFromSource != true, s.minutesAsleep >= 180 else { return false }
                let local = localHour(of: s.end, offset: s.utcOffsetSeconds)
                return local >= 3 && local < 15
            }
            if let main = candidates.max(by: { $0.minutesAsleep < $1.minutesAsleep }) {
                result.insert(main.id)
            }
        }
        return result
    }

    /// Siestas: el resto de sesiones de ≥ 15 min.
    public static func naps(_ sessions: [SleepSession], mainIDs: Set<String>) -> [SleepSession] {
        sessions.filter { !mainIDs.contains($0.id) && $0.minutesAsleep >= 15 }
    }

    static func localHour(of date: Date, offset: Int) -> Double {
        let secs = Int(date.timeIntervalSince1970) + offset
        let daySecs = ((secs % 86_400) + 86_400) % 86_400
        return Double(daySecs) / 3600
    }
}

// MARK: - ALG-CIC-01 · Ciclo fisiológico

public struct Cycle: Hashable, Codable, Sendable, Identifiable {
    public var id: String
    public var start: Date
    public var end: Date?               // nil = ciclo abierto (el actual)
    public var sleepSessionID: String?  // sueño principal que lo inicia
    public var isFallback: Bool
    public var utcOffsetSeconds: Int

    /// Día al que pertenece (fecha local de inicio).
    public var date: LocalDate { LocalDate(start, utcOffsetSeconds: utcOffsetSeconds) }

    public func range(now: Date) -> TimeRange { TimeRange(start: start, end: end ?? max(now, start)) }

    public func contains(_ date: Date, now: Date) -> Bool { range(now: now).contains(date) }
}

public enum CycleBuilder {
    /// Un ciclo va del fin de un sueño principal al fin del siguiente. Si pasan más de 30 h sin sueño
    /// principal, el ciclo se cierra a las 04:00 locales y siguen ciclos de reserva 04:00–04:00.
    public static func cycles(mainSleeps: [SleepSession], firstDay: LocalDate, now: Date, utcOffsetSeconds: Int) -> [Cycle] {
        let sleeps = mainSleeps.filter { $0.end <= now }.sorted { $0.end < $1.end }
        var out: [Cycle] = []

        func fallback(_ start: Date, _ end: Date?, _ offset: Int) -> Cycle {
            Cycle(id: "fb-\(Int(start.timeIntervalSince1970))", start: start, end: end, sleepSessionID: nil,
                  isFallback: true, utcOffsetSeconds: offset)
        }

        func fillFallbacks(from start: Date, until end: Date?, offset: Int) {
            var s = start
            while true {
                let n = next0400(after: s.addingTimeInterval(3600), offset: offset)
                if let end, n >= end {
                    if end > s { out.append(fallback(s, end, offset)) }
                    return
                }
                if end == nil, n > now {
                    out.append(fallback(s, nil, offset))
                    return
                }
                out.append(fallback(s, n, offset))
                s = n
            }
        }

        guard !sleeps.isEmpty else {
            let start = firstDay.startDate(utcOffsetSeconds: utcOffsetSeconds).addingTimeInterval(4 * 3600)
            fillFallbacks(from: min(start, now), until: nil, offset: utcOffsetSeconds)
            return out
        }

        for (i, s) in sleeps.enumerated() {
            let next = i + 1 < sleeps.count ? sleeps[i + 1].end : nil
            let limit = next ?? now
            if limit.timeIntervalSince(s.end) > 30 * 3600 {
                let close = next0400(after: s.end.addingTimeInterval(12 * 3600), offset: s.utcOffsetSeconds)
                out.append(Cycle(id: "c-\(s.id)", start: s.end, end: close, sleepSessionID: s.id, isFallback: false,
                                 utcOffsetSeconds: s.utcOffsetSeconds))
                fillFallbacks(from: close, until: next, offset: s.utcOffsetSeconds)
            } else {
                out.append(Cycle(id: "c-\(s.id)", start: s.end, end: next, sleepSessionID: s.id, isFallback: false,
                                 utcOffsetSeconds: s.utcOffsetSeconds))
            }
        }
        return out
    }

    /// Primeras 04:00 locales estrictamente posteriores a `date`.
    public static func next0400(after date: Date, offset: Int) -> Date {
        let day = LocalDate(date, utcOffsetSeconds: offset)
        var t = day.startDate(utcOffsetSeconds: offset).addingTimeInterval(4 * 3600)
        while t <= date { t = t.addingTimeInterval(86_400) }
        return t
    }
}
