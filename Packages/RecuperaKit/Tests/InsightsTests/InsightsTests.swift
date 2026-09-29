import Foundation
import Testing
@testable import Insights
@testable import MetricsKit

private func utc(_ s: String) -> Date {
    let f = ISO8601DateFormatter()
    return f.date(from: s + ":00Z")!
}

@Suite struct InsightsTests {
    let now = utc("2026-09-29T21:00")

    @Test func formatting() {
        #expect(Format.duration(minutes: 461) == "7 h 41 min")
        #expect(Format.duration(minutes: 45) == "45 min")
        #expect(Format.clock(minutes: -50) == "23:10")
        #expect(Format.pace(secondsPerKm: 312) == "5:12")
        #expect(Format.km(8200) == "8,2 km")
    }

    @Test func deterministicAnalysisHasThreeToFiveKeys() throws {
        let input = SyntheticData.generate(days: 45, endingAt: now)
        let out = MetricsEngine.run(input)
        for cycle in out.cycles.suffix(10) {
            let facts = DayAnalyzer.facts(for: cycle, output: out, profile: input.profile, now: now,
                                          journalLabels: JournalCatalog.labels, journal: input.journal)
            let a = DayAnalyzer.analyze(facts)
            #expect(a.validated())
            // El JSON respeta los nombres del esquema de ALG-ANA-01.
            let json = String(data: try JSONEncoder().encode(a), encoding: .utf8)!
            for key in ["titular", "datos_hasta", "claves", "actividades", "esta_noche", "manana", "datos_usados"] {
                #expect(json.contains("\"\(key)\""))
            }
            let back = try JSONDecoder().decode(DayAnalysis.self, from: Data(json.utf8))
            #expect(back == a)
        }
    }

    @Test func runDayMentionsWatchSource() {
        let input = SyntheticData.generate(days: 45, endingAt: now)
        let out = MetricsEngine.run(input)
        let runDay = out.cycles.last { c in c.activities.contains { $0.activity.kind.isRun && !c.isOpen } }!
        let a = DayAnalyzer.analyze(DayAnalyzer.facts(for: runDay, output: out, profile: input.profile, now: now))
        #expect(a.actividades.contains { $0.fuentes.contains("apple_watch") && $0.distanciaKm != nil && $0.ritmoMinKm != nil })
        #expect(a.datosUsados.contains { $0.fuente == "apple_watch" })
    }

    @Test func todayRecommendationAndWeeklyReport() {
        let input = SyntheticData.generate(days: 30, endingAt: now)
        let out = MetricsEngine.run(input)
        let text = TodayRecommendation.text(for: out.current!, output: out, profile: input.profile)
        #expect(text.contains("Acuéstate a las"))
        let report = WeeklyReportBuilder.build(output: out, weekStart: LocalDate(year: 2026, month: 9, day: 21))
        #expect(report.recommendations.count >= 1 && report.recommendations.count <= 3)
        #expect(report.runs >= 2)
    }

    @Test func catalogHasAboutThirtyQuestions() {
        #expect(JournalCatalog.questions.count >= 28)
        #expect(Set(JournalCatalog.questions.map(\.key)).count == JournalCatalog.questions.count)
    }
}
