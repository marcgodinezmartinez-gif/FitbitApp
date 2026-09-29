import ActivityKit
import Foundation

/// Live Activity de un entrenamiento iniciado en la app (RF-WID-03): pantalla de bloqueo y Dynamic Island.
/// Se compila en la app y en la extensión de widgets.
struct WorkoutActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Inicio del cronómetro.
        var startedAt: Date
        /// Carga del día al empezar y su banda objetivo (contexto; sin FC en vivo, RF-ENT-07).
        var dayStrain: Double?
        var targetLow: Double?
        var targetHigh: Double?
    }

    var kindName: String
    var symbolName: String
}
