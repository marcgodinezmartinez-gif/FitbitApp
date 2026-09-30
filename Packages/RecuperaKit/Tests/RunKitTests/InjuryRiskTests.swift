import Foundation
import Testing
@testable import RunKit
@testable import MetricsKit

@Suite struct InjuryRiskTests {
    let today = LocalDate(year: 2026, month: 9, day: 30)

    func run(_ daysAgo: Int, km: Double) -> RunSummary {
        let date = today.adding(days: -daysAgo)
        return RunSummary(id: "r\(daysAgo)", start: date.startDate(utcOffsetSeconds: 0).addingTimeInterval(8 * 3600), utcOffsetSeconds: 0,
                          kind: .running, name: "Carrera", distanceM: km * 1000, movingS: km * 330, elapsedS: km * 330,
                          bestEfforts: [:], paceCurve: [], powerCurve: [], sources: [.appleHealth], signature: "")
    }

    func loads(_ value: (Int) -> Double, days: Int = 90) -> [LocalDate: Double] {
        Dictionary(uniqueKeysWithValues: (0..<days).map { k in (today.adding(days: -k), value(k)) })
    }

    @Test func steadyLoadIsOptimalAndAJumpIsRisky() {
        let steady = InjuryRisk.assess(dailyLoads: loads { _ in 100 }, runs: [], today: today)
        #expect(abs((steady.ratio ?? 0) - 1) < 0.01 && steady.level == .optimal && steady.points.count == 56)
        // La última semana, el doble: por encima de 1,3.
        let jump = InjuryRisk.assess(dailyLoads: loads { $0 < 7 ? 200 : 100 }, runs: [], today: today)
        #expect((jump.ratio ?? 0) > 1.3 && (jump.level == .caution || jump.level == .high))
        // Una semana casi parado: carga baja.
        let rest = InjuryRisk.assess(dailyLoads: loads { $0 < 7 ? 20 : 100 }, runs: [], today: today)
        #expect(rest.level == .low)
        // Sin cuatro semanas de datos no hay cociente.
        #expect(InjuryRisk.assess(dailyLoads: loads({ _ in 100 }, days: 20), runs: [], today: today).ratio == nil)
    }

    @Test func distanceSpikesAgainstTheLongestOfTheLast30Days() throws {
        let runs = [run(45, km: 8), run(20, km: 8), run(10, km: 10), run(6, km: 6), run(2, km: 14)]
        let risk = InjuryRisk.assess(dailyLoads: loads { _ in 100 }, runs: runs, today: today)
        // 14 km frente a 10: +40 %, pico alto; 10 frente a 8: +25 %, moderado. La de hace 20 días no tenía nada en 30 días
        // (la de hace 45 queda fuera) y está fuera de las 4 semanas.
        #expect(risk.spikes.map(\.runID) == ["r2", "r10"])
        #expect(risk.spikes[0].level == .high && abs((risk.spikes[0].increasePct ?? 0) - 40) < 0.1)
        #expect(risk.spikes[1].level == .moderate)
        #expect(risk.longestLast30M == 14_000 && abs((risk.safeLongRunM ?? 0) - 15_400) < 0.1)
        #expect(risk.advice.contains("40 %"))
        let returning = InjuryRisk.spikes(runs: [run(60, km: 10), run(3, km: 8)], since: today.adding(days: -27))
        #expect(returning.map(\.level) == [.returning])
    }
}
