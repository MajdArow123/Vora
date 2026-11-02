//
//  SchemaV2.swift
//  Vora
//
//  Created by Majd Arow on 2026-11-01.
//

import Foundation
import SwiftData

/// Adds `ExerciseLog.exerciseId`, the permanent library ID that history,
/// PRs and pre-fill match on. Existing rows are filled after the store
/// opens by `ExerciseIDBackfill`. Models a later version changed are frozen
/// below (see docs/MIGRATIONS.md).
nonisolated enum SchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            UserProfile.self,
            FoodEntry.self,
            CustomFood.self,
            SchemaV2.WorkoutSession.self,
            SchemaV2.ExerciseLog.self,
            SchemaV2.SetEntry.self,
            WeightEntry.self,
            BodyMeasurement.self,
            WaterEntry.self,
            SchemaV2.CardioEntry.self,
            SplitDay.self,
            SavedMeal.self,
            SavedMealItem.self,
            Recipe.self,
            RecipeIngredient.self,
            Supplement.self,
            SupplementLog.self,
            GymProfile.self,
        ]
    }
}

// MARK: - Frozen V2 models

// Verbatim copies of the live classes as of SchemaV2. Do not edit.
// The workout cluster is frozen together because its relationships
// reference one another; CardioEntry has no relationships.
extension SchemaV2 {
    @Model
    final class WorkoutSession {
        @Attribute(.unique) var id: UUID
        var date: Date
        var sessionName: String
        var durationSeconds: Int
        var totalVolumeKg: Double
        var notes: String

        @Relationship(deleteRule: .cascade, inverse: \ExerciseLog.parent)
        var exercises: [ExerciseLog]

        init(
            id: UUID = UUID(),
            date: Date,
            sessionName: String,
            durationSeconds: Int = 0,
            totalVolumeKg: Double = 0,
            notes: String = "",
            exercises: [ExerciseLog] = []
        ) {
            self.id = id
            self.date = date
            self.sessionName = sessionName
            self.durationSeconds = durationSeconds
            self.totalVolumeKg = totalVolumeKg
            self.notes = notes
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
        /// Rate of perceived exertion, 1–10. 0 means not set.
        var rpe: Int

        var parent: ExerciseLog?

        init(
            id: UUID = UUID(),
            setNumber: Int,
            weightKg: Double,
            reps: Int,
            isCompleted: Bool = false,
            rpe: Int = 0
        ) {
            self.id = id
            self.setNumber = setNumber
            self.weightKg = weightKg
            self.reps = reps
            self.isCompleted = isCompleted
            self.rpe = rpe
        }
    }

    @Model
    final class CardioEntry {
        @Attribute(.unique) var id: UUID
        var date: Date
        var type: CardioType
        var durationSeconds: Int
        var estimatedCalories: Double

        // Machine-specific stats. All optional so pre-existing rows migrate
        // untouched; only the fields relevant to `type` are ever populated.
        var speedKmh: Double?
        var inclinePercent: Double?
        var resistanceLevel: Int?
        var strokesPerMinute: Int?
        var stepsPerMinute: Int?
        var rpm: Int?
        var distanceKm: Double?
        /// Minutes per kilometre.
        var pace: Double?

        init(
            id: UUID = UUID(),
            date: Date,
            type: CardioType,
            durationSeconds: Int,
            estimatedCalories: Double,
            speedKmh: Double? = nil,
            inclinePercent: Double? = nil,
            resistanceLevel: Int? = nil,
            strokesPerMinute: Int? = nil,
            stepsPerMinute: Int? = nil,
            rpm: Int? = nil,
            distanceKm: Double? = nil,
            pace: Double? = nil
        ) {
            self.id = id
            self.date = date
            self.type = type
            self.durationSeconds = durationSeconds
            self.estimatedCalories = estimatedCalories
            self.speedKmh = speedKmh
            self.inclinePercent = inclinePercent
            self.resistanceLevel = resistanceLevel
            self.strokesPerMinute = strokesPerMinute
            self.stepsPerMinute = stepsPerMinute
            self.rpm = rpm
            self.distanceKm = distanceKm
            self.pace = pace
        }
    }
}
