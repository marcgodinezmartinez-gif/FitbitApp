import Foundation
import Testing
@testable import RunKit
@testable import MetricsKit

@Suite struct RaceTests {
    let date = ISO8601DateFormatter().date(from: "2026-12-06T08:30:00Z")!

    @Test func dewPointAndHeat() {
        #expect(abs(RacePredictor.dewPoint(temperatureC: 20, humidityPct: 50) - 9.3) < 0.2)
        #expect(abs(RacePredictor.dewPoint(temperatureC: 30, humidityPct: 100) - 30) < 0.1)
        // 25 °C y rocío de 18 °C: 141,4 °F → un 3,2 % en una carrera larga, la mitad en una de 15 min.
        #expect(abs(RacePredictor.heatSlowdown(temperatureC: 25, dewPointC: 18, durationS: 3 * 3600) - 0.0321) < 0.001)
        #expect(abs(RacePredictor.heatSlowdown(temperatureC: 25, dewPointC: 18, durationS: 15 * 60) - 0.0161) < 0.001)
        #expect(RacePredictor.heatSlowdown(temperatureC: 10, dewPointC: 5, durationS: 3600) == 0)
    }

    @Test func hillsAndHeatSlowTheFlatPrediction() throws {
        let flatRace = GoalRace(name: "10K", date: date, distanceM: 10_000)
        let flat = try #require(RacePredictor.predict(race: flatRace, vdot: 50))
        #expect(flat.hillSeconds == 0 && flat.heatSeconds == 0 && abs(flat.totalSeconds - flat.flatSeconds) < 0.001)
        #expect(abs(flat.totalSeconds - (41 * 60 + 21)) < 30)
        // 150 m arriba y 150 abajo: más lento que en llano (lo que cuesta subir no se recupera del todo al bajar).
        var hilly = flatRace
        hilly.elevationGainM = 150
        hilly.elevationLossM = 150
        let h = try #require(RacePredictor.predict(race: hilly, vdot: 50))
        #expect(h.hillSeconds > 20 && h.hillSeconds < 180 && h.equivalentFlatM > 10_000)
        // Con calor y humedad, más aún.
        hilly.temperatureC = 27
        hilly.humidityPct = 70
        let hot = try #require(RacePredictor.predict(race: hilly, vdot: 50))
        #expect(hot.heatSeconds > 20 && hot.totalSeconds > h.totalSeconds && !hot.tooHot)
        #expect(hot.dewPointC.map { abs($0 - 21.1) < 0.3 } == true)
    }

    @Test func gpxProfileGivesEvenEffortSplits() throws {
        // 5 km hacia el este: 2 km llanos, 1 km subiendo 40 m y 2 km llanos.
        let perDegree = 111_320 * cos(40.0 * .pi / 180)
        var points = ""
        for k in 0...100 {
            let meters = Double(k) * 50
            let ele = meters < 2000 ? 600 : (meters < 3000 ? 600 + (meters - 2000) * 0.04 : 640)
            points += "<trkpt lat=\"40.0\" lon=\"\(-3.7 + meters / perDegree)\"><ele>\(ele)</ele></trkpt>\n"
        }
        let gpx = "<?xml version=\"1.0\"?><gpx version=\"1.1\"><trk><name>Test</name><trkseg>\n\(points)</trkseg></trk></gpx>"
        let course = try #require(GPXReader.course(from: Data(gpx.utf8)))
        #expect(abs(course.distanceM - 5000) < 15 && abs(course.gainM - 40) < 3 && course.lossM < 3)
        #expect(course.profile.count >= 100 && abs((course.start?.latitude ?? 0) - 40) < 1e-6)
        let race = GoalRace(name: "5K", date: date, distanceM: 5000, elevationGainM: course.gainM, elevationLossM: course.lossM,
                            profile: course.profile)
        let p = try #require(RacePredictor.predict(race: race, vdot: 50))
        #expect(p.splits.count == 5)
        #expect(abs((p.splits.last?.cumulativeSeconds ?? 0) - p.totalSeconds) < 1)
        // El km de la subida, más lento; los llanos, iguales.
        #expect(p.splits[2].paceSeconds > p.splits[0].paceSeconds + 10 && abs(p.splits[0].paceSeconds - p.splits[4].paceSeconds) < 1)
        #expect(abs(p.splits[2].gradePct - 4) < 0.5)
    }

    @Test func openMeteoParsing() throws {
        let places = OpenMeteo.places(from: Data(#"{"results":[{"name":"Valencia","latitude":39.47,"longitude":-0.377,"country":"España","admin1":"Comunidad Valenciana"}]}"#.utf8))
        #expect(places.count == 1 && places[0].detail == "Comunidad Valenciana, España")
        let url = try #require(OpenMeteo.forecastURL(places[0], day: LocalDate(year: 2026, month: 12, day: 6)))
        #expect(url.absoluteString.contains("start_date=2026-12-06") && url.absoluteString.contains("relative_humidity_2m"))
        let json = #"{"hourly":{"time":["2026-12-06T08:00","2026-12-06T09:00"],"temperature_2m":[11.5,12.8],"relative_humidity_2m":[78,71]}}"#
        let c = try #require(OpenMeteo.conditions(from: Data(json.utf8), hour: 9))
        #expect(c.temperatureC == 12.8 && c.humidityPct == 71)
        #expect(OpenMeteo.conditions(from: Data(json.utf8), hour: 20) == nil)
        #expect(OpenMeteo.average([c, RaceConditions(temperatureC: 10.8, humidityPct: 81)]) == RaceConditions(temperatureC: 11.8, humidityPct: 76))
        #expect(OpenMeteo.searchURL("Valencia")?.absoluteString.contains("language=es") == true)
    }
}
