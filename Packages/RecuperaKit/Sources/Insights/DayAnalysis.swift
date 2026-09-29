import Foundation
import MetricsKit

/// Salida del análisis del día con el esquema fijo de ALG-ANA-01. La usan la versión determinista y el Coach.
public struct DayAnalysis: Codable, Sendable, Hashable {
    public enum Tone: String, Codable, Sendable { case positivo, aVigilar = "a_vigilar", neutro }

    public struct Key: Codable, Sendable, Hashable {
        public var tono: Tone
        public var texto: String
        public var metricas: [String]

        public init(tono: Tone, texto: String, metricas: [String]) {
            self.tono = tono
            self.texto = texto
            self.metricas = metricas
        }
    }

    public struct ActivitySummary: Codable, Sendable, Hashable {
        public var tipo: String
        public var distanciaKm: Double?
        public var ritmoMinKm: String?
        public var carga: Double
        public var fuentes: [String]

        enum CodingKeys: String, CodingKey {
            case tipo, carga, fuentes
            case distanciaKm = "distancia_km"
            case ritmoMinKm = "ritmo_min_km"
        }
    }

    public struct DataUsed: Codable, Sendable, Hashable {
        public var metrica: String
        public var fecha: String
        public var fuente: String
    }

    public var titular: String
    public var datosHasta: String
    public var claves: [Key]
    public var actividades: [ActivitySummary]
    public var estaNoche: String
    public var manana: String
    public var datosUsados: [DataUsed]

    enum CodingKeys: String, CodingKey {
        case titular, claves, actividades, manana
        case datosHasta = "datos_hasta"
        case estaNoche = "esta_noche"
        case datosUsados = "datos_usados"
    }

    /// Esquema JSON para validar la respuesta del Coach (salida estructurada, RF-COA-18).
    public static let jsonSchema: String = """
    {"type":"object","additionalProperties":false,
     "required":["titular","datos_hasta","claves","actividades","esta_noche","manana","datos_usados"],
     "properties":{
      "titular":{"type":"string"},
      "datos_hasta":{"type":"string"},
      "claves":{"type":"array","items":{"type":"object","additionalProperties":false,"required":["tono","texto","metricas"],
        "properties":{"tono":{"type":"string","enum":["positivo","a_vigilar","neutro"]},"texto":{"type":"string"},
        "metricas":{"type":"array","items":{"type":"string"}}}}},
      "actividades":{"type":"array","items":{"type":"object","additionalProperties":false,
        "required":["tipo","distancia_km","ritmo_min_km","carga","fuentes"],
        "properties":{"tipo":{"type":"string"},"distancia_km":{"anyOf":[{"type":"number"},{"type":"null"}]},
        "ritmo_min_km":{"anyOf":[{"type":"string"},{"type":"null"}]},
        "carga":{"type":"number"},"fuentes":{"type":"array","items":{"type":"string"}}}}},
      "esta_noche":{"type":"string"},
      "manana":{"type":"string"},
      "datos_usados":{"type":"array","items":{"type":"object","additionalProperties":false,"required":["metrica","fecha","fuente"],
        "properties":{"metrica":{"type":"string"},"fecha":{"type":"string"},"fuente":{"type":"string"}}}}}}
    """

    public func validated(minKeys: Int = 3, maxKeys: Int = 5) -> Bool {
        !titular.isEmpty && (minKeys...maxKeys).contains(claves.count) && !estaNoche.isEmpty && !manana.isEmpty
    }
}

/// Un hecho del ciclo con su relevancia (paso 1–2 de ALG-ANA-01).
public struct DayFact: Codable, Sendable, Hashable {
    public enum Block: String, Codable, Sendable { case sleep, recovery, strain, activity, stress, health, habits }

    public var block: Block
    public var metric: String
    public var text: String
    public var tone: DayAnalysis.Tone
    public var relevance: Double
    public var source: DataSourceKind
    public var confident: Bool
}

/// Todo lo que el análisis sabe del día; es también lo que recibe el Coach con `get_day_detail`.
public struct DayFacts: Codable, Sendable, Hashable {
    public var date: String
    public var dataUntil: String
    /// Hora local de los datos más recientes («20:19»), la que se muestra.
    public var dataUntilLocal: String
    public var facts: [DayFact]
    public var activities: [DayAnalysis.ActivitySummary]
    public var tonight: String
    public var tomorrow: String
    public var headline: String
    public var dataUsed: [DayAnalysis.DataUsed]
}
