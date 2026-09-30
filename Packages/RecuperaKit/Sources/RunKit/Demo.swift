import Foundation
import MetricsKit
import Store

/// Carreras de ejemplo para el modo demostración y las capturas: ruta por el Retiro, repechos, FC con deriva, cadencia,
/// potencia y dinámica de carrera. Deterministas: la misma carrera da siempre los mismos datos.
public enum RunDemo {
    /// Generador pseudoaleatorio reproducible (SplitMix64).
    struct Random {
        var state: UInt64

        init(seed: String) {
            var h: UInt64 = 0xcbf2_9ce4_8422_2325
            for b in seed.utf8 { h = (h ^ UInt64(b)) &* 0x0000_0100_0000_01b3 }
            state = h
        }

        mutating func next() -> Double {
            state &+= 0x9e37_79b9_7f4a_7c15
            var z = state
            z = (z ^ (z >> 30)) &* 0xbf58_476d_1ce4_e5b9
            z = (z ^ (z >> 27)) &* 0x94d0_49bb_1331_11eb
            z ^= z >> 31
            return Double(z >> 11) / Double(1 << 53)
        }

        mutating func range(_ lo: Double, _ hi: Double) -> Double { lo + (hi - lo) * next() }
    }

    /// El circuito de ejemplo: una elipse algo ondulada de 4,2 km. La posición se busca por distancia a lo largo de la curva
    /// para que el GPS vaya a la misma velocidad que el corredor (por ángulo, iría más deprisa en los lados largos).
    struct Circuit: Sendable {
        static let loop = 4_200.0
        static let shape = Circuit()
        let angles: [Double]
        let lengths: [Double]
        let scale: Double

        init() {
            let n = 2_000
            var angles = [0.0], lengths = [0.0]
            var previous = Self.curve(0)
            for i in 1...n {
                let angle = 2 * Double.pi * Double(i) / Double(n)
                let p = Self.curve(angle)
                lengths.append(lengths[i - 1] + hypot(p.north - previous.north, p.east - previous.east))
                angles.append(angle)
                previous = p
            }
            self.angles = angles
            self.lengths = lengths
            scale = Self.loop / lengths[n]
        }

        static func curve(_ angle: Double) -> (north: Double, east: Double) {
            let wobble = 1 + 0.08 * sin(angle * 3)
            return (620 * wobble * sin(angle), 810 * wobble * cos(angle))
        }

        /// Metros al norte y al este del centro tras recorrer `meters`.
        func position(_ meters: Double) -> (north: Double, east: Double) {
            let s = meters.truncatingRemainder(dividingBy: Self.loop) / scale
            var lo = 0, hi = lengths.count - 1
            while hi - lo > 1 {
                let mid = (lo + hi) / 2
                if lengths[mid] <= s { lo = mid } else { hi = mid }
            }
            let f = (s - lengths[lo]) / max(1e-9, lengths[hi] - lengths[lo])
            let p = Self.curve(angles[lo] + f * (angles[hi] - angles[lo]))
            return (p.north * scale, p.east * scale)
        }
    }

    public static func input(for run: FusedActivity, zones: HRZones, profile: UserProfile) -> RunInput {
        var rng = Random(seed: run.id)
        let start = run.start
        let duration = max(600, run.end.timeIntervalSince(start))
        let total = run.distanceM ?? duration * 3
        let baseSpeed = total / duration
        let intervals = rng.next() < 0.25 && duration > 1800
        // Series: tras 15 min de calentamiento, de 3 a 6 veces 3 min rápidos y 2 min de trote.
        let reps = intervals ? max(3, min(6, Int((duration - 1_500) / 300))) : 0
        let hasPause = duration > 2400
        let pauseAt = intervals ? max(duration * 0.55, 900 + Double(reps) * 300 + 60) : duration * 0.55
        let pause = (pauseAt, pauseAt + 45)
        let center = (lat: 40.4153, lon: -3.6845)
        let perLat = 111_320.0, perLon = 111_320.0 * cos(center.lat * .pi / 180)
        let loop = Circuit.loop
        let hrBase = run.primary.avgHR ?? (zones.restingRef + 0.62 * (zones.hrMax - zones.restingRef))
        let hrMax = zones.hrMax

        var route: [RoutePoint] = []
        var samples: [MetricSample] = []
        var hrWatch: [HRSample] = []
        var hrFitbit: [HRSample] = []
        var meters = 0.0
        var hr = hrBase - 12
        var t = 0.0
        let step = 2.0
        while t <= duration {
            let inPause = hasPause && t >= pause.0 && t < pause.1
            var factor = 1 + 0.03 * sin(t / 97) + rng.range(-0.015, 0.015)
            let into = t - 900
            if into >= 0 && into < Double(reps) * 300 { factor *= into.truncatingRemainder(dividingBy: 300) < 180 ? 1.22 : 0.8 }
            let angle = 2 * Double.pi * meters / loop
            let altitude = 655 + 11 * sin(angle) + 4 * sin(3 * angle + 1)
            let slope = (11 * cos(angle) + 12 * cos(3 * angle + 1)) * 2 * .pi / loop   // m/m
            // Cuesta arriba más despacio y cuesta abajo algo más rápido, al mismo esfuerzo.
            let hill = RunPhysiology.gradeFactor(grade: slope)
            let speed = inPause ? 0 : max(1.2, baseSpeed * factor / hill)
            if !inPause {
                meters += speed * step
                let p = Circuit.shape.position(meters)
                route.append(RoutePoint(time: start.addingTimeInterval(t),
                                        latitude: center.lat + p.north / perLat, longitude: center.lon + p.east / perLon,
                                        altitude: altitude + rng.range(-0.6, 0.6), speed: speed, horizontalAccuracy: rng.range(3, 8)))
            }
            // FC que sigue al esfuerzo con retraso y sube despacio (deriva).
            let effort = inPause ? -25.0 : 14 * (speed * hill / baseSpeed - 1) * 4
            let target = min(hrMax - 4, hrBase + effort + 6 * t / duration)
            hr += (target - hr) * 0.08 + rng.range(-0.8, 0.8)
            if Int(t) % 5 == 0 { hrWatch.append(HRSample(time: start.addingTimeInterval(t), bpm: hr.rounded(), source: .appleHealth)) }
            if run.fitbitMember != nil {
                hrFitbit.append(HRSample(time: start.addingTimeInterval(t), bpm: (hr - 1 + rng.range(-2, 2)).rounded(), source: .googleHealth))
            }
            if !inPause, Int(t) % 10 == 0 {
                let time = start.addingTimeInterval(t)
                let cadence = 164 + 9 * (speed / baseSpeed) + rng.range(-1.5, 1.5)
                samples += [
                    MetricSample(metric: "cadence_spm", time: time, value: cadence),
                    MetricSample(metric: "power_w", time: time, value: 4.1 * (profile.weightKg ?? 70) * speed / 3.3 * (1 + 3 * slope) + rng.range(-6, 6)),
                    MetricSample(metric: "stride_m", time: time, value: speed * 60 / cadence),
                    MetricSample(metric: "vertical_osc_cm", time: time, value: 8.2 - 0.3 * (speed - 3) + rng.range(-0.2, 0.2)),
                    MetricSample(metric: "ground_contact_ms", time: time, value: 258 - 14 * (speed - 3) + rng.range(-4, 4)),
                    MetricSample(metric: "speed_mps", time: time, value: speed),
                ]
            }
            t += step
        }
        var watchDetail = run.watchMember.map { ActivityDetail(activityID: $0.id) }
        if hasPause {
            watchDetail?.events = [WorkoutEvent(kind: .pause, start: start.addingTimeInterval(pause.0), end: start.addingTimeInterval(pause.1))]
        }
        watchDetail?.weather = WeatherInfo(temperatureC: (rng.range(9, 24)).rounded(), humidityPct: (rng.range(40, 80)).rounded(),
                                           condition: ["Despejado", "Nubes y claros", "Nublado"][Int(rng.range(0, 2.99))])
        let fitbitDetail = run.fitbitMember.map { f in
            ActivityDetail(activityID: f.id, activeZoneMinutes: (duration / 60 * 0.8).rounded(),
                           mobility: RunningDynamics(avgStrideM: 1.08, avgVerticalOscillationCm: 8.1, avgGroundContactMs: 252, avgCadenceSpm: 170),
                           verticalRatioPct: 7.4, vo2max: (46 + rng.range(-1, 1) * 1.5).rounded())
        }
        return RunInput(activity: run, route: route, samples: samples, hrWatch: run.watchMember == nil ? [] : hrWatch, hrFitbit: hrFitbit,
                        watchDetail: watchDetail, fitbitDetail: fitbitDetail, zones: zones, sex: profile.sex, weightKg: profile.weightKg)
    }

    /// Un segmento de ejemplo (la subida más larga del circuito: 800 m al 2,5 %) con las pasadas de todas las carreras de ejemplo.
    public static func segments(output: MetricsOutput, profile: UserProfile) -> ([Segment], [SegmentEffort]) {
        let runs = RunLibrary.runs(in: output).filter { $0.watchMember != nil }
        let climb = 3_610.0
        guard let last = runs.last(where: { ($0.distanceM ?? 0) > climb + 1_000 }) else { return ([], []) }
        let lastInput = input(for: last, zones: RunLibrary.zones(for: last, output: output), profile: profile)
        guard let segment = SegmentMatcher.make(name: "Subida del Retiro", route: lastInput.route, fromM: climb, toM: climb + 800,
                                                runID: last.id, id: "demo-segment", now: last.start) else { return ([], []) }
        var efforts: [SegmentEffort] = []
        for run in runs {
            let i = run.id == last.id ? lastInput : input(for: run, zones: RunLibrary.zones(for: run, output: output), profile: profile)
            efforts += SegmentMatcher.efforts(of: segment, route: i.route, hr: i.hrWatch, runID: run.id)
        }
        return ([segment], efforts)
    }

    /// Resúmenes de todas las carreras de demostración.
    public static func summaries(output: MetricsOutput, profile: UserProfile) -> [RunSummary] {
        RunLibrary.runs(in: output).map { run in
            let input = input(for: run, zones: RunLibrary.zones(for: run, output: output), profile: profile)
            return RunLibrary.summary(run, analysis: RunAnalyzer.analyze(input), route: input.route)
        }.sorted { $0.start < $1.start }
    }
}
