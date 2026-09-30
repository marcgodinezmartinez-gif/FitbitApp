import Foundation
import MetricsKit
import Store

public struct GeoPoint: Codable, Sendable, Hashable {
    public var lat: Double
    public var lon: Double
    public var alt: Double?

    public init(lat: Double, lon: Double, alt: Double? = nil) {
        self.lat = lat
        self.lon = lon
        self.alt = alt
    }
}

/// Segmento propio (doc. 18 §8): un tramo que eliges de una carrera; la app busca tus pasadas en todas las demás.
public struct Segment: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var createdAt: Date
    /// Polilínea del tramo, un punto cada ~10 m.
    public var points: [GeoPoint]
    public var lengthM: Double
    public var elevationGainM: Double
    public var fromRunID: String?

    public var start: GeoPoint { points.first ?? GeoPoint(lat: 0, lon: 0) }
    public var end: GeoPoint { points.last ?? GeoPoint(lat: 0, lon: 0) }

    /// Pendiente media (%) de la salida a la llegada.
    public var gradePct: Double? {
        guard let a = points.first?.alt, let b = points.last?.alt, lengthM > 0 else { return nil }
        return (b - a) / lengthM * 100
    }
}

/// Una pasada por un segmento.
public struct SegmentEffort: Codable, Sendable, Hashable, Identifiable {
    public var segmentID: String
    public var runID: String
    public var start: Date
    public var seconds: Double
    public var distanceM: Double
    public var avgHR: Double?

    public var id: String { "\(segmentID)|\(runID)|\(Int(start.timeIntervalSince1970))" }
    public var pace: Double { distanceM > 0 ? seconds / distanceM * 1000 : 0 }
}

public enum SegmentMatcher {
    /// Distancia máxima a la salida y a la llegada del segmento, y al resto del tramo.
    static let endpointRadius = 30.0
    static let pathRadius = 40.0

    static func good(_ route: [RoutePoint]) -> [RoutePoint] { route.filter { ($0.horizontalAccuracy ?? 0) <= 50 } }

    static func cumulative(_ pts: [RoutePoint]) -> [Double] {
        var out = [0.0]
        for (a, b) in zip(pts, pts.dropFirst()) { out.append(out.last! + Geo.distance(a.latitude, a.longitude, b.latitude, b.longitude)) }
        return out
    }

    static func distance(_ p: RoutePoint, _ g: GeoPoint) -> Double { Geo.distance(p.latitude, p.longitude, g.lat, g.lon) }

    /// Crea un segmento con el tramo [fromM, toM] (metros desde la salida) de una carrera. Al menos 200 m.
    public static func make(name: String, route: [RoutePoint], fromM: Double, toM: Double, runID: String?,
                            id: String = UUID().uuidString, now: Date = Date()) -> Segment? {
        let pts = good(route)
        guard pts.count >= 2, toM - fromM >= 200 else { return nil }
        let cum = cumulative(pts)
        var points: [GeoPoint] = []
        var lastKept = -Double.infinity
        for (i, p) in pts.enumerated() where cum[i] >= fromM && cum[i] <= toM {
            if cum[i] - lastKept >= 10 || i == pts.count - 1 {
                points.append(GeoPoint(lat: p.latitude, lon: p.longitude, alt: p.altitude))
                lastKept = cum[i]
            }
        }
        // La llegada exacta aunque no toque el paso de 10 m.
        if let lastIndex = pts.indices.last(where: { cum[$0] <= toM }), let last = points.last,
           last.lat != pts[lastIndex].latitude || last.lon != pts[lastIndex].longitude {
            points.append(GeoPoint(lat: pts[lastIndex].latitude, lon: pts[lastIndex].longitude, alt: pts[lastIndex].altitude))
        }
        guard points.count >= 2 else { return nil }
        var length = 0.0
        for (a, b) in zip(points, points.dropFirst()) { length += Geo.distance(a.lat, a.lon, b.lat, b.lon) }
        guard length >= 200 else { return nil }
        var gain = 0.0
        var ref: Double?
        for alt in points.compactMap(\.alt) {
            guard let r = ref else { ref = alt; continue }
            if alt - r >= 2 { gain += alt - r; ref = alt } else if r - alt >= 2 { ref = alt }
        }
        return Segment(id: id, name: name, createdAt: now, points: points, lengthM: length, elevationGainM: gain, fromRunID: runID)
    }

    /// ¿Puede pasar la carrera por el segmento? (su recuadro contiene la salida y la llegada, con 150 m de margen).
    public static func mayPass(_ segment: Segment, bounds: [Double]?) -> Bool {
        guard let b = bounds, b.count == 4 else { return false }
        let m = 0.0015
        func inside(_ g: GeoPoint) -> Bool { g.lat >= b[0] - m && g.lat <= b[2] + m && g.lon >= b[1] - m && g.lon <= b[3] + m }
        return inside(segment.start) && inside(segment.end)
    }

    /// Pasadas por el segmento en su sentido: de la salida a la llegada recorriendo entre el 80 y el 130 % de su longitud y
    /// sin separarse del tramo (se toleran fallos del GPS en un 10 % de los puntos de control).
    public static func efforts(of segment: Segment, route: [RoutePoint], hr: [HRSample], runID: String) -> [SegmentEffort] {
        let pts = good(route)
        guard pts.count >= 2, segment.points.count >= 2 else { return [] }
        let cum = cumulative(pts)
        let checkpoints = self.checkpoints(segment)
        var out: [SegmentEffort] = []
        var i = 0
        while i < pts.count {
            guard distance(pts[i], segment.start) <= endpointRadius else { i += 1; continue }
            // El punto más cercano a la salida en este paso.
            var s = i
            while s + 1 < pts.count, distance(pts[s + 1], segment.start) < distance(pts[s], segment.start) { s += 1 }
            var best: Int?
            var bestD = Double.infinity
            var j = s + 1
            while j < pts.count, cum[j] - cum[s] <= 1.3 * segment.lengthM {
                if cum[j] - cum[s] >= 0.8 * segment.lengthM {
                    let d = distance(pts[j], segment.end)
                    if d <= endpointRadius && d < bestD {
                        bestD = d
                        best = j
                    }
                }
                j += 1
            }
            if let e = best, follows(checkpoints, pts[s...e]) {
                let from = pts[s].time, to = pts[e].time
                let beats = hr.filter { $0.time >= from && $0.time <= to }.map(\.bpm)
                out.append(SegmentEffort(segmentID: segment.id, runID: runID, start: from, seconds: to.timeIntervalSince(from),
                                         distanceM: cum[e] - cum[s], avgHR: beats.isEmpty ? nil : beats.reduce(0, +) / Double(beats.count)))
                i = e + 1
            } else {
                i = s + 1
            }
        }
        return out.filter { $0.seconds > 0 }
    }

    /// Puntos de control del tramo cada ~50 m (sin la salida ni la llegada).
    static func checkpoints(_ segment: Segment) -> [GeoPoint] {
        var out: [GeoPoint] = []
        var since = 0.0
        for (a, b) in zip(segment.points, segment.points.dropFirst()) {
            since += Geo.distance(a.lat, a.lon, b.lat, b.lon)
            if since >= 50 {
                out.append(b)
                since = 0
            }
        }
        if !out.isEmpty { out.removeLast() }
        return out
    }

    static func follows(_ checkpoints: [GeoPoint], _ slice: ArraySlice<RoutePoint>) -> Bool {
        guard !checkpoints.isEmpty else { return true }
        let misses = checkpoints.filter { c in !slice.contains { distance($0, c) <= pathRadius } }.count
        return Double(misses) <= 0.1 * Double(checkpoints.count)
    }
}

/// Segmentos guardados y sus pasadas.
public enum SegmentLibrary {
    public static func segments(db: AppDatabase) throws -> [Segment] {
        try db.segments(Segment.self).sorted { $0.createdAt < $1.createdAt }
    }

    public static func efforts(segmentID: String, db: AppDatabase) throws -> [SegmentEffort] {
        try db.segmentEfforts(SegmentEffort.self, segmentID: segmentID)
    }

    public static func efforts(runID: String, db: AppDatabase) throws -> [SegmentEffort] {
        try db.segmentEfforts(SegmentEffort.self, activityIDs: [runID])
    }

    /// Busca las pasadas en las carreras que aún no se han revisado para cada segmento (todas al crearlo; luego las nuevas).
    /// Solo lee la ruta de las que pasan cerca. Devuelve cuántas pasadas nuevas hay.
    @discardableResult
    public static func scan(db: AppDatabase, summaries: [RunSummary], runs: [String: FusedActivity]) throws -> Int {
        var found = 0
        for segment in try segments(db: db) {
            let scanned = try db.scannedActivityIDs(segmentID: segment.id)
            let pending = summaries.filter { !scanned.contains($0.id) }
            guard !pending.isEmpty else { continue }
            var rows: [(activityID: String, start: Date, seconds: Double, value: SegmentEffort)] = []
            for s in pending where SegmentMatcher.mayPass(segment, bounds: s.bounds) {
                guard let watch = runs[s.id]?.watchMember else { continue }
                let route = try db.route(activityID: watch.id)
                let hr = try db.hrSamples(source: .appleHealth, from: watch.start, to: watch.end)
                for e in SegmentMatcher.efforts(of: segment, route: route, hr: hr, runID: s.id) {
                    rows.append((s.id, e.start, e.seconds, e))
                }
            }
            try db.saveSegmentEfforts(rows, segmentID: segment.id, scanned: pending.map(\.id))
            found += rows.count
        }
        return found
    }

    /// Posición (1 = la mejor) de una pasada entre todas las del segmento.
    public static func rank(of effort: SegmentEffort, in all: [SegmentEffort]) -> Int {
        all.filter { $0.seconds < effort.seconds }.count + 1
    }
}
