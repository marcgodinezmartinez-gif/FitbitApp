import Foundation

// MARK: - ALG-FUS · Fusión de la Fitbit Air y el Apple Watch

/// Actividad tal como la ves: una o varias sesiones de origen unidas (ALG-FUS-02).
public struct FusedActivity: Hashable, Codable, Sendable, Identifiable {
    public var id: String
    public var members: [ActivitySession]      // la principal primero
    public var start: Date
    public var end: Date
    public var kind: ActivityKind
    public var isLeftover: Bool
    public var hrSource: DataSourceKind?
    public var sourcesDisagree: Bool
    public var agreement: HRAgreement?

    public var primary: ActivitySession { members[0] }
    public var range: TimeRange { TimeRange(start: start, end: end) }
    public var durationMinutes: Double { end.timeIntervalSince(start) / 60 }

    public var sources: [DataSourceKind] {
        var seen: [DataSourceKind] = []
        for m in members where !seen.contains(m.source) { seen.append(m.source) }
        return seen
    }

    public var watchMember: ActivitySession? { members.first { $0.source == .appleHealth } }
    public var fitbitMember: ActivitySession? { members.first { $0.source == .googleHealth } }

    /// Datos propios del entrenamiento: los del Watch si está (ALG-FUS-01).
    public var distanceM: Double? { isLeftover ? nil : (watchMember?.distanceM ?? primary.distanceM) }
    public var caloriesKcal: Double? { isLeftover ? nil : (watchMember?.caloriesKcal ?? primary.caloriesKcal) }
    public var rpe: Double? { members.compactMap(\.rpe).first }
    public var notes: String? { members.compactMap(\.notes).first }
    public var name: String { primary.name ?? kind.displayName }

    /// Ritmo medio en segundos por km (carreras con distancia).
    public var paceSecondsPerKm: Double? {
        guard let d = distanceM, d > 200 else { return nil }
        return durationMinutes * 60 / (d / 1000)
    }
}

public struct HRAgreement: Hashable, Codable, Sendable {
    public var bias: Double          // media Watch − Fitbit (lpm)
    public var loaLow: Double        // límite inferior de concordancia al 95 %
    public var loaHigh: Double
    public var minutes: Int
}

public struct FusedHRMinute: Hashable, Codable, Sendable {
    public var minute: Int
    public var bpm: Double
    public var source: DataSourceKind

    public init(minute: Int, bpm: Double, source: DataSourceKind) {
        self.minute = minute
        self.bpm = bpm
        self.source = source
    }
}

public struct DailyTotals: Hashable, Codable, Sendable {
    public var date: LocalDate
    public var steps: Int
    public var distanceM: Double
    public var caloriesKcal: Double
    public var sources: [DataSourceKind]
    public var gpsReplacedM: Double

    public init(date: LocalDate, steps: Int, distanceM: Double, caloriesKcal: Double, sources: [DataSourceKind], gpsReplacedM: Double = 0) {
        self.date = date
        self.steps = steps
        self.distanceM = distanceM
        self.caloriesKcal = caloriesKcal
        self.sources = sources
        self.gpsReplacedM = gpsReplacedM
    }
}

public enum Fusion {
    // MARK: ALG-FUS-02 · Emparejar actividades

    public static func fuseActivities(_ sessions: [ActivitySession], params: AlgorithmParams) -> [FusedActivity] {
        let watch = sessions.filter { $0.source == .appleHealth }.sorted { $0.start < $1.start }
        let fitbit = sessions.filter { $0.source == .googleHealth && !$0.isManual }.sorted { $0.start < $1.start }
        let manual = sessions.filter { $0.source == .manual || ($0.isManual && $0.source != .appleHealth) }
        var result: [FusedActivity] = []
        var matchedRanges: [String: [TimeRange]] = [:]   // id de la sesión de la Fitbit -> Watch con los que empareja

        for w in watch {
            var members = [w]
            for f in fitbit {
                let ov = f.range.overlap(with: w.range)
                let shortest = min(f.range.duration, w.range.duration)
                guard shortest > 0, ov / shortest >= params.fusion.matchOverlap else { continue }
                members.append(f)
                matchedRanges[f.id, default: []].append(w.range)
            }
            result.append(FusedActivity(id: w.id, members: members, start: w.start, end: w.end, kind: w.kind,
                                        isLeftover: false, hrSource: nil, sourcesDisagree: false, agreement: nil))
        }
        for f in fitbit {
            guard let ranges = matchedRanges[f.id] else {
                result.append(FusedActivity(id: f.id, members: [f], start: f.start, end: f.end, kind: f.kind,
                                            isLeftover: false, hrSource: nil, sourcesDisagree: false, agreement: nil))
                continue
            }
            for (k, piece) in f.range.subtracting(ranges).enumerated() where piece.minutes >= params.fusion.minLeftoverMin {
                var part = f
                part.start = piece.start
                part.end = piece.end
                part.distanceM = nil
                part.caloriesKcal = nil
                part.steps = nil
                result.append(FusedActivity(id: "\(f.id)#\(k + 1)", members: [part], start: piece.start, end: piece.end,
                                            kind: f.kind, isLeftover: true, hrSource: nil, sourcesDisagree: false, agreement: nil))
            }
        }
        for m in manual {
            result.append(FusedActivity(id: m.id, members: [m], start: m.start, end: m.end, kind: m.kind,
                                        isLeftover: false, hrSource: nil, sourcesDisagree: false, agreement: nil))
        }
        return result.sorted { $0.start < $1.start }
    }

    // MARK: ALG-FUS-03 · FC por minuto fusionada

    public static func fuseHeartRate(fitbit: [HRMinute], watch: [HRMinute], watchWorkouts: [TimeRange],
                                     params: AlgorithmParams) -> [FusedHRMinute] {
        let f = Dictionary(fitbit.filter { Validity.isValidBPM($0.bpmAvg) }.map { ($0.minute, $0) }, uniquingKeysWith: { a, _ in a })
        let w = Dictionary(watch.filter { Validity.isValidBPM($0.bpmAvg) }.map { ($0.minute, $0) }, uniquingKeysWith: { a, _ in a })
        let workoutMinutes = minuteSet(watchWorkouts)
        let minutes = Set(f.keys).union(w.keys).sorted()
        let prefersWatch = params.fusion.prefersWatchInWorkouts
        var out: [FusedHRMinute] = []
        out.reserveCapacity(minutes.count)
        for m in minutes {
            let wm = w[m], fm = f[m]
            let watchValid = (wm?.samples ?? 0) >= params.fusion.watchMinSamples
            if workoutMinutes.contains(m) {
                if prefersWatch, watchValid, let wm {
                    out.append(FusedHRMinute(minute: m, bpm: wm.bpmAvg, source: .appleHealth))
                } else if let fm {
                    out.append(FusedHRMinute(minute: m, bpm: fm.bpmAvg, source: .googleHealth))
                } else if let wm {
                    out.append(FusedHRMinute(minute: m, bpm: wm.bpmAvg, source: .appleHealth))
                }
            } else if let fm {
                out.append(FusedHRMinute(minute: m, bpm: fm.bpmAvg, source: .googleHealth))
            } else if let wm {
                out.append(FusedHRMinute(minute: m, bpm: wm.bpmAvg, source: .appleHealth))
            }
        }
        return out
    }

    static func minuteSet(_ ranges: [TimeRange]) -> Set<Int> {
        var s = Set<Int>()
        for r in ranges {
            var m = r.start.minuteEpoch
            while TimeInterval(m) < r.end.timeIntervalSince1970 {
                s.insert(m)
                m += 60
            }
        }
        return s
    }

    /// Minutos en que ambas fuentes tienen FC válida dentro de un intervalo.
    static func pairedMinutes(fitbit: [Int: Double], watch: [Int: Double], range: TimeRange) -> [(Int, Double, Double)] {
        var out: [(Int, Double, Double)] = []
        var m = range.start.minuteEpoch
        while TimeInterval(m) < range.end.timeIntervalSince1970 {
            if let a = watch[m], let b = fitbit[m], Validity.isValidBPM(a), Validity.isValidBPM(b) { out.append((m, a, b)) }
            m += 60
        }
        return out
    }

    /// «Las fuentes no coinciden»: diferencia > 15 lpm durante ≥ 5 min seguidos.
    public static func sourcesDisagree(fitbit: [Int: Double], watch: [Int: Double], range: TimeRange, params: AlgorithmParams) -> Bool {
        var run = 0
        var last: Int?
        for (m, a, b) in pairedMinutes(fitbit: fitbit, watch: watch, range: range) {
            if abs(a - b) > params.fusion.disagreementBpm {
                run = (last == m - 60) ? run + 1 : 1
                last = m
                if run >= params.fusion.disagreementMin { return true }
            } else {
                run = 0
                last = nil
            }
        }
        return false
    }

    // MARK: ALG-FUS-10 · Concordancia (Bland-Altman)

    public static func agreement(fitbit: [Int: Double], watch: [Int: Double], range: TimeRange) -> HRAgreement? {
        let diffs = pairedMinutes(fitbit: fitbit, watch: watch, range: range).map { $0.1 - $0.2 }
        guard diffs.count >= 5, let bias = Stats.mean(diffs), let sd = Stats.sd(diffs) else { return nil }
        return HRAgreement(bias: (bias * 10).rounded() / 10, loaLow: ((bias - 1.96 * sd) * 10).rounded() / 10,
                           loaHigh: ((bias + 1.96 * sd) * 10).rounded() / 10, minutes: diffs.count)
    }

    /// Resumen de las últimas N carreras con los dos dispositivos.
    public static func agreementSummary(_ activities: [FusedActivity], params: AlgorithmParams) -> HRAgreement? {
        let recent = activities.filter { $0.agreement != nil && $0.kind.isRun }.sorted { $0.start > $1.start }
            .prefix(params.fusion.agreementWindowRuns)
        let all = recent.compactMap(\.agreement)
        guard !all.isEmpty else { return nil }
        let minutes = all.reduce(0) { $0 + $1.minutes }
        let bias = all.reduce(0) { $0 + $1.bias * Double($1.minutes) } / Double(minutes)
        let low = all.reduce(0) { $0 + $1.loaLow * Double($1.minutes) } / Double(minutes)
        let high = all.reduce(0) { $0 + $1.loaHigh * Double($1.minutes) } / Double(minutes)
        return HRAgreement(bias: (bias * 10).rounded() / 10, loaLow: (low * 10).rounded() / 10,
                           loaHigh: (high * 10).rounded() / 10, minutes: minutes)
    }

    // MARK: ALG-FUS-04 · Pasos, distancia y calorías

    public static func dailyTotals(date: LocalDate, fitbitSteps: Int?, fitbitDistanceM: Double?, fitbitCaloriesKcal: Double?,
                                   fitbitMinutes: [Int: ActivityMinute], fitbitHR: [Int: Double],
                                   activities: [FusedActivity], params: AlgorithmParams) -> DailyTotals {
        var steps = fitbitSteps ?? 0
        var distance = fitbitDistanceM ?? 0
        var calories = fitbitCaloriesKcal ?? 0
        var sources: [DataSourceKind] = fitbitSteps != nil || fitbitDistanceM != nil ? [.googleHealth] : []
        var replaced = 0.0
        for a in activities {
            guard let w = a.watchMember else { continue }
            let minutes = minuteSet([a.range])
            let fitbitWorn = minutes.contains { fitbitHR[$0] != nil || (fitbitMinutes[$0]?.steps ?? 0) > 0 }
            if !fitbitWorn {
                steps += w.steps ?? 0
                distance += w.distanceM ?? 0
                calories += w.caloriesKcal ?? 0
                if !sources.contains(.appleHealth) { sources.append(.appleHealth) }
            } else if params.fusion.gpsDistanceOverride, w.hasRoute, let wd = w.distanceM {
                let fitbitInWindow = minutes.reduce(0.0) { $0 + (fitbitMinutes[$1]?.distanceM ?? 0) }
                distance += wd - fitbitInWindow
                replaced += wd
                if !sources.contains(.appleHealth) { sources.append(.appleHealth) }
            }
        }
        return DailyTotals(date: date, steps: steps, distanceM: max(0, distance), caloriesKcal: calories, sources: sources,
                           gpsReplacedM: replaced)
    }

    // MARK: ALG-FUS-06 · VO₂ máx.

    public static func primaryVO2(_ values: [VO2MaxValue], today: LocalDate, params: AlgorithmParams) -> VO2MaxValue? {
        let watch = values.filter { $0.source == .appleHealth }.max { $0.date < $1.date }
        if let watch, today.days(since: watch.date) < params.fusion.vo2maxWatchMaxAgeDays { return watch }
        return values.filter { $0.source == .googleHealth }.max { $0.date < $1.date } ?? watch
    }

    /// Fuente única para la edad fisiológica: la que más valores tenga en la ventana (empate: Watch).
    public static func vo2SourceForPhysioAge(_ values: [VO2MaxValue], today: LocalDate, windowDays: Int) -> DataSourceKind? {
        let recent = values.filter { today.days(since: $0.date) < windowDays && $0.date <= today }
        let w = recent.filter { $0.source == .appleHealth }.count
        let g = recent.filter { $0.source == .googleHealth }.count
        if w == 0 && g == 0 { return nil }
        return w >= g ? .appleHealth : .googleHealth
    }

    // MARK: ALG-FUS-08 · Origen de las muestras de Salud

    /// Solo se aceptan muestras grabadas en un Apple Watch; lo que escriben Google Health (desde el iPhone)
    /// u otras apps del teléfono se ignora.
    public static func acceptsHealthKitSample(bundleIdentifier: String?, productType: String?) -> Bool {
        guard let productType, productType.hasPrefix("Watch") else { return false }
        if let b = bundleIdentifier?.lowercased(), b.hasPrefix("com.google") { return false }
        return true
    }

    /// De la Google Health API se descartan los puntos subidos desde HealthKit.
    public static func acceptsGooglePlatform(_ platform: String?) -> Bool {
        platform != "HEALTH_KIT"
    }
}
