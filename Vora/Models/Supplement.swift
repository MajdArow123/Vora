//
//  Supplement.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-26.
//

import Foundation
import SwiftData

enum SupplementTiming: String, Codable, CaseIterable {
    case morning
    case preWorkout
    case postWorkout
    case evening
    case anytime
}

@Model
final class Supplement {
    @Attribute(.unique) var id: UUID
    var name: String
    var dose: String
    var timing: SupplementTiming
    var reminderEnabled: Bool = false
    /// Minutes from midnight, matching the ReminderKind storage convention.
    var reminderMinutes: Int = 480
    /// Soft delete — logs keep their history when a supplement is removed.
    var isActive: Bool = true
    var orderIndex: Int
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        dose: String,
        timing: SupplementTiming = .anytime,
        reminderEnabled: Bool = false,
        reminderMinutes: Int = 480,
        isActive: Bool = true,
        orderIndex: Int,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.dose = dose
        self.timing = timing
        self.reminderEnabled = reminderEnabled
        self.reminderMinutes = reminderMinutes
        self.isActive = isActive
        self.orderIndex = orderIndex
        self.createdAt = createdAt
    }
}

extension SupplementTiming: Identifiable {
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .morning: "Morning"
        case .preWorkout: "Pre-workout"
        case .postWorkout: "Post-workout"
        case .evening: "Evening"
        case .anytime: "Anytime"
        }
    }

    var iconName: String {
        switch self {
        case .morning: "sunrise.fill"
        case .preWorkout: "bolt.fill"
        case .postWorkout: "figure.cooldown"
        case .evening: "moon.fill"
        case .anytime: "clock"
        }
    }

    /// Sensible reminder time for each timing, minutes from midnight.
    /// Pre-workout sits 30 minutes before the workout reminder default.
    var defaultReminderMinutes: Int {
        switch self {
        case .morning: 8 * 60
        case .preWorkout: 16 * 60 + 30
        case .postWorkout: 18 * 60 + 30
        case .evening: 21 * 60
        case .anytime: 8 * 60
        }
    }
}
