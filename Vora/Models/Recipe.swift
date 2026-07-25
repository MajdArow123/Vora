//
//  Recipe.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-25.
//

import Foundation
import SwiftData

/// A named collection of ingredients whose combined nutrition is logged
/// per serving from the Recipes tab.
@Model
final class Recipe {
    @Attribute(.unique) var id: UUID
    var name: String
    var servings: Int
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \RecipeIngredient.parent)
    var ingredients: [RecipeIngredient]

    init(
        id: UUID = UUID(),
        name: String,
        servings: Int = 1,
        createdAt: Date = .now,
        ingredients: [RecipeIngredient] = []
    ) {
        self.id = id
        self.name = name
        self.servings = max(1, servings)
        self.createdAt = createdAt
        self.ingredients = ingredients
    }
}

extension Recipe {
    var sortedIngredients: [RecipeIngredient] {
        ingredients.sorted { $0.orderIndex < $1.orderIndex }
    }

    var totalGrams: Double { ingredients.reduce(0) { $0 + $1.servingGrams } }
    var totalCalories: Double { ingredients.reduce(0) { $0 + $1.calories } }
    var totalProteinG: Double { ingredients.reduce(0) { $0 + $1.proteinG } }
    var totalCarbsG: Double { ingredients.reduce(0) { $0 + $1.carbsG } }
    var totalFatG: Double { ingredients.reduce(0) { $0 + $1.fatG } }

    // max(1,_) guards hand-built rows that bypassed the init clamp.
    var perServingCalories: Double { totalCalories / Double(max(1, servings)) }
    var perServingProteinG: Double { totalProteinG / Double(max(1, servings)) }
    var perServingCarbsG: Double { totalCarbsG / Double(max(1, servings)) }
    var perServingFatG: Double { totalFatG / Double(max(1, servings)) }
}
