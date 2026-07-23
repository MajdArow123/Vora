//
//  AppearanceSetting.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-22.
//

import SwiftUI

/// In-app color scheme override. Lives in UserDefaults rather than
/// SwiftData because it is a per-device preference, not profile data.
enum AppearanceSetting: String, CaseIterable, Identifiable {
    static let storageKey = "vora.appearance"

    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var iconName: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
        }
    }

    /// nil follows the iOS system setting.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
