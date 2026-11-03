//
//  TrainingProgram.swift
//  Vora
//
//  Created by Majd Arow on 2026-11-03.
//

import Foundation
import SwiftData

/// How "today's workout" is chosen. Raw values are persisted and never change.
nonisolated enum ScheduleMode: String, CaseIterable, Identifiable {
    /// By weekday, from the seven SplitDay rows.
    case weekly
    /// The next day of an ordered cycle, whatever the weekday.
    case cycle

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .weekly: "Weekly"
        case .cycle: "Cycle"
        }
    }
}

/// The user's schedule mode and cycle. At most one row exists, written the
/// first time they switch to cycle mode, so no row means weekly. The rules
/// are in docs/TRAINING_CYCLES.md.
@Model
final class TrainingProgram {
    @Attribute(.unique) var id: UUID
    /// `ScheduleMode.rawValue`. Stored raw so an unknown future mode never
    /// fails to decode.
    var scheduleModeRawValue: String
    /// The next day of the cycle. An ID rather than an index, so reordering,
    /// adding or removing days can't change which day is next.
    var currentDayID: UUID?
    /// The calendar day a current rest entry applies to; nil on training days.
    var restDay: Date?

    @Relationship(deleteRule: .cascade, inverse: \CycleDay.program)
    var days: [CycleDay]

    init(
        id: UUID = UUID(),
        mode: ScheduleMode = .weekly,
        currentDayID: UUID? = nil,
        restDay: Date? = nil,
        days: [CycleDay] = []
    ) {
        self.id = id
        self.scheduleModeRawValue = mode.rawValue
        self.currentDayID = currentDayID
        self.restDay = restDay
        self.days = days
    }

    var mode: ScheduleMode {
        get { ScheduleMode(rawValue: scheduleModeRawValue) ?? .weekly }
        set { scheduleModeRawValue = newValue.rawValue }
    }

    var orderedDays: [CycleDay] {
        days.sorted { $0.orderIndex < $1.orderIndex }
    }
}

/// One entry of the cycle: a training day with its own template, or a rest
/// entry with none.
@Model
final class CycleDay {
    @Attribute(.unique) var id: UUID
    var orderIndex: Int
    /// The user's name for the day; may be blank, which reads as "Day N".
    var title: String
    var muscleGroups: [String]
    var isRest: Bool

    var program: TrainingProgram?

    @Relationship(deleteRule: .cascade, inverse: \WorkoutTemplate.cycleDay)
    var template: WorkoutTemplate?

    init(
        id: UUID = UUID(),
        orderIndex: Int,
        title: String,
        muscleGroups: [String] = [],
        isRest: Bool = false,
        template: WorkoutTemplate? = nil
    ) {
        self.id = id
        self.orderIndex = orderIndex
        self.title = title
        self.muscleGroups = muscleGroups
        self.isRest = isRest
        self.template = template
    }
}
