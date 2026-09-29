import Foundation

/// Datos sintéticos realistas (dataset `synthetic/basic` y `synthetic/watch-runs` del doc. 13 §3).
/// Sirven para los tests y para el modo demostración de la app antes de conectar las cuentas.
public enum SyntheticData {
    public static func generate(days: Int = 60, endingAt now: Date, utcOffsetSeconds: Int = 7200, seed: UInt64 = 7,
                                withWatch: Bool = true) -> MetricsInput {
        var rng = SeededGenerator(seed: seed)
        var watchRNG = SeededGenerator(seed: seed ^ 0xA5A5_5A5A)   // aparte, para que la Fitbit sea igual con y sin Watch
        func noise(_ amp: Double) -> Double { Double.random(in: -amp...amp, using: &rng) }
        func watchNoise(_ amp: Double) -> Double { Double.random(in: -amp...amp, using: &watchRNG) }

        let profile = UserProfile(birthDate: LocalDate(year: 1990, month: 5, day: 12), sex: .male, heightCm: 178, weightKg: 74,
                                  waistCm: 83,
                                  activityQuestionnaire: ActivityQuestionnaire(frequency: .twoToThreeWeekly, intensity: .breathless,
                                                                               duration: .from30to60),
                                  sports: ["Carrera", "Fuerza"], usualWakeMinutes: 7 * 60)
        let today = LocalDate(now, utcOffsetSeconds: utcOffsetSeconds)
        var sleeps: [SleepSession] = []
        var vitals: [NightlyVitals] = []
        var hrF: [HRMinute] = []
        var hrW: [HRMinute] = []
        var mins: [ActivityMinute] = []
        var acts: [ActivitySession] = []
        var totals: [LocalDate: DailySourceTotals] = [:]
        var vo2: [VO2MaxValue] = []
        var journal: [JournalAnswer] = []

        for k in stride(from: days, through: 0, by: -1) {
            let day = today.adding(days: -k)
            let midnight = day.startDate(utcOffsetSeconds: utcOffsetSeconds)
            let drank = k % 7 == 5
            // Sueño: de 23:15 ± 30 min a 07:00 ± 20 min.
            let bed = midnight.addingTimeInterval(-45 * 60 + noise(1800))
            let wake = midnight.addingTimeInterval(7 * 3600 + noise(1200))
            if wake <= now {
                var stages: [SleepStageSegment] = []
                var t = bed
                var i = 0
                let cycle: [(SleepStageKind, Double)] = [(.light, 25), (.deep, 20), (.light, 20), (.rem, 20), (.wake, 3)]
                while t < wake {
                    let (st, m) = cycle[i % cycle.count]
                    let end = min(wake, t.addingTimeInterval((m + noise(5)) * 60))
                    stages.append(SleepStageSegment(start: t, end: end, stage: st))
                    t = end
                    i += 1
                }
                sleeps.append(SleepSession(id: "s\(day.isoString)", start: bed, end: wake, utcOffsetSeconds: utcOffsetSeconds,
                                           isMainFromSource: true, stages: stages))
                let rmssd = 52 + noise(6) - (drank ? 8 : 0)
                vitals.append(NightlyVitals(date: day, restingHR: 52 + noise(1.5) + (drank ? 3 : 0), hrvRmssdAvg: rmssd,
                                            hrvRmssdDeep: rmssd + 6, respiratoryRate: 14 + noise(0.4),
                                            skinTempC: 34.2 + noise(0.15), spo2Avg: 96 + noise(0.7)))
                var m = bed.minuteEpoch
                while TimeInterval(m) < wake.timeIntervalSince1970 {
                    hrF.append(HRMinute(minute: m, bpmAvg: 52 + noise(4), source: .googleHealth))
                    m += 60
                }
            }
            // Día: FC de vigilia, pasos, una carrera en días alternos a las 18:30 y fuerza cada 4 días a las 19:00.
            let dayStart = midnight.addingTimeInterval(7 * 3600 + 900)
            let dayEnd = min(now, midnight.addingTimeInterval(22 * 3600 + 3000))
            let runs = k % 2 == 0
            let runStart = midnight.addingTimeInterval(18.5 * 3600)
            let runEnd = runStart.addingTimeInterval((40 + noise(10)) * 60)
            let gym = k % 4 == 1
            let gymStart = midnight.addingTimeInterval(19 * 3600)
            let gymEnd = gymStart.addingTimeInterval(50 * 60)
            var steps = 0
            var distance = 0.0
            var m = dayStart.minuteEpoch
            var walking = false
            while TimeInterval(m) < dayEnd.timeIntervalSince1970 {
                let date = Date(timeIntervalSince1970: TimeInterval(m))
                let inRun = runs && date >= runStart && date < runEnd
                let inGym = gym && date >= gymStart && date < gymEnd
                // Paseos en tramos (≈ 7 min de media) y ratos sentado entre ellos, como un día real.
                let roll = Int.random(in: 0..<100, using: &rng)
                walking = !inRun && !inGym && (walking ? roll < 85 : roll < 3)
                let bpm = inRun ? 152 + noise(8) : (inGym ? 112 + noise(12) : (walking ? 88 + noise(8) : 68 + noise(6)))
                hrF.append(HRMinute(minute: m, bpmAvg: bpm, source: .googleHealth))
                let s = inRun ? 165 : (walking ? 90 : 0)
                let d = Double(s) * (inRun ? 1.05 : 0.72)
                steps += s
                distance += d
                mins.append(ActivityMinute(minute: m, steps: s, distanceM: d, source: .googleHealth))
                if inRun || inGym, withWatch {
                    hrW.append(HRMinute(minute: m, bpmAvg: bpm + 2 + watchNoise(2), samples: 12, source: .appleHealth))
                }
                m += 60
            }
            if runs && runEnd <= now {
                let km = runEnd.timeIntervalSince(runStart) / 60 / 5.2
                acts.append(ActivitySession(source: .googleHealth, sourceRecordID: "ex-\(day.isoString)", kind: .running,
                                            start: runStart.addingTimeInterval(120), end: runEnd.addingTimeInterval(-60),
                                            utcOffsetSeconds: utcOffsetSeconds, avgHR: 152, caloriesKcal: km * 70))
                if withWatch {
                    acts.append(ActivitySession(source: .appleHealth, sourceRecordID: "hk-\(day.isoString)", kind: .running,
                                                start: runStart, end: runEnd, utcOffsetSeconds: utcOffsetSeconds, avgHR: 154,
                                                maxHR: 172, caloriesKcal: km * 68, distanceM: km * 1000, steps: 6200,
                                                elevationGainM: 45, hasRoute: true,
                                                dynamics: RunningDynamics(avgPowerW: 265, avgSpeedMps: 1000 / (5.2 * 60), avgStrideM: 1.12,
                                                                          avgVerticalOscillationCm: 8.6, avgGroundContactMs: 245, avgCadenceSpm: 168),
                                                hrRecovery1Min: 28 + watchNoise(4), effortScore: 6))
                    if k % 6 == 0 { vo2.append(VO2MaxValue(date: day, value: 49 + watchNoise(1), source: .appleHealth)) }
                }
            }
            if gym && gymEnd <= now && withWatch {
                acts.append(ActivitySession(source: .appleHealth, sourceRecordID: "hk-gym-\(day.isoString)", kind: .strength,
                                            name: "Fuerza", start: gymStart, end: gymEnd, utcOffsetSeconds: utcOffsetSeconds,
                                            avgHR: 114, maxHR: 139, caloriesKcal: 250, effortScore: 7, rpe: 7))
            }
            if !(k == 0 && dayEnd < midnight.addingTimeInterval(20 * 3600)) {
                totals[day] = DailySourceTotals(steps: steps, distanceM: distance, caloriesKcal: 2300 + Double(steps) * 0.04)
            }
            if k > 0 {
                journal.append(JournalAnswer(date: day, questionKey: "alcohol", yes: drank))
                journal.append(JournalAnswer(date: day, questionKey: "late_caffeine", yes: k % 4 == 0))
            }
        }
        return MetricsInput(profile: profile, now: now, utcOffsetSeconds: utcOffsetSeconds, sleepSessions: sleeps, vitals: vitals,
                            hrFitbit: hrF, hrWatch: hrW, fitbitMinutes: mins, activities: acts, dailyFitbitTotals: totals,
                            vo2max: vo2, journal: journal)
    }
}
