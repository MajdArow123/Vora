//
//  SchemaV1.swift
//  Vora
//
//  Created by Majd Arow on 2026-11-01.
//

import Foundation
import SwiftData

/// The schema every store shipped before versioning was introduced.
/// It references the live model classes directly: their entity names
/// and version hashes are what existing on-disk stores were created
/// with. Before a later version changes one of these models, copy the
/// current class into an `extension SchemaV1` as a frozen nested type
/// and point this list at the copy (see docs/MIGRATIONS.md).
nonisolated enum SchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

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
