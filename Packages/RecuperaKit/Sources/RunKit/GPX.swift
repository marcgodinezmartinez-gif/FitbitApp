import Foundation
import Store

/// Exporta una carrera a GPX 1.1 con FC y cadencia (extensión TrackPointExtension de Garmin), para llevarla a otras apps.
public enum GPXWriter {
    public static func gpx(name: String, route: [RoutePoint], series: RunSeries?) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        var lines: [String] = [
            #"<?xml version="1.0" encoding="UTF-8"?>"#,
            #"<gpx version="1.1" creator="Recupera" xmlns="http://www.topografix.com/GPX/1/1" "#
                + #"xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v1">"#,
            "  <metadata><name>\(escape(name))</name>\(route.first.map { "<time>\(iso.string(from: $0.time))</time>" } ?? "")</metadata>",
            "  <trk><name>\(escape(name))</name><type>running</type><trkseg>",
        ]
        for p in route.sorted(by: { $0.time < $1.time }) {
            var point = #"    <trkpt lat="\#(String(format: "%.7f", p.latitude))" lon="\#(String(format: "%.7f", p.longitude))">"#
            if let alt = p.altitude { point += "<ele>\(String(format: "%.1f", alt))</ele>" }
            point += "<time>\(iso.string(from: p.time))</time>"
            if let s = series, s.count > 0 {
                let i = s.index(at: p.time)
                var ext = ""
                if let hr = s.hr[i] { ext += "<gpxtpx:hr>\(Int(hr.rounded()))</gpxtpx:hr>" }
                // En GPX la cadencia de carrera va en ciclos por minuto (la mitad de los pasos).
                if let cad = s.cadence[i] { ext += "<gpxtpx:cad>\(Int((cad / 2).rounded()))</gpxtpx:cad>" }
                if !ext.isEmpty { point += "<extensions><gpxtpx:TrackPointExtension>\(ext)</gpxtpx:TrackPointExtension></extensions>" }
            }
            lines.append(point + "</trkpt>")
        }
        lines += ["  </trkseg></trk>", "</gpx>"]
        return lines.joined(separator: "\n")
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}
