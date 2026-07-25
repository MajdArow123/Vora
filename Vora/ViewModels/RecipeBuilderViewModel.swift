//
//  RecipeBuilderViewModel.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-25.
//

import Foundation
import Observation
import SwiftData

@Observable
final class RecipeBuilderViewModel {
    /// Value-type draft so cancelling the builder inserts nothing.
    struct DraftIngredient: Identifiable, Equatable {
        let id = UUID()
        var foodName: String
        var servingGrams: Double
        var calories: Double
        var proteinG: Double
        var carbsG: Double
        var fatG: Double
    }

    var name = ""
    var servings = 1
    private(set) var ingredients: [DraftIngredient] = []

    func addIngredient(from item: FoodItem, grams: Double) {
        let nutrition = item.nutrition(for: grams)
        ingredients.append(DraftIngredient(
            foodName: item.name,
            servingGrams: grams,
            calories: nutrition.calories,
            proteinG: nutrition.proteinG,
            carbsG: nutrition.carbsG,
            fatG: nutrition.fatG
        ))
    }

    func remove(_ ingredient: DraftIngredient) {
        ingredients.removeAll { $0.id == ingredient.id }
    }

    func adjustServings(by delta: Int) {
        servings = min(max(servings + delta, 1), 20)
    }

    var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !ingredients.isEmpty
    }

    var totalCalories: Double { ingredients.reduce(0) { $0 + $1.calories } }

    var perServingCalories: Double { totalCalories / Double(max(1, servings)) }

    func save(in context: ModelContext) {
        guard canSave else { return }
        let recipeIngredients = ingredients.enumerated().map { index, draft in
            RecipeIngredient(
                foodName: draft.foodName,
                servingGrams: draft.servingGrams,
                calories: draft.calories,
                proteinG: draft.proteinG,
                carbsG: draft.carbsG,
                fatG: draft.fatG,
                orderIndex: index
            )
        }
        context.insert(Recipe(
            name: name.trimmingCharacters(in: .whitespaces),
            servings: servings,
            ingredients: recipeIngredients
        ))
        do {
            try context.save()
        } catch {
            assertionFailure("Failed to save recipe: \(error)")
        }
    }
}
