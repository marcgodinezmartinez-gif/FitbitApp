import Foundation

/// El tiempo de ahora donde está el reloj, de Open-Meteo (sin clave, doc. 18 §7). El reloj pide la ubicación solo si alguna
/// esfera enseña el tiempo.
public enum FaceWeatherService {
    /// Cada cuánto se vuelve a pedir.
    public static let refreshInterval: TimeInterval = 30 * 60

    public static func currentURL(latitude: Double, longitude: Double) -> URL? {
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        c?.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.3f", latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.3f", longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "timezone", value: "auto"),
        ]
        return c?.url
    }

    struct Response: Decodable {
        struct Current: Decodable {
            var temperature_2m: Double?
            var weather_code: Int?
            var is_day: Int?
        }
        var current: Current?
    }

    public static func parseCurrent(_ data: Data, now: Date) -> FaceWeather? {
        guard let r = try? JSONDecoder().decode(Response.self, from: data), let c = r.current, let t = c.temperature_2m,
              let code = c.weather_code else { return nil }
        return FaceWeather(temperatureC: t, code: code, isDay: (c.is_day ?? 1) == 1, updatedAt: now)
    }

    /// Símbolo SF y texto del código WMO.
    public static func describe(code: Int, isDay: Bool) -> (symbol: String, text: String) {
        switch code {
        case 0: return (isDay ? "sun.max.fill" : "moon.stars.fill", "Despejado")
        case 1, 2: return (isDay ? "cloud.sun.fill" : "cloud.moon.fill", "Poco nuboso")
        case 3: return ("cloud.fill", "Nublado")
        case 45, 48: return ("cloud.fog.fill", "Niebla")
        case 51, 53, 55, 56, 57: return ("cloud.drizzle.fill", "Llovizna")
        case 61, 63, 66, 80, 81: return ("cloud.rain.fill", "Lluvia")
        case 65, 67, 82: return ("cloud.heavyrain.fill", "Lluvia fuerte")
        case 71, 73, 75, 77, 85, 86: return ("cloud.snow.fill", "Nieve")
        case 95, 96, 99: return ("cloud.bolt.rain.fill", "Tormenta")
        default: return ("cloud.fill", "Nublado")
        }
    }
}
