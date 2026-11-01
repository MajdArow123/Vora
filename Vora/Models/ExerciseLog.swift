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

    @Relationship(deleteRule: .cascade, inverse: \SetEntry.parent)
    var sets: [SetEntry]

    var parent: WorkoutSession?

    init(
        id: UUID = UUID(),
        exerciseName: String,
        exerciseId: String? = nil,
        muscleGroups: [String] = [],
        orderIndex: Int,
        sets: [SetEntry] = []
    ) {
        self.id = id
        self.exerciseName = exerciseName
        self.exerciseId = exerciseId
        self.muscleGroups = muscleGroups
        self.orderIndex = orderIndex
        self.sets = sets
    }
}
