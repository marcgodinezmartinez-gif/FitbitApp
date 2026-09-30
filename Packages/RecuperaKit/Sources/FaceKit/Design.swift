import Foundation

// Esferas del Apple Watch (doc. 19). Apple no deja que las apps creen esferas del sistema: estas se dibujan dentro de la
// app de Recupera para el reloj. Aquí va solo el modelo (plantillas, diseño editable y catálogo); el dibujo está en FaceUI.

/// Estructura de una esfera: dónde va la hora, qué huecos tiene y qué biseles admite. Lo demás (colores, letra, qué dato
/// va en cada hueco) es de cada `FaceDesign`.
public enum FaceTemplate: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Hora grande arriba a la izquierda, bisel pegado al borde de la pantalla y cinco huecos (al estilo Modular Ultra).
    case ultraModular
    /// Agujas con bisel de brújula o de minutos, cuatro esquinas y tres subesferas (al estilo Wayfinder del Ultra).
    case wayfinder
    /// La recuperación en un anillo grande, con la carga y el sueño alrededor.
    case recovery
    /// Analógica clásica: bastones, números arábigos o romanos.
    case analog
    /// La hora enorme, a pantalla completa.
    case digital

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .ultraModular: return "Ultra modular"
        case .wayfinder: return "Explorador"
        case .recovery: return "Recuperación"
        case .analog: return "Clásica"
        case .digital: return "Digital XL"
        }
    }

    public var summary: String {
        switch self {
        case .ultraModular: return "Hora grande y los segundos corriendo por el borde, con cinco datos. Al estilo del Modular Ultra."
        case .wayfinder: return "Agujas con bisel de brújula o de minutos, cuatro esquinas y tres subesferas. Al estilo del Wayfinder."
        case .recovery: return "Tu recuperación en un anillo grande, con la carga y el sueño."
        case .analog: return "Agujas de siempre con bastones, números o romanos, y dos datos."
        case .digital: return "Las horas y los minutos enormes, con una línea de datos arriba y otra abajo."
        }
    }

    /// Huecos de la plantilla, en el orden en que se editan.
    public var slots: [FaceSlot] {
        switch self {
        case .ultraModular:
            return [FaceSlot(id: "topRight", kind: .circular, name: "Arriba a la derecha"),
                    FaceSlot(id: "center", kind: .rectangular, name: "Centro"),
                    FaceSlot(id: "bottomLeft", kind: .circular, name: "Abajo a la izquierda"),
                    FaceSlot(id: "bottomCenter", kind: .circular, name: "Abajo en el centro"),
                    FaceSlot(id: "bottomRight", kind: .circular, name: "Abajo a la derecha")]
        case .wayfinder:
            return [FaceSlot(id: "topLeft", kind: .corner, name: "Esquina de arriba a la izquierda"),
                    FaceSlot(id: "topRight", kind: .corner, name: "Esquina de arriba a la derecha"),
                    FaceSlot(id: "bottomLeft", kind: .corner, name: "Esquina de abajo a la izquierda"),
                    FaceSlot(id: "bottomRight", kind: .corner, name: "Esquina de abajo a la derecha"),
                    FaceSlot(id: "dialLeft", kind: .circular, name: "Subesfera izquierda"),
                    FaceSlot(id: "dialRight", kind: .circular, name: "Subesfera derecha"),
                    FaceSlot(id: "dialBottom", kind: .circular, name: "Subesfera de abajo")]
        case .recovery:
            return [FaceSlot(id: "top", kind: .inline, name: "Línea de arriba"),
                    FaceSlot(id: "bottomLeft", kind: .corner, name: "Abajo a la izquierda"),
                    FaceSlot(id: "bottomRight", kind: .corner, name: "Abajo a la derecha")]
        case .analog:
            return [FaceSlot(id: "top", kind: .circular, name: "Arriba"),
                    FaceSlot(id: "bottom", kind: .circular, name: "Abajo")]
        case .digital:
            return [FaceSlot(id: "top", kind: .inline, name: "Línea de arriba"),
                    FaceSlot(id: "bottom", kind: .inline, name: "Línea de abajo")]
        }
    }

    /// Biseles que admite (el primero es el de fábrica).
    public var bezels: [FaceBezel] {
        switch self {
        case .ultraModular: return [.seconds, .recovery, .strain, .steps, .none]
        case .wayfinder: return [.compass, .minutes, .recovery, .none]
        case .analog: return [.none, .minutes]
        case .recovery, .digital: return [.none]
        }
    }

    /// Si tiene agujas (y por tanto estilo de índices).
    public var hasHands: Bool { self == .wayfinder || self == .analog }

    /// Diseño de fábrica de la plantilla.
    public func defaultDesign(id: String = UUID().uuidString, now: Date = Date()) -> FaceDesign {
        var d = FaceDesign(id: id, name: name, template: self, accent: .ultraOrange, background: .black, font: .ultra, dial: .indices,
                           bezel: bezels.first ?? .none, use24h: true, showSeconds: true, startsInNightMode: false, slots: [:], updatedAt: now)
        switch self {
        case .ultraModular:
            d.slots = ["topRight": .date, "center": .summary, "bottomLeft": .recovery, "bottomCenter": .heartRate, "bottomRight": .activity]
        case .wayfinder:
            d.font = .rounded
            d.slots = ["topLeft": .recovery, "topRight": .date, "bottomLeft": .steps, "bottomRight": .battery,
                       "dialLeft": .heartRate, "dialRight": .strain, "dialBottom": .weather]
        case .recovery:
            d.accent = .green
            d.font = .rounded
            d.slots = ["top": .workout, "bottomLeft": .hrv, "bottomRight": .restingHR]
        case .analog:
            d.accent = .ultraOrange
            d.font = .serif
            d.dial = .arabic
            d.slots = ["top": .date, "bottom": .recovery]
        case .digital:
            d.accent = .cyan
            d.font = .condensed
            d.background = .glow(.cyan)
            d.showSeconds = false
            d.slots = ["top": .date, "bottom": .summary]
        }
        return d
    }
}

/// Tamaño de un hueco: como los de las complicaciones de Apple.
public enum SlotKind: String, Codable, Sendable, CaseIterable {
    case circular, corner, rectangular, inline
}

public struct FaceSlot: Sendable, Hashable, Identifiable {
    public var id: String
    public var kind: SlotKind
    public var name: String

    public init(id: String, kind: SlotKind, name: String) {
        self.id = id
        self.kind = kind
        self.name = name
    }
}

/// Qué dato va en un hueco.
public enum FaceComplication: String, Codable, Sendable, CaseIterable, Identifiable {
    case none
    case recovery, strain, sleep, summary, hrv, restingHR, bedtime
    case heartRate, steps, activity, battery, compass
    case workout, race, weather, date

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .none: return "Nada"
        case .recovery: return "Recuperación"
        case .strain: return "Carga del día"
        case .sleep: return "Sueño"
        case .summary: return "Recuperación, carga y sueño"
        case .hrv: return "Variabilidad (VFC)"
        case .restingHR: return "FC en reposo"
        case .bedtime: return "Hora de acostarte"
        case .heartRate: return "Pulso"
        case .steps: return "Pasos"
        case .activity: return "Anillos de actividad"
        case .battery: return "Batería"
        case .compass: return "Brújula"
        case .workout: return "Entreno de hoy"
        case .race: return "Cuenta atrás a tu carrera"
        case .weather: return "El tiempo"
        case .date: return "Fecha"
        }
    }

    /// Si cabe en un hueco de ese tamaño.
    public func fits(_ kind: SlotKind) -> Bool {
        switch self {
        case .none: return true
        case .summary, .workout: return kind == .rectangular || kind == .inline
        case .activity: return kind == .circular || kind == .rectangular
        case .compass: return kind == .circular || kind == .corner
        case .bedtime: return kind != .rectangular
        case .recovery, .strain, .sleep, .heartRate, .steps, .race, .weather: return true
        case .hrv, .restingHR, .battery, .date: return kind != .rectangular
        }
    }

    /// Necesita la ubicación del reloj (el tiempo) o su brújula.
    public var needsLocation: Bool { self == .weather || self == .compass }

    /// Lo mide el propio reloj (Salud en el Watch).
    public var needsHealth: Bool { self == .heartRate || self == .steps || self == .activity }

    /// Los datos que caben en un hueco, en el orden de los selectores.
    public static func options(for kind: SlotKind) -> [FaceComplication] {
        allCases.filter { $0.fits(kind) }
    }
}

/// Lo que recorre el borde (Ultra modular) o el aro de la esfera (Explorador, Clásica).
public enum FaceBezel: String, Codable, Sendable, CaseIterable, Identifiable {
    case none, seconds, minutes, compass, recovery, strain, steps

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .none: return "Sin bisel"
        case .seconds: return "Segundos"
        case .minutes: return "Minutos"
        case .compass: return "Brújula"
        case .recovery: return "Recuperación"
        case .strain: return "Carga del día"
        case .steps: return "Pasos"
        }
    }
}

/// Color en RGB (0–1), para guardarlo y mandarlo al reloj sin depender de SwiftUI.
public struct FaceColor: Codable, Sendable, Hashable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(_ red: Double, _ green: Double, _ blue: Double) {
        self.red = min(1, max(0, red))
        self.green = min(1, max(0, green))
        self.blue = min(1, max(0, blue))
    }

    /// «#FF5F00».
    public var hex: String {
        String(format: "#%02X%02X%02X", Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
    }

    public init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = Int(s, radix: 16) else { return nil }
        self.init(Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255)
    }

    /// Luminancia relativa (WCAG 2): para saber si encima va texto claro u oscuro.
    public var luminance: Double {
        func channel(_ c: Double) -> Double { c <= 0.039_28 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    /// El mismo color, más oscuro (`amount` 0–1 hacia el negro).
    public func darkened(_ amount: Double) -> FaceColor {
        let k = 1 - min(1, max(0, amount))
        return FaceColor(red * k, green * k, blue * k)
    }

    public static let ultraOrange = FaceColor(1.0, 0.37, 0.0)
    public static let green = FaceColor(0.24, 0.86, 0.52)
    public static let blue = FaceColor(0.30, 0.64, 1.0)
    public static let cyan = FaceColor(0.35, 0.85, 0.95)
    public static let white = FaceColor(0.95, 0.95, 0.95)
    public static let yellow = FaceColor(1.0, 0.82, 0.25)
    public static let red = FaceColor(1.0, 0.27, 0.23)
    public static let purple = FaceColor(0.70, 0.55, 1.0)
    public static let pink = FaceColor(1.0, 0.42, 0.62)
    public static let lime = FaceColor(0.75, 1.0, 0.2)
    /// El rojo del modo noche: todo en este color, como en el Ultra.
    public static let night = FaceColor(1.0, 0.12, 0.08)

    public static let presets: [NamedFaceColor] = [
        NamedFaceColor(name: "Naranja", color: .ultraOrange), NamedFaceColor(name: "Verde", color: .green),
        NamedFaceColor(name: "Azul", color: .blue), NamedFaceColor(name: "Cian", color: .cyan),
        NamedFaceColor(name: "Blanco", color: .white), NamedFaceColor(name: "Amarillo", color: .yellow),
        NamedFaceColor(name: "Rojo", color: .red), NamedFaceColor(name: "Morado", color: .purple),
        NamedFaceColor(name: "Rosa", color: .pink), NamedFaceColor(name: "Lima", color: .lime),
    ]
}

public struct NamedFaceColor: Sendable, Hashable, Identifiable {
    public var name: String
    public var color: FaceColor
    public var id: String { name }
}

/// Fondo de la esfera.
public enum FaceBackground: Codable, Sendable, Hashable {
    /// Negro puro (el que menos gasta con la pantalla OLED).
    case black
    /// Un color liso, oscurecido para que se lea encima.
    case solid(FaceColor)
    /// Un halo del color que se funde con el negro.
    case glow(FaceColor)

    public var name: String {
        switch self {
        case .black: return "Negro"
        case .solid: return "Color"
        case .glow: return "Halo"
        }
    }
}

/// Letra de la hora.
public enum FaceFont: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Ancha y rotunda, como la del Ultra.
    case ultra
    case rounded, condensed, mono, serif, thin

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .ultra: return "Ancha"
        case .rounded: return "Redondeada"
        case .condensed: return "Estrecha"
        case .mono: return "Monoespaciada"
        case .serif: return "Con remates"
        case .thin: return "Fina"
        }
    }
}

/// Marcas de las horas en las esferas de agujas.
public enum FaceDial: String, Codable, Sendable, CaseIterable, Identifiable {
    case indices, arabic, roman, minimal

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .indices: return "Bastones"
        case .arabic: return "Números"
        case .roman: return "Romanos"
        case .minimal: return "Mínima"
        }
    }

    /// Texto de la hora `h` (1–12) en la esfera; `nil` si se marca con un bastón.
    public func label(hour h: Int) -> String? {
        switch self {
        case .indices: return nil
        case .arabic: return "\(h)"
        case .roman: return ["XII", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI"][h % 12]
        case .minimal: return h % 3 == 0 ? "\(h)" : nil
        }
    }
}

/// Una esfera diseñada por ti: plantilla, colores, letra, bisel y qué dato va en cada hueco.
public struct FaceDesign: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var template: FaceTemplate
    public var accent: FaceColor
    public var background: FaceBackground
    public var font: FaceFont
    public var dial: FaceDial
    public var bezel: FaceBezel
    public var use24h: Bool
    public var showSeconds: Bool
    /// Arranca en rojo (modo noche); la corona lo cambia en el reloj.
    public var startsInNightMode: Bool
    /// Hueco → dato.
    public var slots: [String: FaceComplication]
    public var updatedAt: Date

    public init(id: String, name: String, template: FaceTemplate, accent: FaceColor, background: FaceBackground, font: FaceFont,
                dial: FaceDial, bezel: FaceBezel, use24h: Bool, showSeconds: Bool, startsInNightMode: Bool,
                slots: [String: FaceComplication], updatedAt: Date) {
        self.id = id
        self.name = name
        self.template = template
        self.accent = accent
        self.background = background
        self.font = font
        self.dial = dial
        self.bezel = bezel
        self.use24h = use24h
        self.showSeconds = showSeconds
        self.startsInNightMode = startsInNightMode
        self.slots = slots
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, name, template, accent, background, font, dial, bezel, use24h, showSeconds, startsInNightMode, slots, updatedAt
    }

    /// Tolera campos que falten o valores que esta versión no conozca (un dato nuevo de una versión posterior): se quedan
    /// los de fábrica de la plantilla.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let template = try c.decode(FaceTemplate.self, forKey: .template)
        let base = template.defaultDesign(id: try c.decode(String.self, forKey: .id), now: Date(timeIntervalSince1970: 0))
        func value<T: RawRepresentable>(_ key: CodingKeys, _ fallback: T) -> T where T.RawValue == String {
            (try? c.decodeIfPresent(String.self, forKey: key)).flatMap(T.init(rawValue:)) ?? fallback
        }
        id = base.id
        self.template = template
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? base.name
        accent = (try? c.decodeIfPresent(FaceColor.self, forKey: .accent)) ?? base.accent
        background = (try? c.decodeIfPresent(FaceBackground.self, forKey: .background)) ?? base.background
        font = value(.font, base.font)
        dial = value(.dial, base.dial)
        bezel = value(.bezel, base.bezel)
        use24h = (try? c.decodeIfPresent(Bool.self, forKey: .use24h)) ?? base.use24h
        showSeconds = (try? c.decodeIfPresent(Bool.self, forKey: .showSeconds)) ?? base.showSeconds
        startsInNightMode = (try? c.decodeIfPresent(Bool.self, forKey: .startsInNightMode)) ?? base.startsInNightMode
        let raw = (try? c.decodeIfPresent([String: String].self, forKey: .slots)) ?? [:]
        var slots = base.slots
        for (key, value) in raw { slots[key] = FaceComplication(rawValue: value) ?? base.slots[key] ?? FaceComplication.none }
        self.slots = slots
        updatedAt = (try? c.decodeIfPresent(Date.self, forKey: .updatedAt)) ?? base.updatedAt
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(template, forKey: .template)
        try c.encode(accent, forKey: .accent)
        try c.encode(background, forKey: .background)
        try c.encode(font, forKey: .font)
        try c.encode(dial, forKey: .dial)
        try c.encode(bezel, forKey: .bezel)
        try c.encode(use24h, forKey: .use24h)
        try c.encode(showSeconds, forKey: .showSeconds)
        try c.encode(startsInNightMode, forKey: .startsInNightMode)
        try c.encode(slots.mapValues(\.rawValue), forKey: .slots)
        try c.encode(updatedAt, forKey: .updatedAt)
    }

    /// Qué hay en un hueco (nada si no está puesto).
    public func complication(_ slotID: String) -> FaceComplication { slots[slotID] ?? .none }

    /// Lo que no encaje en la plantilla vuelve a lo de fábrica: un dato en un hueco que no lo admite, un bisel que no
    /// existe en esta plantilla, huecos que ya no están.
    public func normalized() -> FaceDesign {
        var d = self
        let base = template.defaultDesign(id: id, now: updatedAt)
        var fixed: [String: FaceComplication] = [:]
        for slot in template.slots {
            let c = slots[slot.id] ?? base.complication(slot.id)
            fixed[slot.id] = c.fits(slot.kind) ? c : base.complication(slot.id)
        }
        d.slots = fixed
        if !template.bezels.contains(bezel) { d.bezel = base.bezel }
        if d.name.trimmingCharacters(in: .whitespaces).isEmpty { d.name = template.name }
        return d
    }

    /// Todo lo que muestra (huecos y bisel).
    public var complications: Set<FaceComplication> {
        var all = Set(template.slots.map { complication($0.id) })
        switch bezel {
        case .recovery: all.insert(.recovery)
        case .strain: all.insert(.strain)
        case .steps: all.insert(.steps)
        case .compass: all.insert(.compass)
        default: break
        }
        all.remove(.none)
        return all
    }

    public var needsLocation: Bool { complications.contains { $0.needsLocation } }
    public var needsHealth: Bool { complications.contains { $0.needsHealth } }
}

/// Tus esferas, en el orden en que se pasan en el reloj.
public struct FaceLibrary: Codable, Sendable, Hashable {
    public var designs: [FaceDesign]

    public init(designs: [FaceDesign] = []) {
        self.designs = designs
    }

    /// Un diseño que no se entienda (una plantilla de una versión más nueva) se salta en vez de perder todos los demás.
    public init(from decoder: Decoder) throws {
        struct Lossy: Decodable {
            var design: FaceDesign?
            init(from decoder: Decoder) throws { design = try? FaceDesign(from: decoder) }
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        designs = ((try? c.decode([Lossy].self, forKey: .designs)) ?? []).compactMap(\.design)
    }

    /// Una de cada plantilla, para empezar.
    public static func starter(now: Date = Date()) -> FaceLibrary {
        FaceLibrary(designs: FaceTemplate.allCases.map { $0.defaultDesign(id: "default-\($0.rawValue)", now: now) })
    }

    public func design(_ id: String) -> FaceDesign? { designs.first { $0.id == id } }

    /// Guarda (o añade al final) el diseño, ya normalizado.
    public mutating func save(_ design: FaceDesign) {
        let d = design.normalized()
        if let i = designs.firstIndex(where: { $0.id == d.id }) { designs[i] = d } else { designs.append(d) }
    }

    public mutating func delete(_ id: String) {
        designs.removeAll { $0.id == id }
    }

    /// Una copia justo detrás del original, con «(copia)» en el nombre.
    @discardableResult
    public mutating func duplicate(_ id: String, newID: String = UUID().uuidString, now: Date = Date()) -> FaceDesign? {
        guard let i = designs.firstIndex(where: { $0.id == id }) else { return nil }
        var copy = designs[i]
        copy.id = newID
        copy.name += " (copia)"
        copy.updatedAt = now
        designs.insert(copy, at: i + 1)
        return copy
    }

    public mutating func move(from source: Int, to destination: Int) {
        guard designs.indices.contains(source) else { return }
        let d = designs.remove(at: source)
        designs.insert(d, at: min(max(0, destination), designs.count))
    }
}
