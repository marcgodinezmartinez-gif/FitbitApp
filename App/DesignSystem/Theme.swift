import SwiftUI
import UIKit
import MetricsKit

// Tokens de color del doc. 11 §9.1 (oscuro primero, claro igual de cuidado).

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

extension Color {
    /// Color que cambia con el tema (claro u oscuro).
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }
}

enum Palette {
    static let recoveryHigh = Color(light: 0x157F3B, dark: 0x3DDC84)
    static let recoveryMedium = Color(light: 0x8A6A00, dark: 0xFFD23F)
    static let recoveryLow = Color(light: 0xB3261E, dark: 0xFF5C5C)
    static let strain = Color(light: 0x1D5FB8, dark: 0x4DA3FF)
    static let sleep = Color(light: 0x6B3FC8, dark: 0xB38CFF)
    static let stress = Color(light: 0xA65A00, dark: 0xFF9F43)
    static let bg = Color(light: 0xFFFFFF, dark: 0x07080A)
    static let surface = Color(light: 0xF4F5F7, dark: 0x121418)
    static let surfaceElevated = Color(light: 0xFFFFFF, dark: 0x1B1E24)
    static let textPrimary = Color(light: 0x0B0D10, dark: 0xF5F6F8)
    static let textSecondary = Color(light: 0x5B616B, dark: 0x9AA0AA)
    static let separator = Color(light: 0xE3E5E9, dark: 0x262A31)
    static let fitbit = Color(light: 0x00796B, dark: 0x4DD0C8)
    static let watch = Color(light: 0x0B0D10, dark: 0xF5F6F8)

    static func recovery(_ zone: RecoveryZone?) -> Color {
        switch zone {
        case .high?: return recoveryHigh
        case .medium?: return recoveryMedium
        case .low?: return recoveryLow
        case nil: return textSecondary
        }
    }

    static func recovery(score: Int?) -> Color {
        guard let score else { return textSecondary }
        return score >= 67 ? recoveryHigh : (score >= 34 ? recoveryMedium : recoveryLow)
    }

    /// Colores de las zonas de FC Z0…Z5.
    static let zones: [Color] = [
        Color(light: 0xC9CDD3, dark: 0x3A3F47), Color(light: 0x7FA7D9, dark: 0x6FA8E8), Color(light: 0x2E9E6A, dark: 0x3DDC84),
        Color(light: 0xC99A00, dark: 0xFFD23F), Color(light: 0xD96A00, dark: 0xFF9F43), Color(light: 0xC62828, dark: 0xFF5C5C),
    ]
}

extension RecoveryZone {
    /// Forma asociada a la zona (color + texto + forma, RNF-ACC-02).
    var symbol: String {
        switch self {
        case .high: return "circle.fill"
        case .medium: return "diamond.fill"
        case .low: return "triangle.fill"
        }
    }
}

extension Font {
    /// Cifras protagonistas: SF Pro Rounded con cifras tabulares.
    static func metric(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

extension DataSourceKind {
    var label: String {
        switch self {
        case .googleHealth: return "Fitbit Air"
        case .appleHealth: return "Apple Watch"
        case .manual: return "Manual"
        }
    }

    var symbol: String {
        switch self {
        case .googleHealth: return "circle.inset.filled"
        case .appleHealth: return "applewatch"
        case .manual: return "hand.draw"
        }
    }

    var tint: Color {
        switch self {
        case .googleHealth: return Palette.fitbit
        case .appleHealth: return Palette.watch
        case .manual: return Palette.textSecondary
        }
    }
}

enum Haptics {
    static func soft() { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
}
