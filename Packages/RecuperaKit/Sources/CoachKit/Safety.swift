import Foundation

/// Salvaguardas de contenido del Coach (doc. 06 §6, RL-02 y RL-34).
public enum CoachSafety {
    /// Minúsculas y sin tildes (comparación robusta en español).
    public static func normalize(_ text: String) -> String {
        let map: [Character: Character] = ["á": "a", "é": "e", "í": "i", "ó": "o", "ú": "u", "ü": "u", "ñ": "n", "à": "a", "è": "e",
                                           "ì": "i", "ò": "o", "ù": "u"]
        return String(text.lowercased().map { map[$0] ?? $0 })
    }

    // MARK: Filtro previo de urgencias

    /// Expresiones que indican una posible urgencia. Si aparecen, no se llama a ningún proveedor.
    static let urgencyPatterns: [String] = [
        "dolor en el pecho", "dolor de pecho", "dolor toracico", "me duele el pecho", "opresion en el pecho", "presion en el pecho",
        "me he desmayado", "me desmaye", "me estoy desmayando", "perdi el conocimiento", "perdida de conocimiento",
        "no puedo respirar", "me cuesta respirar", "dificultad para respirar", "me ahogo", "me estoy ahogando",
        "quiero morir", "quiero morirme", "no quiero vivir", "quitarme la vida", "suicid", "matarme", "autolesion",
        "hacerme dano", "cortarme las venas",
        "tengo un infarto", "estoy teniendo un infarto", "me esta dando un infarto", "sintomas de infarto",
        "tengo un ictus", "me esta dando un ictus", "sintomas de ictus", "se me ha dormido medio cuerpo", "se me ha torcido la cara",
        "no puedo mover el brazo", "no puedo hablar bien", "convulsion", "sobredosis", "toso sangre", "vomito sangre",
    ]

    public static func isUrgent(_ text: String) -> Bool {
        let t = normalize(text)
        return urgencyPatterns.contains { t.contains($0) }
    }

    public static let urgencyResponse = """
    Lo que describes puede ser una urgencia y aquí no puedo ayudarte con ello.

    • Si es una emergencia médica, llama ahora al **112**.
    • Si tienes pensamientos de hacerte daño, llama al **024** (atención a la conducta suicida: gratuito, confidencial y 24 horas).

    Habla también con un profesional sanitario. Cuando estés bien, aquí seguiré para ayudarte con tu sueño, recuperación y entrenamiento.
    """

    // MARK: Filtro posterior (RL-02)

    /// Términos que la app no usa para hablar de ti (nada de diagnósticos ni enfermedades).
    static let prohibitedTerms: [String] = [
        "diagnostic", "arritmia", "apnea", "fibrilacion", "presion arterial", "tension arterial", "hipertension",
        "covid", "infeccion", "detecta enfermedades", "enfermedad cardiaca", "cardiopatia", "taquicardia", "bradicardia",
    ]

    static let negations = ["no ", "ni ", "sin ", "nunca ", "tampoco "]

    /// Términos prohibidos presentes en una respuesta. Se permiten en frases negadas («no puedo hacer diagnósticos»).
    public static func violations(in text: String) -> [String] {
        let t = normalize(text)
        var found: [String] = []
        for term in prohibitedTerms {
            var searchStart = t.startIndex
            while let range = t.range(of: term, range: searchStart..<t.endIndex) {
                // Contexto desde el inicio de la frase hasta el término (máx. 60 caracteres).
                let sentenceStart = t[..<range.lowerBound].lastIndex(where: { ".!?\n;:".contains($0) }).map { t.index(after: $0) } ?? t.startIndex
                let windowStart = t.index(range.lowerBound, offsetBy: -60, limitedBy: sentenceStart) ?? sentenceStart
                let context = " " + String(t[windowStart..<range.lowerBound])
                if !negations.contains(where: { context.contains(" " + $0) }) {
                    found.append(term)
                    break
                }
                searchStart = range.upperBound
            }
        }
        return found
    }

    public static let safeReplacement = """
    Prefiero no responder a eso tal cual: no puedo interpretar síntomas ni hablar de enfermedades. Si te encuentras mal, \
    consulta a un profesional sanitario. Sí puedo ayudarte con tu sueño, tu recuperación y tu entrenamiento.
    """
}
