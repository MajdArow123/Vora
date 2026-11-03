//
//  ProgressionSettings.swift
//  Vora
//
//  Created by Majd Arow on 2026-11-02.
//

import Foundation

/// How a new session fills in its weights. Lives in UserDefaults because it
/// is a per-device preference, not profile data. Raw values never change.
enum SessionPrefillMode: String, CaseIterable, Identifiable {
    static let storageKey = "vora.sessionPrefillMode"

    case smart
    case previous

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .smart: "Smart"
        case .previous: "Previous values"
        }
    }

    var detail: String {
        switch self {
        case .smart: "Suggests weight and reps from your recent sessions, and tells you why."
        case .previous: "Starts each set at the weight you used last time."
        }
    }
}

/// Whether compound lifts get generated warm-ups. Lives in UserDefaults like
/// the settings above.
enum SmartWarmUpSettings {
    static let storageKey = "vora.smartWarmUps"
    static let defaultEnabled = true
}

extension ProgressionMode {
    static let storageKey = "vora.progressionMode"

    var displayName: String {
        switch self {
        case .repsFirst: "Reps first"
        case .weightFirst: "Weight first"
        }
    }

    var detail: String {
        switch self {
        case .repsFirst: "Reach the top of your rep range on every set, then add weight."
        case .weightFirst: "Add weight as soon as you can stay in your rep range."
        }
    }
}
