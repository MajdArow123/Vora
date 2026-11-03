//
//  SchemaV9.swift
//  Vora
//
//  Created by Majd Arow on 2026-11-03.
//

import Foundation
import SwiftData

/// Adds training cycles: the TrainingProgram and CycleDay entities, plus
/// `TemplateExercise.supersetGroup` and the optional `WorkoutTemplate.cycleDay`.
/// No TrainingProgram row reads as weekly mode, so nothing is backfilled.
nonisolated enum SchemaV9: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(9, 0, 0) }

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
            TrainingProgram.self,
            CycleDay.self,
        ]
    }
}
