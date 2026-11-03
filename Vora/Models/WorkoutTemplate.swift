//
//  WorkoutTemplate.swift
//  Vora
//
//  Created by Majd Arow on 2026-11-01.
//

import Foundation
import SwiftData

/// The user's saved exercise plan for one weekday slot of a split. A slot
/// without a row uses the built-in defaults from WorkoutTemplateService,
/// so a row's presence means the template is customized. At most one row
/// exists per (split, dayIndex); WorkoutTemplateService enforces that.
/// A cycle day's template is reached through `cycleDay` instead, and its
/// reserved split and day index keep weekly slot lookups from matching it.
@Model
final class WorkoutTemplate {
    @Attribute(.unique) var id: UUID
    /// `TrainingSplit.rawValue`. Stored raw so an unknown future split
    /// never fails to decode.
    var splitRawValue: String
    /// 0 = Monday, matching SplitDay.dayIndex.
    var dayIndex: Int
    var name: String

    @Relationship(deleteRule: .cascade, inverse: \TemplateExercise.parent)
    var exercises: [TemplateExercise]

    /// Set on a cycle day's template; nil on weekly slots.
    var cycleDay: CycleDay?

    static let cycleSplitRawValue = "cycle"
    static let cycleDayIndex = -1

    init(
        id: UUID = UUID(),
        split: TrainingSplit,
        dayIndex: Int,
        name: String,
        exercises: [TemplateExercise] = []
    ) {
        self.id = id
        self.splitRawValue = split.rawValue
        self.dayIndex = dayIndex
        self.name = name
        self.exercises = exercises
    }

    /// A template for a cycle day, independent of every weekly slot.
    init(id: UUID = UUID(), cycleName name: String, exercises: [TemplateExercise] = []) {
        self.id = id
        self.splitRawValue = Self.cycleSplitRawValue
        self.dayIndex = Self.cycleDayIndex
        self.name = name
        self.exercises = exercises
    }

    var split: TrainingSplit? {
        TrainingSplit(rawValue: splitRawValue)
    }

    var orderedExercises: [TemplateExercise] {
        exercises.sorted { $0.orderIndex < $1.orderIndex }
    }
}
