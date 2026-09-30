import Foundation
import Observation
import WidgetKit
import FaceKit

/// Tus esferas y sus datos en el reloj: lo último que mandó el iPhone y lo que miden los sensores del reloj.
@MainActor
@Observable
final class FaceStore {
    static let shared = FaceStore()

    private(set) var library: FaceLibrary
    private(set) var phone: FaceData
    private(set) var receivedAt: Date?
    var sensors = FaceData()
    /// Modo noche de cada esfera (la corona lo cambia).
    var night: [String: Bool] = [:]

    init() {
        if let saved = FaceShared.load() {
            library = saved.library
            phone = saved.data
            receivedAt = saved.sentAt
        } else {
            library = FaceLibrary.starter()
            phone = FaceData()
        }
    }

    /// Lo del iPhone con lo medido en el reloj encima.
    var data: FaceData { phone.merged(withWatch: sensors) }

    /// Tus esferas (o las de fábrica si aún no has mandado ninguna).
    var designs: [FaceDesign] { library.designs.isEmpty ? FaceLibrary.starter().designs : library.designs }

    func isNight(_ design: FaceDesign) -> Bool { night[design.id] ?? design.startsInNightMode }

    func receive(_ payload: WatchPayload, raw: Data) {
        guard payload.sentAt >= (receivedAt ?? .distantPast) else { return }
        library = payload.library
        phone = payload.data
        receivedAt = payload.sentAt
        FaceShared.save(raw)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
