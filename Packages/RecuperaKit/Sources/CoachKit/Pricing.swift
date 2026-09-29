import Foundation

/// Precio publicado por millón de *tokens* (USD).
public struct ModelPrice: Sendable, Hashable {
    public var input: Double
    public var output: Double
    public var cacheWrite: Double
    public var cacheRead: Double

    public init(input: Double, output: Double, cacheWrite: Double, cacheRead: Double) {
        self.input = input
        self.output = output
        self.cacheWrite = cacheWrite
        self.cacheRead = cacheRead
    }

    public func cost(_ u: TokenUsage) -> Double {
        (Double(u.inputTokens) * input + Double(u.outputTokens) * output + Double(u.cacheWriteTokens) * cacheWrite
            + Double(u.cacheReadTokens) * cacheRead) / 1_000_000
    }
}

/// Modelo elegible en Ajustes (RF-COA-21).
public struct ModelOption: Sendable, Hashable, Identifiable {
    public var id: String
    public var provider: String
    public var name: String
    public var note: String

    public init(id: String, provider: String, name: String, note: String) {
        self.id = id
        self.provider = provider
        self.name = name
        self.note = note
    }
}

/// Catálogo de modelos y precios (doc. 06 §5 y §8). Revisar al cambiar de modelo: los precios cambian a menudo.
public enum ModelCatalog {
    public static let defaultAnthropicModel = "claude-opus-5-5"
    public static let defaultGeminiModel = "gemini-3.8-flash"

    public static let options: [ModelOption] = [
        ModelOption(id: "claude-opus-5-5", provider: "anthropic", name: "Claude Opus 5.5", note: "Recomendado · el más capaz"),
        ModelOption(id: "claude-sonnet-5-5", provider: "anthropic", name: "Claude Sonnet 5.5", note: "La mitad de precio"),
        ModelOption(id: "claude-haiku-4-5", provider: "anthropic", name: "Claude Haiku 4.5", note: "El más económico"),
        ModelOption(id: "gemini-3.8-flash", provider: "gemini", name: "Gemini 3.8 Flash", note: "Recomendado · muy económico"),
        ModelOption(id: "gemini-3.1-pro-preview", provider: "gemini", name: "Gemini 3.1 Pro (preview)", note: "Más capaz, en pruebas"),
    ]

    public static func options(for provider: String) -> [ModelOption] { options.filter { $0.provider == provider } }

    public static func displayName(_ model: String) -> String {
        if let o = options.first(where: { model.hasPrefix($0.id) }) { return o.name }
        return model
    }

    /// 1 de enero de 2027: Google duplica el precio de Gemini 3.8 Flash (doc. 06 §5).
    static let geminiPriceChange: Date = {
        var c = DateComponents()
        c.year = 2027; c.month = 1; c.day = 1
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: c)!
    }()

    public static func price(provider: String, model: String, on date: Date = Date()) -> ModelPrice {
        if provider == "gemini" {
            let factor = date >= geminiPriceChange ? 2.0 : 1.0
            if model.contains("pro") { return ModelPrice(input: 2, output: 12, cacheWrite: 2, cacheRead: 0.2) }
            // En Gemini la primera lectura del prefijo se paga completa (sin sobrecoste de escritura).
            return ModelPrice(input: 0.75 * factor, output: 3.75 * factor, cacheWrite: 0.75 * factor, cacheRead: 0.075 * factor)
        }
        switch model {
        case let m where m.hasPrefix("claude-opus-5-5"): return ModelPrice(input: 4, output: 20, cacheWrite: 5, cacheRead: 0.2)
        case let m where m.hasPrefix("claude-sonnet-5"): return ModelPrice(input: 2, output: 10, cacheWrite: 2.5, cacheRead: 0.2)
        case let m where m.hasPrefix("claude-haiku-4-5"): return ModelPrice(input: 1, output: 5, cacheWrite: 1.25, cacheRead: 0.1)
        case let m where m.hasPrefix("claude-fable"): return ModelPrice(input: 10, output: 50, cacheWrite: 12.5, cacheRead: 0.25)
        case let m where m.hasPrefix("claude-opus"): return ModelPrice(input: 5, output: 25, cacheWrite: 6.25, cacheRead: 0.5)
        default: return ModelPrice(input: 4, output: 20, cacheWrite: 5, cacheRead: 0.2)
        }
    }

    public static func cost(_ usage: TokenUsage, provider: String, model: String, on date: Date = Date()) -> Double {
        price(provider: provider, model: model, on: date).cost(usage)
    }

    /// Coste orientativo de una pregunta con los supuestos del doc. 06 §8: prefijo de ≈ 6 000 *tokens* escrito una vez
    /// y leído dos, ≈ 4 000 de entrada sin caché y ≈ 2 000 de salida (respuesta, herramientas y razonamiento).
    public static func estimatedCostPerQuestion(provider: String, model: String, on date: Date = Date()) -> Double {
        price(provider: provider, model: model, on: date)
            .cost(TokenUsage(inputTokens: 4_000, outputTokens: 2_000, cacheReadTokens: 12_000, cacheWriteTokens: 6_000))
    }
}
