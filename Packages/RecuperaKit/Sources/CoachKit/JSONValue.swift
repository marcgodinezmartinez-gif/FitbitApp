import Foundation

/// Valor JSON que conserva el orden de las claves y el literal de cada número.
///
/// El Coach guarda los turnos tal como los devuelve cada proveedor y los reenvía después. Para que el
/// prefijo de cada petición sea idéntico byte a byte (caché de *prompt* y razonamiento preservado de
/// Claude, doc. 06 §3) no vale `JSONSerialization`, que reordena las claves y reformatea los números.
public indirect enum JSONValue: Sendable, Hashable {
    case null
    case bool(Bool)
    case number(String)
    case string(String)
    case array([JSONValue])
    case object([Member])

    public struct Member: Sendable, Hashable {
        public var key: String
        public var value: JSONValue

        public init(_ key: String, _ value: JSONValue) {
            self.key = key
            self.value = value
        }
    }
}

// MARK: - Acceso

extension JSONValue {
    public subscript(key: String) -> JSONValue? {
        if case .object(let members) = self { return members.first { $0.key == key }?.value }
        return nil
    }

    public subscript(index: Int) -> JSONValue? {
        if case .array(let items) = self, items.indices.contains(index) { return items[index] }
        return nil
    }

    public var stringValue: String? { if case .string(let s) = self { return s }; return nil }
    public var doubleValue: Double? { if case .number(let n) = self { return Double(n) }; return nil }
    public var intValue: Int? {
        guard case .number(let n) = self else { return nil }
        if let i = Int(n) { return i }
        return Double(n).flatMap { $0.isFinite ? Int($0) : nil }
    }
    public var boolValue: Bool? { if case .bool(let b) = self { return b }; return nil }
    public var arrayValue: [JSONValue]? { if case .array(let a) = self { return a }; return nil }
    public var objectValue: [Member]? { if case .object(let m) = self { return m }; return nil }
    public var isNull: Bool { if case .null = self { return true }; return false }

    /// Devuelve una copia con la clave sustituida (en su sitio), añadida al final o eliminada (`nil`).
    public func setting(_ key: String, _ value: JSONValue?) -> JSONValue {
        guard case .object(var members) = self else { return self }
        if let i = members.firstIndex(where: { $0.key == key }) {
            if let value { members[i].value = value } else { members.remove(at: i) }
        } else if let value {
            members.append(Member(key, value))
        }
        return .object(members)
    }
}

// MARK: - Construcción

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral,
    ExpressibleByBooleanLiteral, ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral, ExpressibleByNilLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
    public init(integerLiteral value: Int) { self = .number(String(value)) }
    public init(floatLiteral value: Double) { self = .from(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, JSONValue)...) { self = .object(elements.map { Member($0.0, $0.1) }) }
    public init(nilLiteral: ()) { self = .null }
}

extension JSONValue {
    public static func from(_ value: Int) -> JSONValue { .number(String(value)) }

    /// Número con formato estable: enteros sin decimales; el resto, con la representación más corta.
    public static func from(_ value: Double) -> JSONValue {
        guard value.isFinite else { return .null }
        if value == value.rounded(), abs(value) < 1e15 { return .number(String(Int64(value))) }
        return .number("\(value)")
    }

    public static func from(_ value: String?) -> JSONValue { value.map { .string($0) } ?? .null }

    /// Número redondeado a `digits` decimales (los resultados de las herramientas van redondeados, doc. 06 §4).
    public static func rounded(_ value: Double?, _ digits: Int = 1) -> JSONValue {
        guard let value, value.isFinite else { return .null }
        let f = pow(10.0, Double(digits))
        return .from((value * f).rounded() / f)
    }

    public static func rounded(_ value: Int?) -> JSONValue { value.map { .from($0) } ?? .null }

    /// Objeto sin los miembros nulos (resultados más compactos).
    public static func compact(_ members: [(String, JSONValue)]) -> JSONValue {
        .object(members.filter { !$0.1.isNull }.map { Member($0.0, $0.1) })
    }
}

// MARK: - Serialización

extension JSONValue {
    /// JSON compacto y determinista (mismo valor ⇒ mismos bytes).
    public func serialized() -> String {
        var out = ""
        write(to: &out)
        return out
    }

    public var data: Data { Data(serialized().utf8) }

    func write(to out: inout String) {
        switch self {
        case .null: out += "null"
        case .bool(let b): out += b ? "true" : "false"
        case .number(let n): out += n
        case .string(let s): Self.writeString(s, to: &out)
        case .array(let items):
            out += "["
            for (i, item) in items.enumerated() {
                if i > 0 { out += "," }
                item.write(to: &out)
            }
            out += "]"
        case .object(let members):
            out += "{"
            for (i, m) in members.enumerated() {
                if i > 0 { out += "," }
                Self.writeString(m.key, to: &out)
                out += ":"
                m.value.write(to: &out)
            }
            out += "}"
        }
    }

    static func writeString(_ s: String, to out: inout String) {
        out += "\""
        for u in s.unicodeScalars {
            switch u {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            default:
                if u.value < 0x20 {
                    let hex = String(u.value, radix: 16)
                    out += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
                } else {
                    out.unicodeScalars.append(u)
                }
            }
        }
        out += "\""
    }
}

// MARK: - Conversión con Codable

extension JSONValue {
    /// Convierte un valor `Encodable` (claves ordenadas, fechas en segundos) en `JSONValue`.
    public init<T: Encodable>(encoding value: T) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        self = try JSONValue.parse(encoder.encode(value))
    }

    public func decode<T: Decodable>(_ type: T.Type) throws -> T {
        try JSONDecoder().decode(T.self, from: data)
    }
}

// MARK: - Análisis sintáctico

public struct JSONParseError: Error, Sendable, CustomStringConvertible {
    public var message: String
    public var offset: Int
    public var description: String { "JSON no válido (posición \(offset)): \(message)" }
}

extension JSONValue {
    public static func parse(_ string: String) throws -> JSONValue { try parse(bytes: Array(string.utf8)) }
    public static func parse(_ data: Data) throws -> JSONValue { try parse(bytes: [UInt8](data)) }

    static func parse(bytes: [UInt8]) throws -> JSONValue {
        var p = JSONByteParser(bytes: bytes)
        p.skipWhitespace()
        let value = try p.value(depth: 0)
        p.skipWhitespace()
        guard p.index == bytes.count else { throw p.error("sobra contenido tras el valor") }
        return value
    }
}

private struct JSONByteParser {
    let bytes: [UInt8]
    var index = 0

    init(bytes: [UInt8]) { self.bytes = bytes }

    func error(_ message: String) -> JSONParseError { JSONParseError(message: message, offset: index) }

    var current: UInt8? { index < bytes.count ? bytes[index] : nil }

    mutating func skipWhitespace() {
        while let c = current, c == 0x20 || c == 0x0A || c == 0x0D || c == 0x09 { index += 1 }
    }

    mutating func value(depth: Int) throws -> JSONValue {
        guard depth < 200 else { throw error("anidamiento excesivo") }
        guard let c = current else { throw error("fin inesperado") }
        switch c {
        case UInt8(ascii: "{"): return try object(depth: depth)
        case UInt8(ascii: "["): return try array(depth: depth)
        case UInt8(ascii: "\""): return .string(try string())
        case UInt8(ascii: "t"): try literal("true"); return .bool(true)
        case UInt8(ascii: "f"): try literal("false"); return .bool(false)
        case UInt8(ascii: "n"): try literal("null"); return .null
        default: return try number()
        }
    }

    mutating func literal(_ word: String) throws {
        let w = Array(word.utf8)
        guard index + w.count <= bytes.count, Array(bytes[index..<(index + w.count)]) == w else { throw error("se esperaba \(word)") }
        index += w.count
    }

    mutating func object(depth: Int) throws -> JSONValue {
        index += 1
        var members: [JSONValue.Member] = []
        skipWhitespace()
        if current == UInt8(ascii: "}") { index += 1; return .object(members) }
        while true {
            skipWhitespace()
            guard current == UInt8(ascii: "\"") else { throw error("se esperaba una clave") }
            let key = try string()
            skipWhitespace()
            guard current == UInt8(ascii: ":") else { throw error("se esperaba «:»") }
            index += 1
            skipWhitespace()
            members.append(JSONValue.Member(key, try value(depth: depth + 1)))
            skipWhitespace()
            if current == UInt8(ascii: ",") { index += 1; continue }
            if current == UInt8(ascii: "}") { index += 1; return .object(members) }
            throw error("se esperaba «,» o «}»")
        }
    }

    mutating func array(depth: Int) throws -> JSONValue {
        index += 1
        var items: [JSONValue] = []
        skipWhitespace()
        if current == UInt8(ascii: "]") { index += 1; return .array(items) }
        while true {
            skipWhitespace()
            items.append(try value(depth: depth + 1))
            skipWhitespace()
            if current == UInt8(ascii: ",") { index += 1; continue }
            if current == UInt8(ascii: "]") { index += 1; return .array(items) }
            throw error("se esperaba «,» o «]»")
        }
    }

    mutating func number() throws -> JSONValue {
        let start = index
        func isDigit(_ c: UInt8?) -> Bool { c.map { $0 >= 0x30 && $0 <= 0x39 } ?? false }
        if current == UInt8(ascii: "-") { index += 1 }
        guard isDigit(current) else { throw error("número no válido") }
        while isDigit(current) { index += 1 }
        if current == UInt8(ascii: ".") {
            index += 1
            guard isDigit(current) else { throw error("número no válido") }
            while isDigit(current) { index += 1 }
        }
        if current == UInt8(ascii: "e") || current == UInt8(ascii: "E") {
            index += 1
            if current == UInt8(ascii: "+") || current == UInt8(ascii: "-") { index += 1 }
            guard isDigit(current) else { throw error("número no válido") }
            while isDigit(current) { index += 1 }
        }
        return .number(String(decoding: bytes[start..<index], as: UTF8.self))
    }

    mutating func string() throws -> String {
        index += 1 // comilla inicial
        var buffer: [UInt8] = []
        while true {
            guard let c = current else { throw error("cadena sin cerrar") }
            index += 1
            switch c {
            case UInt8(ascii: "\""):
                return String(decoding: buffer, as: UTF8.self)
            case UInt8(ascii: "\\"):
                guard let e = current else { throw error("escape incompleto") }
                index += 1
                switch e {
                case UInt8(ascii: "\""): buffer.append(0x22)
                case UInt8(ascii: "\\"): buffer.append(0x5C)
                case UInt8(ascii: "/"): buffer.append(0x2F)
                case UInt8(ascii: "b"): buffer.append(0x08)
                case UInt8(ascii: "f"): buffer.append(0x0C)
                case UInt8(ascii: "n"): buffer.append(0x0A)
                case UInt8(ascii: "r"): buffer.append(0x0D)
                case UInt8(ascii: "t"): buffer.append(0x09)
                case UInt8(ascii: "u"):
                    var code = try hex4()
                    if (0xD800...0xDBFF).contains(code), current == UInt8(ascii: "\\"),
                       index + 1 < bytes.count, bytes[index + 1] == UInt8(ascii: "u") {
                        let save = index
                        index += 2
                        let low = try hex4()
                        if (0xDC00...0xDFFF).contains(low) {
                            code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
                        } else {
                            index = save
                        }
                    }
                    let scalar = Unicode.Scalar(code) ?? "\u{FFFD}"
                    buffer.append(contentsOf: Array(String(Character(scalar)).utf8))
                default:
                    throw error("escape no válido")
                }
            default:
                buffer.append(c)
            }
        }
    }

    mutating func hex4() throws -> UInt32 {
        guard index + 4 <= bytes.count, let v = UInt32(String(decoding: bytes[index..<(index + 4)], as: UTF8.self), radix: 16) else {
            throw error("escape \\u no válido")
        }
        index += 4
        return v
    }
}
