//
//  SavedMealDetailViewModel.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-25.
//

import Foundation
import Observation
import SwiftData

@Observable
final class SavedMealDetailViewModel {
    let meal: SavedMeal

    init(meal: SavedMeal) {
        self.meal = meal
    }

    /// Logs every item as its own FoodEntry in the given slot.
    /// SavedMealItem doesn't carry fibre/sugar/sodium, so those log as 0.
    func log(to slot: MealSlot, on date: Date, context: ModelContext) {
        for item in meal.sortedItems {
            context.insert(FoodEntry(
                date: date,
                mealSlot: slot,
                foodName: item.foodName,
                servingGrams: item.servingGrams,
                calories: item.calories,
                proteinG: item.proteinG,
                carbsG: item.carbsG,
                fatG: item.fatG
            ))
        }
        do {
            try context.save()
        } catch {
            assertionFailure("Failed to log saved meal: \(error)")
        }
    }
}
