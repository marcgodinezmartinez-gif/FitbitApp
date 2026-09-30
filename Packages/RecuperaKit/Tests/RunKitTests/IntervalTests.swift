import Foundation
import Testing
@testable import RunKit
@testable import MetricsKit
import Store

/// Carrera a tramos de velocidad constante (segundos, m/s) en línea recta, con FC que sigue al ritmo.
enum BlockRun {
    static let start = ISO8601DateFormatter().date(from: "2026-09-27T07:00:00Z")!

    static func input(_ blocks: [(Double, Double)], id: String = "blocks") -> RunInput {
        let metersPerDegree = 111_320 * cos(40.0 * .pi / 180)
        var route: [RoutePoint] = []
        var hr: [HRSample] = []
        var meters = 0.0, t = 0.0
        for (seconds, speed) in blocks {
            for _ in 0..<Int(seconds) {
                route.append(RoutePoint(time: start.addingTimeInterval(t), latitude: 40, longitude: -3.7 + meters / metersPerDegree,
                                        altitude: 600, speed: speed, horizontalAccuracy: 5))
                if Int(t) % 5 == 0 { hr.append(HRSample(time: start.addingTimeInterval(t), bpm: 100 + 15 * speed, source: .appleHealth)) }
                meters += speed
                t += 1
            }
        }
        let end = start.addingTimeInterval(t)
        let watch = ActivitySession(source: .appleHealth, sourceRecordID: id, kind: .running, start: start, end: end, utcOffsetSeconds: 7200,
                                    avgHR: 150, distanceM: meters, hasRoute: true)
        let activity = FusedActivity(id: watch.id, members: [watch], start: start, end: end, kind: .running, isLeftover: false,
                                     hrSource: .appleHealth, sourcesDisagree: false, agreement: nil)
        return RunInput(activity: activity, route: route, samples: [], hrWatch: hr, hrFitbit: [], watchDetail: nil, fitbitDetail: nil,
                        zones: StrainCalculator.zones(hrMax: 190, restingRef: 55), sex: .male, weightKg: 70)
    }
}

@Suite struct IntervalTests {
    @Test func findsSixThreeMinuteRepsWithTheirRecoveries() throws {
        // 10 min suaves, 6 × (3 min a 4:00 + 2 min a 6:30) y 8 min de vuelta a la calma.
        var blocks: [(Double, Double)] = [(600, 1000.0 / 360)]
        for _ in 0..<6 { blocks += [(180, 1000.0 / 240), (120, 1000.0 / 390)] }
        blocks.append((480, 1000.0 / 375))
        let r = RunAnalyzer.analyze(BlockRun.input(blocks))
        let session = try #require(r.intervals)
        #expect(session.reps.count == 6)
        #expect(session.label == "6 × 3 min")
        for rep in session.reps {
            #expect(abs(rep.pace - 240) < 8)
            #expect(abs(rep.seconds - 180) < 12)
        }
        #expect(session.reps.dropLast().allSatisfy { abs(($0.recoverySeconds ?? 0) - 120) < 15 })
        #expect(abs(session.avgRepPace - 240) < 6 && abs(session.fadePct ?? 99) < 3)
        #expect((session.paceSpreadPct ?? 99) < 3)
        // Y en el resumen que usa la lista de carreras.
        let summary = RunLibrary.summary(BlockRun.input(blocks).activity, analysis: r, route: BlockRun.input(blocks).route)
        #expect(summary.intervalLabel == session.label && summary.bounds?.count == 4)
    }

    @Test func roundDistancesAreNamedByDistance() throws {
        // 5 × 1 km a 3:45 con 90 s de trote.
        var blocks: [(Double, Double)] = [(720, 1000.0 / 350)]
        for _ in 0..<5 { blocks += [(225, 1000.0 / 225), (90, 1000.0 / 420)] }
        blocks.append((420, 1000.0 / 360))
        let session = try #require(RunAnalyzer.analyze(BlockRun.input(blocks)).intervals)
        #expect(session.reps.count == 5 && session.label == "5 × 1 km")
    }

    @Test func warmupIsNotARepWhenRecoveriesAreSlower() throws {
        // 12 min a 5:00, 5 × (6 min a 4:24 + 6 min a 6:06) y 10 min a 5:00: tres ritmos distintos.
        var blocks: [(Double, Double)] = [(720, 1000.0 / 300)]
        for _ in 0..<5 { blocks += [(360, 1000.0 / 264), (360, 1000.0 / 366)] }
        blocks.append((600, 1000.0 / 300))
        let session = try #require(RunAnalyzer.analyze(BlockRun.input(blocks)).intervals)
        #expect(session.reps.count == 5 && session.label == "5 × 6 min")
        #expect(session.reps.allSatisfy { abs($0.pace - 264) < 6 })
    }

    @Test func pausedStandingRecoveriesStillSeparateTheReps() throws {
        // 10 min suaves y 6 × 400 m a 3:20 con 90 s parado y el reloj en pausa; luego 10 min suaves.
        var blocks: [(Double, Double)] = [(600, 1000.0 / 360)]
        for _ in 0..<6 { blocks += [(80, 5), (90, 0)] }
        blocks.append((600, 1000.0 / 360))
        var input = BlockRun.input(blocks)
        var detail = ActivityDetail(activityID: input.activity.id)
        detail.events = (0..<6).map { k in
            let t = 600 + Double(k) * 170 + 80
            return WorkoutEvent(kind: .pause, start: BlockRun.start.addingTimeInterval(t), end: BlockRun.start.addingTimeInterval(t + 90))
        }
        input.watchDetail = detail
        let session = try #require(RunAnalyzer.analyze(input).intervals)
        #expect(session.reps.count == 6 && session.label == "6 × 400 m")
        #expect(session.reps.dropLast().allSatisfy { abs(($0.recoverySeconds ?? 0) - 90) < 15 })
    }

    @Test func labelsPreferTheUsualDistancesAndTimes() {
        func reps(_ pairs: [(Double, Double)]) -> [DetectedRep] {
            pairs.enumerated().map { DetectedRep(index: $0.offset + 1, startS: 0, endS: $0.element.1, distanceM: $0.element.0, seconds: $0.element.1) }
        }
        // 3 min que dan unos 650 m: manda el tiempo.
        #expect(IntervalDetector.label(reps([(652, 177), (650, 180), (654, 178)])) == "3 × 3 min")
        // Vueltas a la pista: 400 m, aunque el tiempo también sea redondo.
        #expect(IntervalDetector.label(reps([(401, 90), (398, 88), (402, 91), (399, 90)])) == "4 × 400 m")
        #expect(IntervalDetector.label(reps([(1_490, 330), (1_510, 335), (1_505, 332)])) == "3 × 1,5 km")
        #expect(IntervalDetector.label(reps([(560, 150), (540, 148), (575, 151)])) == "3 × 2 min 30 s")
        #expect(IntervalDetector.label(reps([(700, 150), (300, 60), (900, 240)])) == "3 cambios de ritmo")
    }

    @Test func steadyAndProgressiveRunsAreNotIntervals() {
        #expect(RunAnalyzer.analyze(SyntheticRun.input()).intervals == nil)
        let progressive = BlockRun.input([(900, 1000.0 / 360), (900, 1000.0 / 330), (900, 1000.0 / 300)])
        #expect(RunAnalyzer.analyze(progressive).intervals == nil)
        // Un rodaje con tres paradas en semáforos tampoco.
        let stops = BlockRun.input([(600, 3), (40, 0.2), (600, 3), (40, 0.2), (600, 3), (40, 0.2), (600, 3)])
        #expect(RunAnalyzer.analyze(stops).intervals == nil)
    }
}
