//
//  DesignSystem.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import SwiftUI
import UIKit

enum DesignSystem {
    /// Warm palette in both appearances: the light side matches the PRD
    /// hex values; the dark side keeps the same warm hue families at
    /// dark-appropriate lightness, following the iOS system setting.
    enum Colors {
        /// Sage green — primary brand accent, tab bar and interactive tint.
        static let accent = Color.adaptive(light: "5C7A61", dark: "7E9C84")
        /// Warm off-white / warm near-black — app-wide screen background.
        static let background = Color.adaptive(light: "F7F4F0", dark: "191715")
        /// Primary text.
        static let textPrimary = Color.adaptive(light: "2C2825", dark: "EFEBE6")
        /// Secondary text.
        static let textSecondary = Color.adaptive(light: "8A857E", dark: "9B958D")
        /// Card surfaces.
        static let card = Color.adaptive(light: "FFFFFF", dark: "24211E")
        /// Macro colors: protein shares the brand sage.
        static let macroProtein = Color.adaptive(light: "5C7A61", dark: "7E9C84")
        static let macroCarbs = Color.adaptive(light: "7EA8C0", dark: "8FB9D1")
        static let macroFat = Color.adaptive(light: "C4996B", dark: "D3AC7F")
        /// Semantic deltas: progress toward a goal vs away from it.
        static let positive = Color.adaptive(light: "4C8A5A", dark: "6FAF7D")
        static let negative = Color.adaptive(light: "B4574E", dark: "C97A72")
        /// Amber — recoverable-problem states (offline, degraded lookups).
        static let warning = Color.adaptive(light: "B07E3A", dark: "D0A05F")
    }

    enum Typography {
        static let screenTitle = Font.system(.largeTitle, weight: .bold)
        static let title = Font.system(.title2, weight: .semibold)
        static let headline = Font.system(.headline, weight: .semibold)
        static let body = Font.system(.body)
        static let caption = Font.system(.caption)
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
    }

    enum CornerRadius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 20
    }
}

extension Color {
    /// Creates a color from a 6-digit RGB hex string, e.g. "5C7A61".
    init(hex: String) {
        self.init(uiColor: UIColor(hex: hex))
    }

    /// A dynamic color that resolves per the system light/dark setting.
    static func adaptive(light: String, dark: String) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }
}

extension UIColor {
    /// Creates a color from a 6-digit RGB hex string, e.g. "5C7A61".
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        self.init(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}
