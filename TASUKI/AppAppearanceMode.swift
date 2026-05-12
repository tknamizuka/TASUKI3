import SwiftUI

enum AppAppearanceMode: String, CaseIterable, Identifiable {
    case device
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .device: return "デバイス"
        case .light: return "ライト"
        case .dark: return "ダーク"
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .device: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
