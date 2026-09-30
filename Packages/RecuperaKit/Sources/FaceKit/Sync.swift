import Foundation

/// Lo que el iPhone manda al reloj (WatchConnectivity): tus esferas y los datos del día. Va como JSON en el contexto de la
/// app, que siempre guarda solo lo último.
public struct WatchPayload: Codable, Sendable, Hashable {
    /// Versión del formato: si el reloj recibe una más nueva que la suya, se queda con lo que entienda.
    public static let currentVersion = 1
    /// Clave en el diccionario de WatchConnectivity.
    public static let key = "recupera-faces"

    public var version: Int
    public var library: FaceLibrary
    public var data: FaceData
    public var sentAt: Date

    public init(library: FaceLibrary, data: FaceData, sentAt: Date) {
        version = Self.currentVersion
        self.library = library
        self.data = data.phoneOnly
        self.sentAt = sentAt
    }

    public func encoded() throws -> Data {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        e.outputFormatting = [.sortedKeys]
        return try e.encode(self)
    }

    public static func decode(_ data: Data) -> WatchPayload? {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        guard var p = try? d.decode(WatchPayload.self, from: data) else { return nil }
        p.library.designs = p.library.designs.map { $0.normalized() }
        return p
    }
}
