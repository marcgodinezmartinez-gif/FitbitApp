import Foundation
import Testing
@testable import FaceKit

@Suite struct FaceDesignTests {
    @Test func everyTemplateStartsValid() {
        for template in FaceTemplate.allCases {
            let d = template.defaultDesign(id: "x", now: Date(timeIntervalSince1970: 0))
            #expect(d.normalized() == d, "\(template)")
            #expect(Set(template.slots.map(\.id)).count == template.slots.count)
            #expect(template.slots.allSatisfy { d.complication($0.id).fits($0.kind) })
            #expect(template.bezels.contains(d.bezel))
        }
        #expect(FaceLibrary.starter().designs.count == FaceTemplate.allCases.count)
    }

    @Test func normalizationPutsBackWhatDoesNotFit() {
        var d = FaceTemplate.ultraModular.defaultDesign(id: "u")
        d.slots["topRight"] = .summary          // un rectangular en un hueco redondo
        d.slots["ghost"] = .steps               // un hueco que no existe
        d.bezel = .compass                      // la brújula es del Explorador
        d.name = "  "
        let n = d.normalized()
        #expect(n.complication("topRight") == .date && n.slots["ghost"] == nil && n.bezel == .seconds && n.name == "Ultra modular")
        #expect(FaceComplication.options(for: .rectangular).contains(.summary))
        #expect(!FaceComplication.options(for: .circular).contains(.workout))
    }

    @Test func whatEachDesignNeeds() {
        let wayfinder = FaceTemplate.wayfinder.defaultDesign(id: "w")
        #expect(wayfinder.needsLocation && wayfinder.needsHealth)       // brújula y el tiempo; pulso y pasos
        var analog = FaceTemplate.analog.defaultDesign(id: "a")
        analog.slots = ["top": .date, "bottom": .recovery]
        #expect(!analog.needsLocation && !analog.needsHealth)
        #expect(analog.complications == [.date, .recovery])
    }

    @Test func decodingToleratesNewerOrMissingValues() throws {
        let json = """
        {"designs": [
          {"id": "a", "template": "ultraModular", "name": "Mía", "slots": {"center": "bloodOxygen", "bottomLeft": "steps"},
           "bezel": "tides", "font": "rounded"},
          {"id": "b", "template": "hologram"},
          {"id": "c", "template": "digital"}
        ]}
        """
        let lib = try JSONDecoder().decode(FaceLibrary.self, from: Data(json.utf8))
        #expect(lib.designs.map(\.id) == ["a", "c"])
        let a = try #require(lib.design("a"))
        #expect(a.name == "Mía" && a.font == .rounded && a.bezel == .seconds)
        #expect(a.complication("center") == .summary && a.complication("bottomLeft") == .steps)
        #expect(a.accent == .ultraOrange && a.use24h)
    }

    @Test func payloadRoundTripKeepsDesignsAndDropsWatchReadings() throws {
        var lib = FaceLibrary.starter(now: Date(timeIntervalSince1970: 1_790_000_000))
        var custom = FaceTemplate.wayfinder.defaultDesign(id: "mine", now: Date(timeIntervalSince1970: 1_790_000_000))
        custom.accent = FaceColor(0.2, 0.4, 0.6)
        custom.background = .glow(.blue)
        custom.startsInNightMode = true
        lib.save(custom)
        let data = FaceData.demo(now: Date(timeIntervalSince1970: 1_790_000_000))
        let payload = WatchPayload(library: lib, data: data, sentAt: Date(timeIntervalSince1970: 1_790_000_100))
        let back = try #require(WatchPayload.decode(try payload.encoded()))
        #expect(back.library == lib && back.version == WatchPayload.currentVersion)
        #expect(back.data.recovery == 72 && back.data.workout == data.workout && back.data.race == data.race)
        #expect(back.data.heartRate == nil && back.data.steps == nil && back.data.weather == nil)
        // En el reloj, lo medido allí va encima de lo del iPhone.
        let merged = back.data.merged(withWatch: FaceData(heartRate: 88, steps: 120))
        #expect(merged.heartRate == 88 && merged.steps == 120 && merged.recovery == 72)
    }

    @Test func libraryEditing() {
        var lib = FaceLibrary.starter(now: Date(timeIntervalSince1970: 0))
        let first = lib.designs[0].id
        let copy = lib.duplicate(first, newID: "copy", now: Date(timeIntervalSince1970: 10))
        #expect(copy?.name == "Ultra modular (copia)" && lib.designs[1].id == "copy" && lib.designs.count == 6)
        lib.move(from: 1, to: 6)
        #expect(lib.designs.last?.id == "copy")
        lib.delete("copy")
        #expect(lib.design("copy") == nil && lib.designs.count == 5)
        var d = lib.designs[0]
        d.slots["center"] = .battery   // no cabe en el hueco grande
        lib.save(d)
        #expect(lib.designs[0].complication("center") == .summary)
    }

    @Test func colors() {
        #expect(FaceColor.ultraOrange.hex == "#FF5E00")
        #expect(FaceColor(hex: "#3DDB85") == FaceColor(0x3D / 255.0, 0xDB / 255.0, 0x85 / 255.0))
        #expect(FaceColor(hex: "zz") == nil)
        #expect(FaceColor(1, 1, 1).luminance > 0.99 && FaceColor(0, 0, 0).luminance == 0)
        #expect(FaceColor(1, 0.5, 0).darkened(0.5) == FaceColor(0.5, 0.25, 0))
        #expect(FaceDial.roman.label(hour: 12) == "XII" && FaceDial.minimal.label(hour: 4) == nil && FaceDial.indices.label(hour: 3) == nil)
    }
}

@Suite struct FaceValueTests {
    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Madrid")!
        return c
    }

    // Miércoles 30 de septiembre de 2026, 10:09:30 en Madrid.
    let now = ISO8601DateFormatter().date(from: "2026-09-30T08:09:30Z")!

    @Test func valuesInSpanish() throws {
        let d = FaceData.demo(now: now)
        let rec = try #require(FaceValues.value(.recovery, d, now: now, calendar: calendar))
        #expect(rec.textWithUnit == "72 %" && rec.fraction == 0.72 && rec.tint == .recoveryHigh && rec.detail == "Buena")
        let strain = try #require(FaceValues.value(.strain, d, now: now, calendar: calendar))
        #expect(strain.text == "11,4" && strain.detail == "Objetivo 12–15")
        #expect(FaceValues.value(.sleep, d, now: now, calendar: calendar)?.text == "7:22")
        #expect(FaceValues.value(.steps, d, now: now, calendar: calendar)?.text == "8.412")
        #expect(FaceValues.value(.summary, d, now: now, calendar: calendar)?.text == "72 % · 11,4 · 7:22")
        let race = try #require(FaceValues.value(.race, d, now: now, calendar: calendar))
        #expect(race.textWithUnit == "74 días" && race.title == "10K DE VALENCIA")
        #expect(FaceValues.value(.weather, d, now: now, calendar: calendar)?.text == "19°")
        #expect(FaceValues.value(.weather, d, now: now, calendar: calendar)?.detail == "Poco nuboso")
        let date = try #require(FaceValues.value(.date, d, now: now, calendar: calendar))
        #expect(date.title == "MIÉ" && date.text == "30" && date.detail == "SEPT")
        #expect(FaceValues.value(.battery, d, now: now, calendar: calendar)?.textWithUnit == "82 %")
        #expect(FaceValues.value(.compass, d, now: now, calendar: calendar)?.title == "NE")
        #expect(FaceValues.value(.heartRate, d, now: now, calendar: calendar)?.detail == "Última hora: 58–124")
        #expect(FaceValues.value(.none, d, now: now, calendar: calendar) == nil)
    }

    @Test func missingDataShowsADash() {
        let empty = FaceData()
        for c in FaceComplication.allCases where c != .none && c != .date {
            let v = FaceValues.value(c, empty, now: now, calendar: calendar)
            #expect(v != nil, "\(c)")
            if c == .workout { #expect(v?.text == "Descanso") } else { #expect(v?.text == FaceValues.missing, "\(c)") }
            #expect(v?.unit == nil, "\(c)")
        }
    }

    @Test func raceDayAndAfter() {
        var d = FaceData()
        d.race = FaceRace(name: "Maratón", date: now.addingTimeInterval(3600))
        #expect(FaceValues.value(.race, d, now: now, calendar: calendar)?.text == "Hoy")
        d.race?.date = now.addingTimeInterval(-86_400 * 2)
        #expect(FaceValues.value(.race, d, now: now, calendar: calendar)?.text == "Hecha")
        d.race?.date = now.addingTimeInterval(86_400)
        #expect(FaceValues.value(.race, d, now: now, calendar: calendar)?.textWithUnit == "1 día")
    }

    @Test func clockAndHands() {
        let c = FaceValues.clock(now, use24h: true, calendar: calendar)
        #expect(c.hours == "10" && c.minutes == "09" && abs(c.second - 30) < 0.001)
        let pm = ISO8601DateFormatter().date(from: "2026-09-30T11:05:00Z")!   // 13:05
        #expect(FaceValues.clock(pm, use24h: false, calendar: calendar).hours == "1")
        #expect(FaceValues.clock(pm, use24h: true, calendar: calendar).hours == "13")
        let midnight = ISO8601DateFormatter().date(from: "2026-09-29T22:00:00Z")!
        #expect(FaceValues.clock(midnight, use24h: false, calendar: calendar).hours == "12")
        #expect(FaceValues.clock(midnight, use24h: true, calendar: calendar).hours == "00")
        let three = FaceGeometry.handAngles(hour: 15, minute: 0, second: 0)
        #expect(abs(three.hour - .pi / 2) < 1e-9 && three.minute == 0 && three.second == 0)
        let half = FaceGeometry.handAngles(hour: 6, minute: 30, second: 30, smoothSeconds: false)
        #expect(abs(half.minute - (30.5 / 60) * 2 * .pi) < 1e-9 && abs(half.second - .pi) < 1e-9)
    }

    @Test func numbersAndHeadings() {
        #expect(FaceValues.thousands(0) == "0" && FaceValues.thousands(999) == "999" && FaceValues.thousands(1000) == "1.000")
        #expect(FaceValues.thousands(1_234_567) == "1.234.567" && FaceValues.thousands(-1500) == "-1.500")
        #expect(FaceValues.decimal(11.45, digits: 1) == "11,4" || FaceValues.decimal(11.45, digits: 1) == "11,5")
        #expect(FaceValues.clockDuration(minutes: 65) == "1:05")
        #expect(FaceValues.cardinal(0) == "N" && FaceValues.cardinal(44) == "NE" && FaceValues.cardinal(90) == "E")
        #expect(FaceValues.cardinal(359) == "N" && FaceValues.cardinal(-10) == "N" && FaceValues.cardinal(225) == "SO")
    }
}

@Suite struct FaceGeometryTests {
    @Test func roundedRectangleEdge() {
        let (w, h, r) = (100.0, 100.0, 20.0)
        func at(_ t: Double) -> (FacePoint, Double) {
            let p = FaceGeometry.roundedRectPoint(t: t, width: w, height: h, radius: r)
            return (p.point, p.angle)
        }
        let top = at(0)
        #expect(abs(top.0.x - 50) < 1e-9 && top.0.y == 0 && abs(top.1 + .pi / 2) < 1e-9)
        let right = at(0.25)
        #expect(abs(right.0.x - 100) < 1e-9 && abs(right.0.y - 50) < 1e-9 && abs(right.1) < 1e-9)
        let bottom = at(0.5)
        #expect(abs(bottom.0.x - 50) < 1e-9 && abs(bottom.0.y - 100) < 1e-9)
        let left = at(0.75)
        #expect(abs(left.0.x) < 1e-9 && abs(left.0.y - 50) < 1e-9 && abs(left.1 - .pi) < 1e-9)
        // A 1/8 del perímetro, en mitad de la esquina de arriba a la derecha.
        let corner = at(0.125)
        #expect(abs(corner.0.x - (80 + 20 * cos(-Double.pi / 4))) < 1e-6 && abs(corner.0.y - (20 + 20 * sin(-Double.pi / 4))) < 1e-6)
        #expect(abs(corner.1 + .pi / 4) < 1e-6)
        #expect(abs(FaceGeometry.perimeter(width: w, height: h, radius: r) - (240 + 40 * .pi)) < 1e-9)
        // Una vuelta completa vuelve al principio.
        #expect(abs(at(1).0.x - 50) < 1e-9 && abs(at(1.25).0.x - 100) < 1e-9)
    }

    @Test func edgeIsContinuousOnAWatchScreen() {
        // 45 mm: 198 × 242 puntos.
        var last = FaceGeometry.roundedRectPoint(t: 0, width: 198, height: 242, radius: 44).point
        let step = FaceGeometry.perimeter(width: 198, height: 242, radius: 44) / 600
        for i in 1...600 {
            let p = FaceGeometry.roundedRectPoint(t: Double(i) / 600, width: 198, height: 242, radius: 44).point
            #expect(hypot(p.x - last.x, p.y - last.y) < step * 1.01)
            #expect(p.x >= -1e-9 && p.x <= 198 + 1e-9 && p.y >= -1e-9 && p.y <= 242 + 1e-9)
            last = p
        }
    }

    @Test func clockPoints() {
        let c = FacePoint(x: 50, y: 50)
        let twelve = FaceGeometry.clockPoint(center: c, radius: 40, angle: 0)
        let three = FaceGeometry.clockPoint(center: c, radius: 40, angle: .pi / 2)
        #expect(abs(twelve.x - 50) < 1e-9 && abs(twelve.y - 10) < 1e-9)
        #expect(abs(three.x - 90) < 1e-9 && abs(three.y - 50) < 1e-9)
    }
}

@Suite struct FaceWeatherTests {
    @Test func openMeteoCurrent() throws {
        let url = try #require(FaceWeatherService.currentURL(latitude: 40.4153, longitude: -3.6845))
        #expect(url.absoluteString.contains("latitude=40.415") && url.absoluteString.contains("current=temperature_2m,weather_code,is_day"))
        let json = #"{"latitude":40.4,"longitude":-3.7,"current":{"time":"2026-09-30T10:00","temperature_2m":18.6,"weather_code":61,"is_day":1}}"#
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let w = try #require(FaceWeatherService.parseCurrent(Data(json.utf8), now: now))
        #expect(w.temperatureC == 18.6 && w.code == 61 && w.isDay && w.symbol == "cloud.rain.fill" && w.text == "Lluvia")
        #expect(FaceWeatherService.parseCurrent(Data("{}".utf8), now: now) == nil)
        #expect(FaceWeatherService.describe(code: 0, isDay: false).symbol == "moon.stars.fill")
        #expect(FaceWeatherService.describe(code: 95, isDay: true).text == "Tormenta")
    }
}
