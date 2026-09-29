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

    public static func input(for run: FusedActivity, zones: HRZones, profile: UserProfile) -> RunInput {
        var rng = Random(seed: run.id)
        let start = run.start
        let duration = max(600, run.end.timeIntervalSince(start))
        let total = run.distanceM ?? duration * 3
        let baseSpeed = total / duration
        let intervals = rng.next() < 0.25 && duration > 1800
        let hasPause = duration > 2400
        let pause = (duration * 0.55, duration * 0.55 + 45)
        let center = (lat: 40.4153, lon: -3.6845)
        let perLat = 111_320.0, perLon = 111_320.0 * cos(center.lat * .pi / 180)
        let loop = 4_200.0
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
            // Series: 4 min rápidos y 2 min suaves en la parte central.
            var factor = 1 + 0.03 * sin(t / 97) + rng.range(-0.015, 0.015)
            if intervals, t > duration * 0.2, t < duration * 0.8 { factor *= (Int(t / 360) % 2 == 0) ? 1.14 : 0.82 }
            let angle = 2 * Double.pi * meters / loop
            let altitude = 655 + 11 * sin(angle) + 4 * sin(3 * angle + 1)
            let slope = (11 * cos(angle) + 12 * cos(3 * angle + 1)) * 2 * .pi / loop   // m/m
            let speed = inPause ? 0 : max(1.2, baseSpeed * factor * (1 - 2.2 * slope))
            if !inPause {
                meters += speed * step
                let wobble = 1 + 0.08 * sin(angle * 3)
                route.append(RoutePoint(time: start.addingTimeInterval(t),
                                        latitude: center.lat + 620 / perLat * wobble * sin(angle),
                                        longitude: center.lon + 810 / perLon * wobble * cos(angle),
                                        altitude: altitude + rng.range(-0.6, 0.6), speed: speed, horizontalAccuracy: rng.range(3, 8)))
            }
            // FC que sigue al esfuerzo con retraso y sube despacio (deriva).
            let effort = inPause ? -25.0 : 14 * (speed / baseSpeed - 1) * 4 + 60 * slope
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

    /// Resúmenes de todas las carreras de demostración.
    public static func summaries(output: MetricsOutput, profile: UserProfile) -> [RunSummary] {
        RunLibrary.runs(in: output).map { run in
            let input = input(for: run, zones: RunLibrary.zones(for: run, output: output), profile: profile)
            return RunLibrary.summary(run, analysis: RunAnalyzer.analyze(input), route: input.route)
        }.sorted { $0.start < $1.start }
    }
}
