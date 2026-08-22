// Adapted from Clipfield (MIT, Copyright 2026 Alex Jolley)

import SwiftUI

/// Selectable accent colors. `system` follows the macOS accent color.
enum AccentTheme: String, Codable, CaseIterable, Identifiable {
    case system, blue, purple, indigo, pink, red, orange, green, teal

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .system: return .accentColor
        case .blue: return .blue
        case .purple: return .purple
        case .indigo: return .indigo
        case .pink: return .pink
        case .red: return .red
        case .orange: return .orange
        case .green: return .green
        case .teal: return .teal
        }
    }

    var label: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

/// Light / Dark / follow-system appearance.
enum AppColorScheme: String, Codable, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }
    var label: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

    /// `nil` means "follow the system", matching `View.preferredColorScheme`.
    var swiftUI: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
