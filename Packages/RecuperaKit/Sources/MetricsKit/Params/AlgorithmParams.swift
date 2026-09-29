import Foundation

/// Parámetros versionados de los algoritmos (doc. 05 §12). Se guardan en `algorithm_params`
/// y cada valor derivado registra la versión con la que se calculó (RNF-CAL-05).
/// Un test comprueba que estos valores coinciden con el JSON del documento.
public struct AlgorithmParams: Codable, Sendable, Hashable {
    public static let currentVersion = "0.1.0"

    public var baseline: Baseline
    public var recovery: Recovery
    public var strain: Strain
    public var sleep: Sleep
    public var stress: Stress
    public var healthMonitor: HealthMonitor
    public var physioAge: PhysioAge
    public var fusion: Fusion
    public var dayAnalysis: DayAnalysis

    public struct SDFloor: Codable, Sendable, Hashable {
        public var lnRmssd: Double
        public var rhr: Double
        public var respRate: Double
        public var skinTemp: Double
        public var spo2: Double
    }

    public struct Baseline: Codable, Sendable, Hashable {
        public var shortWindow: Int
        public var longWindow: Int
        public var minNights: Int
        public var fullNights: Int
        public var hrvSource: String
        public var sdFloor: SDFloor
    }

    public struct Zones: Codable, Sendable, Hashable {
        public var high: Double
        public var low: Double
    }

    public struct Recovery: Codable, Sendable, Hashable {
        public var wHrv: Double
        public var wRhr: Double
        public var wSleep: Double
        public var wPenalties: Double
        public var hrvZCapHigh: Double
        public var sleepAnchor: Double
        public var sleepScale: Double
        public var c0: Double
        public var sInitial: Double
        public var sMethod: String
        public var zones: Zones
    }

    public struct Strain: Codable, Sendable, Hashable {
        public var xMin: Double
        public var requireMotion: Bool
        public var tau: Double
        public var gamma: Double
        public var banisterMode: String
        public var banister: [String: [Double]]
        public var kappaSrpe: Double
        public var targetK: Double
        public var targetHalfWidth: Double
        public var targetBounds: [Double]
        public var ewmaAcuteDays: Int
        public var ewmaChronicDays: Int
    }

    public struct PerformanceWeights: Codable, Sendable, Hashable {
        public var sufficiency: Double
        public var efficiency: Double
        public var consistency: Double
    }

    public struct Bands: Codable, Sendable, Hashable {
        public var optimal: Double
        public var sufficient: Double
    }

    public struct Sleep: Codable, Sendable, Hashable {
        public var baseByAge: [String: Double]
        public var strainAdjPerPoint: Double
        public var strainAdjMax: Double
        public var debtRepayFraction: Double
        public var debtRepayMax: Double
        public var napCreditMax: Double
        public var debtDecay: Double
        public var debtCap: Double
        public var plannerFactors: [Double]
        public var consistencyStepMaxMin: Double
        public var performanceWeights: PerformanceWeights
        public var efficiencyScale: [Double]
        public var bands: Bands
    }

    public struct SustainedHigh: Codable, Sendable, Hashable {
        public var level: Double
        public var minutes: Int
    }

    public struct Stress: Codable, Sendable, Hashable {
        public var windowMin: Int
        public var zeroStepsLookbackMin: Int
        public var postExerciseExclusionMin: Int
        public var calmPercentile: Double
        public var baselineDays: Int
        public var deltaRefMinBpm: Double
        public var deltaRefHrrFraction: Double
        public var sustainedHigh: SustainedHigh
    }

    public struct HealthMonitor: Codable, Sendable, Hashable {
        public var zThreshold: Double
        public var minSignalsForAlert: Int
        public var rhrDeltaBpm: Double
        public var rhrConsecutiveNights: Int
        public var respRateDeltaBpm: Double
        public var hrvZLow: Double
        public var tempZHigh: Double
    }

    public struct PhysioAge: Codable, Sendable, Hashable {
        public var gompertzDoublingYears: Double
        public var shrinkage: Double
        public var capPerFactorYears: Double
        public var capTotalYears: Double
        public var windowDays: Int
        public var minValidDays: Int
        public var calibratedDays: Int
        public var paceWindowDays: Int
    }

    public struct Fusion: Codable, Sendable, Hashable {
        public var matchOverlap: Double
        public var minLeftoverMin: Double
        public var hrWorkoutPriority: String
        public var watchMinSamples: Int
        public var disagreementBpm: Double
        public var disagreementMin: Int
        public var vo2maxWatchMaxAgeDays: Int
        public var gpsDistanceOverride: Bool
        public var agreementWindowRuns: Int

        public var prefersWatchInWorkouts: Bool { hrWorkoutPriority == "apple_watch" }
    }

    public struct DayAnalysis: Codable, Sendable, Hashable {
        public var minKeys: Int
        public var maxKeys: Int
        public var runPaceWindowDays: Int
        public var runSimilarDistance: Double
        public var bedtimeAdvanceMin: [Double]
        public var debtThresholdMin: Double
    }

    /// Valores de `algorithm_version = 0.1.0` (doc. 05 §12).
    public static let `default` = AlgorithmParams(
        baseline: Baseline(shortWindow: 30, longWindow: 60, minNights: 4, fullNights: 14,
                           hrvSource: "deep_if_min_20_else_avg",
                           sdFloor: SDFloor(lnRmssd: 0.05, rhr: 1.0, respRate: 0.3, skinTemp: 0.1, spo2: 0.5)),
        recovery: Recovery(wHrv: 0.55, wRhr: 0.25, wSleep: 0.20, wPenalties: 0.10, hrvZCapHigh: 1.0,
                           sleepAnchor: 85, sleepScale: 10, c0: -0.15, sInitial: 0.8,
                           sMethod: "sqrt_wRw_after_30_nights", zones: Zones(high: 67, low: 33)),
        strain: Strain(xMin: 0.30, requireMotion: false, tau: 100, gamma: 0.8, banisterMode: "sex_specific",
                       banister: ["male": [0.64, 1.92], "female": [0.86, 1.67], "unspecified": [0.75, 1.795]],
                       kappaSrpe: 0.2, targetK: 3, targetHalfWidth: 1.5, targetBounds: [4, 19],
                       ewmaAcuteDays: 7, ewmaChronicDays: 28),
        sleep: Sleep(baseByAge: ["18-64": 480, "65+": 450], strainAdjPerPoint: 5, strainAdjMax: 45,
                     debtRepayFraction: 0.25, debtRepayMax: 60, napCreditMax: 60, debtDecay: 0.85, debtCap: 600,
                     plannerFactors: [1.0, 0.85, 0.70], consistencyStepMaxMin: 15,
                     performanceWeights: PerformanceWeights(sufficiency: 0.70, efficiency: 0.15, consistency: 0.15),
                     efficiencyScale: [70, 95], bands: Bands(optimal: 85, sufficient: 70)),
        stress: Stress(windowMin: 5, zeroStepsLookbackMin: 12, postExerciseExclusionMin: 120, calmPercentile: 10,
                       baselineDays: 14, deltaRefMinBpm: 15, deltaRefHrrFraction: 0.25,
                       sustainedHigh: SustainedHigh(level: 2.5, minutes: 30)),
        healthMonitor: HealthMonitor(zThreshold: 2.0, minSignalsForAlert: 2, rhrDeltaBpm: 4, rhrConsecutiveNights: 2,
                                     respRateDeltaBpm: 3, hrvZLow: -1.5, tempZHigh: 2.0),
        physioAge: PhysioAge(gompertzDoublingYears: 8, shrinkage: 0.5, capPerFactorYears: 5, capTotalYears: 10,
                             windowDays: 180, minValidDays: 21, calibratedDays: 90, paceWindowDays: 30),
        fusion: Fusion(matchOverlap: 0.5, minLeftoverMin: 10, hrWorkoutPriority: "apple_watch", watchMinSamples: 2,
                       disagreementBpm: 15, disagreementMin: 5, vo2maxWatchMaxAgeDays: 60, gpsDistanceOverride: true,
                       agreementWindowRuns: 10),
        dayAnalysis: DayAnalysis(minKeys: 3, maxKeys: 5, runPaceWindowDays: 60, runSimilarDistance: 0.2,
                                 bedtimeAdvanceMin: [15, 30], debtThresholdMin: 60)
    )

    public static func decode(json: Data) throws -> AlgorithmParams {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return try d.decode(AlgorithmParams.self, from: json)
    }

    public func encodedJSON() throws -> Data {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.outputFormatting = [.sortedKeys]
        return try e.encode(self)
    }

    /// Coeficientes (a, b) de Banister según el sexo (ALG-CAR-01).
    public func banisterCoefficients(for sex: Sex) -> (a: Double, b: Double) {
        let key: String
        if strain.banisterMode == "sex_specific" {
            key = sex.rawValue
        } else {
            key = "male"
        }
        let v = strain.banister[key] ?? strain.banister["unspecified"] ?? [0.75, 1.795]
        return (v[0], v[1])
    }
}
