//
//  DesignSystem.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import SwiftUI

enum DesignSystem {
    enum Colors {
        /// Sage green — primary brand accent, tab bar and interactive tint.
        static let accent = Color(hex: "5C7A61")
        /// Warm off-white — app-wide screen background.
        static let background = Color(hex: "F7F4F0")
        /// Warm near-black — primary text.
        static let textPrimary = Color(hex: "2C2825")
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
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
