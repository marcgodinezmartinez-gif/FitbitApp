import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
import MetricsKit

/// Punto del perfil de un recorrido: metros desde la salida y altitud.
public struct CoursePoint: Codable, Sendable, Hashable {
    public var distanceM: Double
    public var altitudeM: Double

    public init(distanceM: Double, altitudeM: Double) {
        self.distanceM = distanceM
        self.altitudeM = altitudeM
    }
}

/// Sitio de la carrera (para la previsión del tiempo): solo la ciudad, nunca tu ubicación.
public struct RaceLocation: Codable, Sendable, Hashable, Identifiable {
    public var name: String
    public var detail: String?
    public var latitude: Double
    public var longitude: Double

    public init(name: String, detail: String? = nil, latitude: Double, longitude: Double) {
        self.name = name
        self.detail = detail
        self.latitude = latitude
        self.longitude = longitude
    }

    public var id: String { "\(name)-\(latitude)-\(longitude)" }
}

/// Carrera objetivo (doc. 18 §7): distancia, fecha, recorrido y condiciones.
public struct GoalRace: Codable, Sendable, Hashable {
    public var name: String
    /// Día y hora de la salida.
    public var date: Date
    public var distanceM: Double
    public var elevationGainM: Double
    public var elevationLossM: Double
    /// Perfil del recorrido (de un GPX), cada ~50 m.
    public var profile: [CoursePoint]?
    public var temperatureC: Double?
    public var humidityPct: Double?
    /// De dónde salen la temperatura y la humedad: «previsión», «clima de otros años» o las pones tú.
    public var weatherSource: String?
    public var location: RaceLocation?
    /// Tu objetivo de tiempo (opcional).
    public var targetSeconds: Double?

    public init(name: String, date: Date, distanceM: Double, elevationGainM: Double = 0, elevationLossM: Double = 0,
                profile: [CoursePoint]? = nil, temperatureC: Double? = nil, humidityPct: Double? = nil, weatherSource: String? = nil,
                location: RaceLocation? = nil, targetSeconds: Double? = nil) {
        self.name = name
        self.date = date
        self.distanceM = distanceM
        self.elevationGainM = elevationGainM
        self.elevationLossM = elevationLossM
        self.profile = profile
        self.temperatureC = temperatureC
        self.humidityPct = humidityPct
        self.weatherSource = weatherSource
        self.location = location
        self.targetSeconds = targetSeconds
    }

    /// Distancia estándar más cercana (para el plan de entrenamiento).
    public var standardDistance: RaceDistance {
        [RaceDistance.k5, .k10, .half, .marathon].min { abs($0.rawValue - distanceM) < abs($1.rawValue - distanceM) } ?? .k10
    }
}

/// Ritmo de un km a esfuerzo constante: más lento cuesta arriba, algo más rápido cuesta abajo.
public struct PacedSplit: Sendable, Hashable, Identifiable {
    public var km: Int
    public var distanceM: Double
    public var gradePct: Double
    public var paceSeconds: Double
    public var cumulativeSeconds: Double
    public var id: Int { km }
}

public struct RacePrediction: Sendable, Hashable {
    /// En llano y sin calor (tu VDOT).
    public var flatSeconds: Double
    /// Lo que añade el desnivel.
    public var hillSeconds: Double
    /// Lo que añade el calor.
    public var heatSeconds: Double
    public var totalSeconds: Double
    public var heatSlowdownPct: Double
    public var dewPointC: Double?
    /// Distancia en llano que cuesta lo mismo que el recorrido.
    public var equivalentFlatM: Double
    /// Plan de ritmos por km (solo con el perfil del recorrido).
    public var splits: [PacedSplit]
    /// Demasiado calor para correr a tope (temperatura + punto de rocío por encima de 180 °F).
    public var tooHot: Bool
}

/// Predicción ajustada al desnivel (la misma curva que el ritmo ajustado por pendiente, a igual esfuerzo) y al calor
/// (temperatura + punto de rocío).
public enum RacePredictor {
    /// Cuánto cuesta un tramo con pendiente `grade` frente al llano.
    public static func costFactor(grade: Double) -> Double { RunPhysiology.gradeFactor(grade: grade) }

    /// Punto de rocío (Magnus; Alduchov y Eskridge, 1996).
    public static func dewPoint(temperatureC t: Double, humidityPct rh: Double) -> Double {
        let gamma = log(max(1, min(100, rh)) / 100) + 17.625 * t / (243.04 + t)
        return 243.04 * gamma / (17.625 - gamma)
    }

    /// Temperatura + punto de rocío en °F → cuánto más lento (fracción), según la tabla habitual de los entrenadores
    /// (hasta 100 °F nada; 150 °F, un 4,5 %; 180 °F, un 10 %). Pesa menos en carreras cortas: la mitad por debajo de 20 min.
    public static func heatSlowdown(temperatureC: Double, dewPointC: Double, durationS: Double) -> Double {
        let sum = temperatureC * 9 / 5 + 32 + dewPointC * 9 / 5 + 32
        let table: [(Double, Double)] = [(100, 0), (110, 0.005), (120, 0.01), (130, 0.02), (140, 0.03), (150, 0.045), (160, 0.06),
                                         (170, 0.08), (180, 0.10), (190, 0.12)]
        var pct = 0.0
        if sum >= 190 {
            pct = 0.12
        } else if sum > 100, let k = table.indices.dropLast().first(where: { table[$0].0 <= sum && sum < table[$0 + 1].0 }) {
            let (x0, y0) = table[k], (x1, y1) = table[k + 1]
            pct = y0 + (sum - x0) / (x1 - x0) * (y1 - y0)
        }
        let minutes = durationS / 60
        return pct * (0.5 + 0.5 * min(1, max(0, (minutes - 20) / 40)))
    }

    /// Tramos (longitud, pendiente) del recorrido: del perfil del GPX o, si no hay, del desnivel total repartido en subidas y
    /// bajadas del 4 % (más empinadas si no caben).
    public static func segments(for race: GoalRace) -> [(meters: Double, grade: Double)] {
        if let p = race.profile, p.count >= 2 {
            return zip(p, p.dropFirst()).compactMap { a, b in
                let d = b.distanceM - a.distanceM
                return d > 0 ? (d, (b.altitudeM - a.altitudeM) / d) : nil
            }
        }
        let gain = max(0, race.elevationGainM), loss = max(0, race.elevationLossM)
        guard gain + loss > 0, race.distanceM > 0 else { return [(race.distanceM, 0)] }
        var up = gain / 0.04, down = loss / 0.04
        let room = 0.9 * race.distanceM
        if up + down > room {
            let k = room / (up + down)
            up *= k
            down *= k
        }
        var out: [(meters: Double, grade: Double)] = []
        if up > 0 { out.append((up, gain / up)) }
        if down > 0 { out.append((down, -loss / down)) }
        out.append((race.distanceM - up - down, 0))
        return out
    }

    public static func predict(race: GoalRace, vdot: Double) -> RacePrediction? {
        guard race.distanceM >= 1000, let flat = RunPhysiology.predictedSeconds(meters: race.distanceM, vdot: vdot) else { return nil }
        let segs = segments(for: race)
        let courseM = segs.reduce(0) { $0 + $1.meters }
        let scale = courseM > 0 ? race.distanceM / courseM : 1
        let efd = segs.reduce(0) { $0 + $1.meters * scale * costFactor(grade: $1.grade) }
        let hilly = RunPhysiology.predictedSeconds(meters: efd, vdot: vdot) ?? flat
        var dew: Double?
        if let t = race.temperatureC { dew = race.humidityPct.map { dewPoint(temperatureC: t, humidityPct: $0) } ?? t - 8 }
        let heat = race.temperatureC.map { heatSlowdown(temperatureC: $0, dewPointC: dew ?? $0 - 8, durationS: hilly) } ?? 0
        let total = hilly * (1 + heat)
        let tooHot = race.temperatureC.map { $0 * 9 / 5 + 32 + (dew ?? $0 - 8) * 9 / 5 + 32 > 180 } ?? false

        // Ritmo por km a esfuerzo constante: el tiempo de cada tramo es proporcional a su coste.
        var splits: [PacedSplit] = []
        if let p = race.profile, p.count >= 2 {
            let perMeter = total / efd
            var cumulative = 0.0
            var km = 1
            var start = 0.0
            while start < race.distanceM - 1 {
                let end = min(race.distanceM, start + 1000)
                var cost = 0.0, climb = 0.0
                for (a, b) in zip(p, p.dropFirst()) {
                    let lo = max(start, a.distanceM * scale), hi = min(end, b.distanceM * scale)
                    guard hi > lo, b.distanceM > a.distanceM else { continue }
                    let grade = (b.altitudeM - a.altitudeM) / (b.distanceM - a.distanceM)
                    cost += (hi - lo) * costFactor(grade: grade)
                    climb += (hi - lo) * grade
                }
                let seconds = cost * perMeter
                cumulative += seconds
                splits.append(PacedSplit(km: km, distanceM: end - start, gradePct: climb / (end - start) * 100,
                                         paceSeconds: seconds / (end - start) * 1000, cumulativeSeconds: cumulative))
                km += 1
                start = end
            }
        }
        return RacePrediction(flatSeconds: flat, hillSeconds: hilly - flat, heatSeconds: total - hilly, totalSeconds: total,
                              heatSlowdownPct: heat * 100, dewPointC: dew, equivalentFlatM: efd, splits: splits, tooHot: tooHot)
    }
}

// MARK: - GPX del recorrido

/// Recorrido leído de un GPX: perfil cada 50 m, distancia y desnivel.
public struct Course: Sendable, Hashable {
    public var profile: [CoursePoint]
    public var distanceM: Double
    public var gainM: Double
    public var lossM: Double
    public var start: RaceLocation?
}

public enum GPXReader {
    /// Lee los puntos de pista o de ruta (`trkpt`/`rtept`) con su altitud.
    public static func course(from data: Data, name: String = "Salida") -> Course? {
        let reader = PointCollector()
        let parser = XMLParser(data: data)
        parser.delegate = reader
        guard parser.parse(), reader.points.count >= 2 else { return nil }
        var cumulative = [0.0]
        for (a, b) in zip(reader.points, reader.points.dropFirst()) {
            cumulative.append(cumulative.last! + Geo.distance(a.lat, a.lon, b.lat, b.lon))
        }
        let total = cumulative.last ?? 0
        guard total >= 500 else { return nil }
        // Altitud suavizada (5 puntos) y desnivel con histéresis de 2 m.
        let raw = reader.points.map(\.ele)
        let hasAltitude = raw.contains { $0 != nil }
        let smooth = RunSeriesBuilder.smooth(raw, window: 5)
        var gain = 0.0, loss = 0.0
        var ref: Double?
        for a in smooth.compactMap({ $0 }) {
            guard let r = ref else { ref = a; continue }
            if a - r >= 2 { gain += a - r; ref = a } else if r - a >= 2 { loss += r - a; ref = a }
        }
        // Perfil cada 50 m (interpolado).
        var profile: [CoursePoint] = []
        if hasAltitude {
            var j = 0
            var d = 0.0
            while d <= total {
                while j + 1 < cumulative.count && cumulative[j + 1] < d { j += 1 }
                let k = min(j + 1, cumulative.count - 1)
                let a0 = smooth[j] ?? smooth[k] ?? 0, a1 = smooth[k] ?? a0
                let span = cumulative[k] - cumulative[j]
                let alt = span > 0 ? a0 + (d - cumulative[j]) / span * (a1 - a0) : a0
                profile.append(CoursePoint(distanceM: d, altitudeM: alt))
                d += 50
            }
            if let last = profile.last, last.distanceM < total, let a = smooth.last ?? nil {
                profile.append(CoursePoint(distanceM: total, altitudeM: a))
            }
        }
        let first = reader.points[0]
        return Course(profile: profile, distanceM: total, gainM: gain, lossM: loss,
                      start: RaceLocation(name: name, latitude: first.lat, longitude: first.lon))
    }

    final class PointCollector: NSObject, XMLParserDelegate {
        var points: [(lat: Double, lon: Double, ele: Double?)] = []
        private var inPoint = false
        private var inEle = false
        private var text = ""

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                    attributes: [String: String] = [:]) {
            let local = name.split(separator: ":").last.map(String.init) ?? name
            if local == "trkpt" || local == "rtept", let lat = attributes["lat"].flatMap(Double.init), let lon = attributes["lon"].flatMap(Double.init) {
                points.append((lat, lon, nil))
                inPoint = true
            } else if local == "ele" && inPoint {
                inEle = true
                text = ""
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if inEle { text += string }
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            let local = name.split(separator: ":").last.map(String.init) ?? name
            if local == "ele", inEle {
                inEle = false
                if let v = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)), !points.isEmpty { points[points.count - 1].ele = v }
            } else if local == "trkpt" || local == "rtept" {
                inPoint = false
            }
        }
    }
}

// MARK: - Tiempo el día de la carrera (Open-Meteo, sin clave)

public struct RaceConditions: Sendable, Hashable {
    public var temperatureC: Double
    public var humidityPct: Double
}

/// Previsión (hasta 16 días) o clima de ese día en años anteriores, de Open-Meteo. Solo se envía la ciudad de la carrera.
public enum OpenMeteo {
    public static let forecastDays = 16

    public static func searchURL(_ query: String) -> URL? {
        var c = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")
        c?.queryItems = [URLQueryItem(name: "name", value: query), URLQueryItem(name: "count", value: "6"),
                         URLQueryItem(name: "language", value: "es"), URLQueryItem(name: "format", value: "json")]
        return c?.url
    }

    public static func places(from data: Data) -> [RaceLocation] {
        struct Response: Decodable {
            struct Place: Decodable {
                var name: String
                var latitude: Double
                var longitude: Double
                var country: String?
                var admin1: String?
            }
            var results: [Place]?
        }
        guard let r = try? JSONDecoder().decode(Response.self, from: data) else { return [] }
        return (r.results ?? []).map { p in
            let detail = [p.admin1, p.country].compactMap { $0 }.joined(separator: ", ")
            return RaceLocation(name: p.name, detail: detail.isEmpty ? nil : detail, latitude: p.latitude, longitude: p.longitude)
        }
    }

    static func url(_ base: String, _ loc: RaceLocation, day: LocalDate) -> URL? {
        var c = URLComponents(string: base)
        c?.queryItems = [URLQueryItem(name: "latitude", value: String(format: "%.4f", loc.latitude)),
                         URLQueryItem(name: "longitude", value: String(format: "%.4f", loc.longitude)),
                         URLQueryItem(name: "hourly", value: "temperature_2m,relative_humidity_2m"),
                         URLQueryItem(name: "timezone", value: "auto"),
                         URLQueryItem(name: "start_date", value: day.isoString), URLQueryItem(name: "end_date", value: day.isoString)]
        return c?.url
    }

    /// Previsión para ese día (si faltan 16 días o menos).
    public static func forecastURL(_ loc: RaceLocation, day: LocalDate) -> URL? {
        url("https://api.open-meteo.com/v1/forecast", loc, day: day)
    }

    /// Lo que hizo ese mismo día en un año pasado.
    public static func archiveURL(_ loc: RaceLocation, day: LocalDate) -> URL? {
        url("https://archive-api.open-meteo.com/v1/archive", loc, day: day)
    }

    /// Temperatura y humedad a la hora de la salida (hora local del sitio).
    public static func conditions(from data: Data, hour: Int) -> RaceConditions? {
        struct Response: Decodable {
            struct Hourly: Decodable {
                var time: [String]
                var temperature_2m: [Double?]
                var relative_humidity_2m: [Double?]
            }
            var hourly: Hourly?
        }
        guard let h = (try? JSONDecoder().decode(Response.self, from: data))?.hourly else { return nil }
        let suffix = String(format: "T%02d:00", hour)
        guard let i = h.time.firstIndex(where: { $0.hasSuffix(suffix) }), i < h.temperature_2m.count, i < h.relative_humidity_2m.count,
              let t = h.temperature_2m[i], let rh = h.relative_humidity_2m[i] else { return nil }
        return RaceConditions(temperatureC: t, humidityPct: rh)
    }

    /// Media de varias condiciones (el clima típico de ese día).
    public static func average(_ list: [RaceConditions]) -> RaceConditions? {
        guard !list.isEmpty else { return nil }
        let n = Double(list.count)
        return RaceConditions(temperatureC: list.reduce(0) { $0 + $1.temperatureC } / n, humidityPct: list.reduce(0) { $0 + $1.humidityPct } / n)
    }
}
