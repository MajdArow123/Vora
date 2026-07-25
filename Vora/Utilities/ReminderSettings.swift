//
//  ReminderSettings.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-25.
//

import Foundation

/// The three configurable smart reminders. Settings live in UserDefaults
/// rather than SwiftData because they are per-device preferences, not
/// profile data.
enum ReminderKind: String, CaseIterable, Identifiable {
    case meal
    case water
    case workout

    var id: String { rawValue }

    /// Bool, default false.
    var enabledKey: String { "vora.reminder.\(rawValue).enabled" }

    /// Int, minutes from midnight. Stored as minutes rather than a Date
    /// so the wall-clock time survives timezone and DST changes.
    var timeKey: String { "vora.reminder.\(rawValue).time" }

    /// Pending-notification identifier, unique per kind so each reminder
    /// can be cancelled independently.
    var notificationId: String { "vora.reminder.\(rawValue)" }

    var defaultMinutes: Int {
        switch self {
        case .meal: 12 * 60          // 12:00 PM
        case .water: 15 * 60         // 3:00 PM
        case .workout: 17 * 60 + 30  // 5:30 PM
        }
    }

    var displayName: String {
        switch self {
        case .meal: "Meal reminder"
        case .water: "Water reminder"
        case .workout: "Workout reminder"
        }
    }
}

/// Plain UserDefaults reader so NotificationService can evaluate reminder
/// settings without SwiftUI. Views bind to the same keys via @AppStorage.
struct ReminderSettings {
    static let weeklySummaryEnabledKey = "vora.reminder.weeklySummary.enabled"

    var defaults: UserDefaults = .standard

    func isEnabled(_ kind: ReminderKind) -> Bool {
        defaults.bool(forKey: kind.enabledKey)
    }

    func minutes(for kind: ReminderKind) -> Int {
        defaults.object(forKey: kind.timeKey) == nil
            ? kind.defaultMinutes
            : defaults.integer(forKey: kind.timeKey)
    }

    /// Defaults to true: the weekly summary predates this setting and was
    /// always scheduled, so absence of the key preserves that behavior.
    var weeklySummaryEnabled: Bool {
        defaults.object(forKey: Self.weeklySummaryEnabledKey) == nil
            ? true
            : defaults.bool(forKey: Self.weeklySummaryEnabledKey)
    }
}
