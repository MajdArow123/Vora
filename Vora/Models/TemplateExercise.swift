//
//  TemplateExercise.swift
//  Vora
//
//  Created by Majd Arow on 2026-11-01.
//

import Foundation
import SwiftData

/// One exercise in a WorkoutTemplate with its per-session targets.
/// Exactly one of `exerciseId` (library exercises) and `customName`
/// (exercises not in the library) is set.
@Model
final class TemplateExercise {
    @Attribute(.unique) var id: UUID
    /// Permanent ExerciseLibrary ID; the display name always comes from
    /// the library so renames carry over. nil for custom exercises.
    var exerciseId: String?
    /// The user's name for an exercise outside the library.
    var customName: String?
    var orderIndex: Int
    var targetSets: Int = 3
    var repRangeMin: Int = 8
    var repRangeMax: Int = 12
    /// Reps in reserve to aim for; nil means no target.
    var targetRIR: Int? = 2
    var restSeconds: Int = 90
    /// Links consecutive exercises into a superset; nil when unlinked. Same
    /// rules as `ExerciseLog.supersetGroup`.
    var supersetGroup: Int?

    var parent: WorkoutTemplate?

    init(
        id: UUID = UUID(),
        exerciseId: String?,
        customName: String? = nil,
        orderIndex: Int,
        targetSets: Int = 3,
        repRangeMin: Int = 8,
        repRangeMax: Int = 12,
        targetRIR: Int? = 2,
        restSeconds: Int? = nil,
        supersetGroup: Int? = nil
    ) {
        self.id = id
        self.exerciseId = exerciseId
        self.customName = customName
        self.orderIndex = orderIndex
        self.targetSets = targetSets
        self.repRangeMin = repRangeMin
        self.repRangeMax = repRangeMax
        self.targetRIR = targetRIR
        self.restSeconds = restSeconds ?? ExerciseLibrary.defaultRestSeconds(exerciseId: exerciseId)
        self.supersetGroup = supersetGroup
    }

    var displayName: String {
        TemplateExerciseSpec.displayName(exerciseId: exerciseId, customName: customName)
    }
}
