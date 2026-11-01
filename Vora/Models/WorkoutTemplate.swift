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

    var split: TrainingSplit? {
        TrainingSplit(rawValue: splitRawValue)
    }

    var orderedExercises: [TemplateExercise] {
        exercises.sorted { $0.orderIndex < $1.orderIndex }
    }
}
