//
//  RecipeDetailViewModel.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-25.
//

import Foundation
import Observation
import SwiftData

@Observable
final class RecipeDetailViewModel {
    struct Portion {
        let grams: Double
        let calories: Double
        let proteinG: Double
        let carbsG: Double
        let fatG: Double
    }

    let recipe: Recipe
    var servingsToLog = 1

    init(recipe: Recipe) {
        self.recipe = recipe
    }

    func adjustServings(by delta: Int) {
        servingsToLog = min(max(servingsToLog + delta, 1), 20)
    }

    /// The chosen number of servings, scaled from the recipe totals.
    var portion: Portion {
        let factor = Double(servingsToLog) / Double(max(1, recipe.servings))
        return Portion(
            grams: recipe.totalGrams * factor,
            calories: recipe.totalCalories * factor,
            proteinG: recipe.totalProteinG * factor,
            carbsG: recipe.totalCarbsG * factor,
            fatG: recipe.totalFatG * factor
        )
    }

    /// Logs the portion as a single FoodEntry named after the recipe.
    /// RecipeIngredient doesn't carry fibre/sugar/sodium, so those log as 0.
    func log(to slot: MealSlot, on date: Date, context: ModelContext) {
        let portion = portion
        context.insert(FoodEntry(
            date: date,
            mealSlot: slot,
            foodName: recipe.name,
            servingGrams: portion.grams,
            calories: portion.calories,
            proteinG: portion.proteinG,
            carbsG: portion.carbsG,
            fatG: portion.fatG
        ))
        do {
            try context.save()
        } catch {
            assertionFailure("Failed to log recipe: \(error)")
        }
    }
}
