import Foundation
import Testing
@testable import RunKit
@testable import MetricsKit
@testable import Store

/// Ruta a 3,3 m/s por unos puntos de paso (metros al este y al norte de un origen), un punto por segundo.
enum PathRun {
    static let origin = (lat: 40.4, lon: -3.7)
    static let perLat = 111_320.0, perLon = 111_320.0 * cos(40.4 * .pi / 180)

    static func route(_ waypoints: [(Double, Double)], start: Date, speed: Double = 3.3) -> [RoutePoint] {
        var out: [RoutePoint] = []
        var t = 0.0
        for (a, b) in zip(waypoints, waypoints.dropFirst()) {
            let dx = b.0 - a.0, dy = b.1 - a.1
            let len = (dx * dx + dy * dy).squareRoot()
            var d = 0.0
            while d < len {
                let x = a.0 + dx * d / len, y = a.1 + dy * d / len
                out.append(RoutePoint(time: start.addingTimeInterval(t), latitude: origin.lat + y / perLat, longitude: origin.lon + x / perLon,
                                      altitude: 650 + x / 100, speed: speed, horizontalAccuracy: 5))
                d += speed
                t += 1
            }
        }
        return out
    }
}

@Suite struct SegmentTests {
    let start = ISO8601DateFormatter().date(from: "2026-09-20T07:00:00Z")!

    @Test func segmentsAreDirectionalAndCountEveryPass() throws {
        // Ida y vuelta de 2 km hacia el este: el segmento es el tramo de 500 a 1500 m de la ida.
        let outAndBack = PathRun.route([(0, 0), (2000, 0), (0, 0)], start: start)
        let segment = try #require(SegmentMatcher.make(name: "Recta", route: outAndBack, fromM: 500, toM: 1500, runID: "a", id: "s1"))
        #expect(abs(segment.lengthM - 1000) < 10 && segment.elevationGainM > 8 && abs((segment.gradePct ?? 0) - 1) < 0.1)
        let hr = outAndBack.map { HRSample(time: $0.time, bpm: 150, source: .appleHealth) }
        let efforts = SegmentMatcher.efforts(of: segment, route: outAndBack, hr: hr, runID: "a")
        // Solo la ida (la vuelta va en sentido contrario).
        #expect(efforts.count == 1 && abs(efforts[0].seconds - 1000 / 3.3) < 4 && efforts[0].avgHR == 150)
        // Dos idas y vueltas: dos pasadas.
        let twice = PathRun.route([(0, 0), (2000, 0), (0, 0), (2000, 0), (0, 0)], start: start)
        #expect(SegmentMatcher.efforts(of: segment, route: twice, hr: [], runID: "b").count == 2)
        // Una calle paralela a 200 m no cuenta; ni un tramo que se corta antes de la llegada.
        #expect(SegmentMatcher.efforts(of: segment, route: PathRun.route([(0, 200), (2000, 200)], start: start), hr: [], runID: "c").isEmpty)
        #expect(SegmentMatcher.efforts(of: segment, route: PathRun.route([(0, 0), (1200, 0), (1200, 500)], start: start), hr: [], runID: "d").isEmpty)
        // Más rápido, menos tiempo.
        let fast = PathRun.route([(0, 0), (2000, 0)], start: start, speed: 4)
        let e = try #require(SegmentMatcher.efforts(of: segment, route: fast, hr: [], runID: "e").first)
        #expect(e.seconds < efforts[0].seconds && SegmentLibrary.rank(of: e, in: efforts + [e]) == 1)
        #expect(SegmentMatcher.make(name: "Corto", route: outAndBack, fromM: 100, toM: 250, runID: nil) == nil)
    }

    @Test func libraryScansOnlyRunsThatPassNearAndOnlyOnce() throws {
        let db = try AppDatabase.inMemory()
        func store(_ id: String, _ route: [RoutePoint]) -> (RunSummary, FusedActivity) {
            let watch = ActivitySession(source: .appleHealth, sourceRecordID: id, kind: .running, start: route.first!.time,
                                        end: route.last!.time, utcOffsetSeconds: 7200, hasRoute: true)
            try! db.upsertActivities([watch])
            try! db.saveRoute(route, activityID: watch.id)
            let run = FusedActivity(id: watch.id, members: [watch], start: watch.start, end: watch.end, kind: .running, isLeftover: false,
                                    hrSource: nil, sourcesDisagree: false, agreement: nil)
            let summary = RunSummary(id: watch.id, start: watch.start, utcOffsetSeconds: 7200, kind: .running, name: "Carrera", distanceM: 2000,
                                     movingS: 600, elapsedS: 600, bestEfforts: [:], paceCurve: [], powerCurve: [], sources: [.appleHealth],
                                     bounds: Geo.bounds(route), signature: "")
            return (summary, run)
        }
        let a = store("a", PathRun.route([(0, 0), (2000, 0)], start: start))
        let b = store("b", PathRun.route([(0, 0), (2000, 0)], start: start.addingTimeInterval(86_400), speed: 3.6))
        let far = store("far", PathRun.route([(0, 20_000), (2000, 20_000)], start: start.addingTimeInterval(2 * 86_400)))
        let segment = try #require(SegmentMatcher.make(name: "Recta", route: try db.route(activityID: a.1.id), fromM: 300, toM: 1300,
                                                       runID: a.0.id, id: "s1"))
        try db.saveSegment(segment, id: segment.id)
        let runs = Dictionary(uniqueKeysWithValues: [a, b, far].map { ($0.0.id, $0.1) })
        #expect(try SegmentLibrary.scan(db: db, summaries: [a.0, b.0, far.0], runs: runs) == 2)
        let efforts = try SegmentLibrary.efforts(segmentID: "s1", db: db)
        #expect(efforts.count == 2 && efforts[0].runID == b.0.id)   // la más rápida primero
        #expect(try SegmentLibrary.efforts(runID: a.0.id, db: db).count == 1)
        // Ya revisadas: no se vuelven a leer.
        #expect(try db.scannedActivityIDs(segmentID: "s1").count == 3)
        #expect(try SegmentLibrary.scan(db: db, summaries: [a.0, b.0, far.0], runs: runs) == 0)
        try db.deleteSegment(id: "s1")
        #expect(try SegmentLibrary.segments(db: db).isEmpty && SegmentLibrary.efforts(segmentID: "s1", db: db).isEmpty)
    }
}
