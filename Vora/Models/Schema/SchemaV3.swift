//
//  SchemaV3.swift
//  Vora
//
//  Created by Majd Arow on 2026-11-01.
//

import Foundation
import SwiftData

/// Adds WorkoutTemplate and TemplateExercise, replacing the UserDefaults
/// template dictionary. Purely additive: no V2 model changed or gained a
/// relationship to the new ones, so nothing is frozen. Saved UserDefaults
/// templates are moved in after the store opens by
/// `TemplateDefaultsMigration`.
nonisolated enum SchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }

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
        ]
    }
}
