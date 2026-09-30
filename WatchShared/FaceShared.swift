import Foundation
import FaceKit

/// Lo último que mandó el iPhone, guardado en el App Group del reloj: lo lee la app y también las complicaciones.
enum FaceShared {
    static var url: URL? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "RecuperaAppGroup") as? String, !group.contains("$(") else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?.appendingPathComponent("faces.json")
    }

    static func load() -> WatchPayload? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return WatchPayload.decode(data)
    }

    static func save(_ data: Data) {
        guard let url else { return }
        try? data.write(to: url, options: .atomic)
    }
}
