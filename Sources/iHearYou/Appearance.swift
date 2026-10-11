// iHearYou | Signature: i729
import SwiftUI
import AppKit

enum AppAppearance: String, CaseIterable {
    case system = "System", light = "Light", dark = "Dark"

    var colorScheme: ColorScheme? {
        switch self { case .system: return nil; case .light: return .light; case .dark: return .dark }
    }
    var appKitAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

enum Palette {
    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255,
                           green: CGFloat((value >> 8) & 255) / 255,
                           blue: CGFloat(value & 255) / 255, alpha: 1)
        })
    }
    static let background = adaptive(0xF7F7F8, 0x242728)
    static let sidebar = adaptive(0xEEEEF1, 0x1D2021)
    static let surface = adaptive(0xFFFFFF, 0x2D3032)
    static let ink = adaptive(0x22242A, 0xF5F5F7)
    static let secondary = adaptive(0x61616D, 0xB5B5BE)
    static let accent = adaptive(0x6345D0, 0xA491FF)
    static let line = adaptive(0xDADAE0, 0x3B3E40)
    static let clean = Color(red: 0.40, green: 0.85, blue: 0.71)
    static let signalBackground = Color(red: 0.09, green: 0.11, blue: 0.13)
    static let errorBackground = adaptive(0xFCE9E6, 0x4A2929)
}
