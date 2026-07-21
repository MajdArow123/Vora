//
//  FoodItem.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import Foundation

/// The one neutral food shape the UI consumes, regardless of source
/// (OpenFoodFacts, custom foods, or recent diary entries). Nutrition is
/// always per 100 g; serving math derives from it.
struct FoodItem: Identifiable, Hashable {
    let id: String
    let name: String
    let brand: String?
    let caloriesPer100g: Double
    let proteinPer100g: Double
    let carbsPer100g: Double
    let fatPer100g: Double
    let fibrePer100g: Double
    let sugarPer100g: Double
    let sodiumMgPer100g: Double
    let defaultServingGrams: Double

    struct Nutrition {
        let calories: Double
        let proteinG: Double
        let carbsG: Double
        let fatG: Double
        let fibreG: Double
        let sugarG: Double
        let sodiumMg: Double
    }

    func nutrition(for grams: Double) -> Nutrition {
        let f = grams / 100
        return Nutrition(
            calories: caloriesPer100g * f,
            proteinG: proteinPer100g * f,
            carbsG: carbsPer100g * f,
            fatG: fatPer100g * f,
            fibreG: fibrePer100g * f,
            sugarG: sugarPer100g * f,
            sodiumMg: sodiumMgPer100g * f
        )
    }
}

extension FoodItem {
    init(customFood: CustomFood) {
        self.init(
            id: "custom-\(customFood.id.uuidString)",
            name: customFood.name,
            brand: customFood.brand.isEmpty ? nil : customFood.brand,
            caloriesPer100g: customFood.caloriesPer100g,
            proteinPer100g: customFood.proteinPer100g,
            carbsPer100g: customFood.carbsPer100g,
            fatPer100g: customFood.fatPer100g,
            fibrePer100g: customFood.fibrePer100g,
            sugarPer100g: customFood.sugarPer100g,
            sodiumMgPer100g: customFood.sodiumMgPer100g,
            defaultServingGrams: customFood.defaultServingGrams
        )
    }

    /// Reconstructs the per-100 g basis from a logged entry so recents
    /// can be re-logged at any serving size. Returns nil for zero-gram
    /// entries, which cannot be scaled.
    init?(entry: FoodEntry) {
        guard entry.servingGrams > 0 else { return nil }
        let f = 100 / entry.servingGrams
        self.init(
            id: "recent-\(entry.foodName.lowercased())",
            name: entry.foodName,
            brand: nil,
            caloriesPer100g: entry.calories * f,
            proteinPer100g: entry.proteinG * f,
            carbsPer100g: entry.carbsG * f,
            fatPer100g: entry.fatG * f,
            fibrePer100g: entry.fibreG * f,
            sugarPer100g: entry.sugarG * f,
            sodiumMgPer100g: entry.sodiumMg * f,
            defaultServingGrams: entry.servingGrams
        )
    }
}
