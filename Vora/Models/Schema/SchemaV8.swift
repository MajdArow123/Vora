//
//  SchemaV8.swift
//  Vora
//
//  Created by Majd Arow on 2026-11-02.
//

import Foundation
import SwiftData

/// Adds set types and sides to SetEntry and superset groups to ExerciseLog,
/// all optional. nil reads as a normal, unlinked set, so nothing is backfilled.
nonisolated enum SchemaV8: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(8, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            UserProfile.self,
            FoodEntry.self,
            CustomFood.self,
            WorkoutSession.self,
            ExerciseLog.self,
            SetEntry.self,
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
            ExpenditureCheckIn.self,
        ]
    }
}

// Verbatim copies of the live template cluster as of SchemaV8, with
// main-actor helpers left out of the initializers. Do not edit.
extension SchemaV8 {
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
