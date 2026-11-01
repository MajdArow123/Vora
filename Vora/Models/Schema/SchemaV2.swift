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
/// opens by `ExerciseIDBackfill`.
nonisolated enum SchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

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
        ]
    }
}
