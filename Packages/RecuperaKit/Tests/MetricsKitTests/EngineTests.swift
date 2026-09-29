import Foundation
import Testing
@testable import MetricsKit

@Suite struct EngineTests {
    let now = utc("2026-09-29T20:00")

    @Test func fullPipelineOnSyntheticData() {
        let input = SyntheticData.generate(days: 60, endingAt: now)
        let out = MetricsEngine.run(input)
        #expect(out.cycles.count >= 58)
        let scored = out.cycles.compactMap(\.recovery.score)
        #expect(scored.count >= 50)
        #expect(scored.allSatisfy { (0...100).contains($0) })
        #expect(out.cycles.allSatisfy { $0.strain.strain >= 0 && $0.strain.strain <= 21 })
        // Cada carrera del Watch aparece en exactamente una actividad fusionada con las dos fuentes;
        // las sesiones de fuerza (solo del Watch) quedan como actividades propias.
        let watchRuns = input.activities.filter { $0.source == .appleHealth && $0.kind.isRun }
        for w in watchRuns {
            let owners = out.fusedActivities.filter { $0.members.contains { $0.id == w.id } }
            #expect(owners.count == 1)
            #expect(owners.first?.sources == [.appleHealth, .googleHealth])
        }
        let gym = input.activities.filter { $0.kind.isStrength }
        #expect(!gym.isEmpty)
        for g in gym {
            #expect(out.fusedActivities.filter { $0.members.contains { $0.id == g.id } }.map(\.sources) == [[.appleHealth]])
        }
        #expect(out.physioAge?.factors.contains { $0.key == "strength" } == true)
        #expect(out.agreementSummary != nil)
        #expect(out.tonightNeed != nil)
        #expect(out.habitImpacts.contains { $0.questionKey == "alcohol" })
    }

    /// Quitar los datos del Watch da exactamente el resultado de la Fitbit sola (RNF-DIS-09).
    @Test func strippingWatchEqualsFitbitOnly() {
        var stripped = SyntheticData.generate(days: 30, endingAt: now, withWatch: true)
        stripped.hrWatch = []
        stripped.activities.removeAll { $0.source == .appleHealth }
        stripped.vo2max.removeAll { $0.source == .appleHealth }
        let a = MetricsEngine.run(stripped)
        let b = MetricsEngine.run(SyntheticData.generate(days: 30, endingAt: now, withWatch: false))
        #expect(a.cycles == b.cycles)
    }

    /// Las líneas base (noches) no cambian con el Watch; la recuperación solo puede variar a través
    /// de la necesidad de sueño, que depende de la carga del día anterior.
    @Test func baselinesDoNotDependOnWatch() {
        let with = MetricsEngine.run(SyntheticData.generate(days: 40, endingAt: now, withWatch: true))
        let without = MetricsEngine.run(SyntheticData.generate(days: 40, endingAt: now, withWatch: false))
        #expect(with.nights == without.nights)
        let hrvWith = with.cycles.map { $0.recovery.components.first { $0.kind == .hrv }?.z }
        let hrvWithout = without.cycles.map { $0.recovery.components.first { $0.kind == .hrv }?.z }
        #expect(hrvWith == hrvWithout)
    }

    @Test func deterministic() {
        let a = MetricsEngine.run(SyntheticData.generate(days: 20, endingAt: now))
        let b = MetricsEngine.run(SyntheticData.generate(days: 20, endingAt: now))
        #expect(a.cycles == b.cycles)
    }

    @Test func fusedHRNeverHasTwoSourcesPerMinute() {
        let out = MetricsEngine.run(SyntheticData.generate(days: 10, endingAt: now))
        #expect(Set(out.fusedHR.map(\.minute)).count == out.fusedHR.count)
    }

    @Test func cyclesAreContiguous() {
        let out = MetricsEngine.run(SyntheticData.generate(days: 15, endingAt: now))
        for (a, b) in zip(out.cycles, out.cycles.dropFirst()) {
            #expect(a.cycle.end == b.cycle.start)
        }
        #expect(out.cycles.last?.isOpen == true)
    }
}
