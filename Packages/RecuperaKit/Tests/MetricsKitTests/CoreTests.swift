import Foundation
import Testing
@testable import MetricsKit

@Suite struct CoreTests {
    @Test func localDateRoundTrip() {
        let d = LocalDate(year: 2026, month: 9, day: 29)
        #expect(LocalDate(dayNumber: d.dayNumber) == d)
        #expect(d.adding(days: 3) == LocalDate(year: 2026, month: 10, day: 2))
        #expect(d.isoWeekday == 2) // martes
        #expect(LocalDate(isoString: "2026-02-28")!.adding(days: 1) == LocalDate(year: 2026, month: 3, day: 1))
        #expect(LocalDate(utc("2026-09-29T23:30"), utcOffsetSeconds: 7200) == LocalDate(year: 2026, month: 9, day: 30))
    }

    @Test func robustStats() {
        #expect(Stats.median([3, 1, 2]) == 2)
        #expect(Stats.median([4, 1, 2, 3]) == 2.5)
        #expect(abs(Stats.robustSigma([1, 2, 3, 4, 100])! - 1.4826) < 1e-9)
        #expect(Stats.percentile([10, 20, 30, 40], 50) == 25)
        #expect(abs(Stats.normalCDF(0) - 0.5) < 1e-12)
        #expect(abs(Stats.normalCDF(0.44) - 0.670) < 0.001)
    }

    @Test func olsRecoversCoefficients() {
        let x = (0..<20).map { i in [1.0, Double(i % 2), Double(i)] }
        let y = x.map { 3 + 2 * $0[1] - 0.5 * $0[2] }
        let b = Stats.ols(x, y)!
        #expect(abs(b[0] - 3) < 1e-9 && abs(b[1] - 2) < 1e-9 && abs(b[2] + 0.5) < 1e-9)
    }

    @Test func rangeSubtraction() {
        let r = TimeRange(start: utc("2026-09-01T17:50"), end: utc("2026-09-01T18:50"))
        let pieces = r.subtracting([TimeRange(start: utc("2026-09-01T18:00"), end: utc("2026-09-01T18:45"))])
        #expect(pieces.map(\.minutes) == [10, 5])
    }

    /// Los parámetros del código coinciden con el JSON del doc. 05 §12.
    @Test func paramsMatchDocumentation() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/05-algoritmos-y-metricas.md")
        let doc = try String(contentsOf: url, encoding: .utf8)
        let section = doc.components(separatedBy: "## 12. Parámetros iniciales")[1]
        let json = section.components(separatedBy: "```json")[1].components(separatedBy: "```")[0]
        let decoded = try AlgorithmParams.decode(json: Data(json.utf8))
        #expect(decoded == AlgorithmParams.default)
    }
}
