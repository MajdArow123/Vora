//
//  SchemaV5.swift
//  Vora
//
//  Created by Majd Arow on 2026-11-02.
//

import Foundation
import SwiftData

/// Adds the optional loading inventory to GymProfile: bars, plates, and the
/// dumbbell and machine steps. Existing rows are filled after the store
/// opens by `GymInventoryBackfill`. Models a later version changed are frozen
/// below (see docs/MIGRATIONS.md).
nonisolated enum SchemaV5: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(5, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            UserProfile.self,
            FoodEntry.self,
            CustomFood.self,
            SchemaV5.WorkoutSession.self,
            SchemaV5.ExerciseLog.self,
            SchemaV5.SetEntry.self,
            WeightEntry.self,
            BodyMeasurement.self,
            WaterEntry.self,
            CardioEntry.self,
            SplitDay.self,
            SavedMeal.self,
            SavedMealItem.self,
            Recipe.self,
            RecipeIngredient.self,
            Supplement.self,
            SupplementLog.self,
            GymProfile.self,
            WorkoutTemplate.self,
            TemplateExercise.self,
        ]
    }
}

// Verbatim copies of the live workout cluster as of SchemaV5. Do not edit.
extension SchemaV5 {
    @Model
    final class WorkoutSession {
        @Attribute(.unique) var id: UUID
        var date: Date
        var sessionName: String
        var durationSeconds: Int
        var totalVolumeKg: Double
        var notes: String
        /// UUID of the workout written to HealthKit. nil when none was written,
        /// and for rows saved before SchemaV4; deletion then matches on times.
        var healthKitWorkoutID: UUID?

        @Relationship(deleteRule: .cascade, inverse: \ExerciseLog.parent)
        var exercises: [ExerciseLog]

        init(
            id: UUID = UUID(),
            date: Date,
            sessionName: String,
            durationSeconds: Int = 0,
            totalVolumeKg: Double = 0,
            notes: String = "",
            healthKitWorkoutID: UUID? = nil,
            exercises: [ExerciseLog] = []
        ) {
            self.id = id
            self.date = date
            self.sessionName = sessionName
            self.durationSeconds = durationSeconds
            self.totalVolumeKg = totalVolumeKg
            self.notes = notes
            self.healthKitWorkoutID = healthKitWorkoutID
            self.exercises = exercises
        }
    }

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

    @Model
    final class SetEntry {
        @Attribute(.unique) var id: UUID
        var setNumber: Int
        var weightKg: Double
        var reps: Int
        var isCompleted: Bool
        /// Reps in reserve, 0–5: 0 means failure, 5 means five or more. nil
        /// means not logged, which is different from 0.
        var rir: Int?

        var parent: ExerciseLog?

        init(
            id: UUID = UUID(),
            setNumber: Int,
            weightKg: Double,
            reps: Int,
            isCompleted: Bool = false,
            rir: Int? = nil
        ) {
            self.id = id
            self.setNumber = setNumber
            self.weightKg = weightKg
            self.reps = reps
            self.isCompleted = isCompleted
            self.rir = rir
        }
    }
}

// Verbatim copies of the live template cluster as of SchemaV5, with
// main-actor helpers left out of the initializers. Do not edit.
extension SchemaV5 {
    @Model
    final class WorkoutTemplate {
        @Attribute(.unique) var id: UUID
        var splitRawValue: String
        var dayIndex: Int
        var name: String

        @Relationship(deleteRule: .cascade, inverse: \TemplateExercise.parent)
        var exercises: [TemplateExercise]

        init(
            id: UUID = UUID(),
            splitRawValue: String,
            dayIndex: Int,
            name: String,
            exercises: [TemplateExercise] = []
        ) {
            self.id = id
            self.splitRawValue = splitRawValue
            self.dayIndex = dayIndex
            self.name = name
            self.exercises = exercises
        }
    }

    @Model
    final class TemplateExercise {
        @Attribute(.unique) var id: UUID
        var exerciseId: String?
        var customName: String?
        var orderIndex: Int
        var targetSets: Int = 3
        var repRangeMin: Int = 8
        var repRangeMax: Int = 12
        var targetRIR: Int? = 2
        var restSeconds: Int = 90

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
            restSeconds: Int = 90
        ) {
            self.id = id
            self.exerciseId = exerciseId
            self.customName = customName
            self.orderIndex = orderIndex
            self.targetSets = targetSets
            self.repRangeMin = repRangeMin
            self.repRangeMax = repRangeMax
            self.targetRIR = targetRIR
            self.restSeconds = restSeconds
        }
    }
}
