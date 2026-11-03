//
//  CheckInSettings.swift
//  Vora
//
//  Created by Majd Arow on 2026-11-02.
//

import Foundation

/// The day of the week the check-in comes due. Lives in UserDefaults because
/// it is a per-device preference, not profile data. Raw values are Calendar
/// weekday numbers (Sunday = 1) and never change.
enum CheckInWeekday: Int, CaseIterable, Identifiable {
    static let storageKey = "vora.checkInWeekday"

    case monday = 2
    case tuesday = 3
    case wednesday = 4
    case thursday = 5
    case friday = 6
    case saturday = 7
    case sunday = 1

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .monday: "Monday"
        case .tuesday: "Tuesday"
        case .wednesday: "Wednesday"
        case .thursday: "Thursday"
        case .friday: "Friday"
        case .saturday: "Saturday"
        case .sunday: "Sunday"
        }
    }

    /// The stored day, or Monday when unset.
    static func current(in defaults: UserDefaults) -> CheckInWeekday {
        CheckInWeekday(rawValue: defaults.integer(forKey: storageKey)) ?? .monday
    }
}
