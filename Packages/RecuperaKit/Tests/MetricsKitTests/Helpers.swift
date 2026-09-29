import Foundation
@testable import MetricsKit

/// Fecha UTC a partir de "2026-09-01T07:00".
func utc(_ s: String) -> Date {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f.date(from: s.count == 16 ? s + ":00Z" : s)!
}

func minutes(from start: Date, count: Int, bpm: Double, source: DataSourceKind, samples: Int = 0) -> [HRMinute] {
    (0..<count).map { HRMinute(minute: start.minuteEpoch + $0 * 60, bpmAvg: bpm, samples: samples, source: source) }
}

func session(_ id: String, _ start: String, _ end: String, source: DataSourceKind, kind: ActivityKind = .running,
             distance: Double? = nil, hasRoute: Bool = false, steps: Int? = nil) -> ActivitySession {
    ActivitySession(source: source, sourceRecordID: id, kind: kind, start: utc(start), end: utc(end), utcOffsetSeconds: 0,
                    distanceM: distance, steps: steps, hasRoute: hasRoute)
}
