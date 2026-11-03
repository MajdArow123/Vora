//
//  ExerciseLog.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import Foundation
import SwiftData

@Model
final class ExerciseLog {
    @Attribute(.unique) var id: UUID
    var exerciseName: String
    /// Permanent ExerciseLibrary ID. nil for custom exercises, and for
    /// pre-V2 rows until ExerciseIDBackfill fills them.
    var exerciseId: String?
    var muscleGroups: [String]
    var orderIndex: Int
    /// Targets this session was done under. All nil for exercises added
    /// mid-session and for pre-V6 rows, whose real targets are unknown.
    var repRangeMin: Int?
    var repRangeMax: Int?
    var targetRIR: Int?
    var targetSets: Int?

    @Relationship(deleteRule: .cascade, inverse: \SetEntry.parent)
    var sets: [SetEntry]

    var parent: WorkoutSession?

    init(
        id: UUID = UUID(),
        exerciseName: String,
        exerciseId: String? = nil,
        muscleGroups: [String] = [],
        orderIndex: Int,
        targets: TemplateTargets? = nil,
        sets: [SetEntry] = []
    ) {
        self.id = id
        self.exerciseName = exerciseName
        self.exerciseId = exerciseId
        self.muscleGroups = muscleGroups
        self.orderIndex = orderIndex
        self.repRangeMin = targets?.repRangeMin
        self.repRangeMax = targets?.repRangeMax
        self.targetRIR = targets?.targetRIR
        self.targetSets = targets?.targetSets
        self.sets = sets
    }
}

extension ExerciseLog {
    /// The targets this session was done under; nil when not recorded.
    /// A snapshot needs its rep range and set count; targetRIR can be nil.
    var targetSnapshot: TemplateTargets? {
        guard let repRangeMin, let repRangeMax, let targetSets else { return nil }
        return TemplateTargets(
            targetSets: targetSets,
            repRangeMin: repRangeMin,
            repRangeMax: repRangeMax,
            targetRIR: targetRIR
        )
    }
}
