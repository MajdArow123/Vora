//
//  SuggestedFoodsLogger.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-27.
//

import Foundation

/// A FoodEntry-shaped value built from one suggested food, before insertion.
/// `isEstimated` marks entries whose macros came from the fallback formula
/// rather than an OpenFoodFacts match.
struct LoggedFoodDraft: Equatable, Sendable {
    let foodName: String
    let servingGrams: Double
    let calories: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
    let fibreG: Double
    let sugarG: Double
    let sodiumMg: Double
    let barcode: String?
    let isEstimated: Bool
}

/// Pure mapping from enrichment results to loggable drafts. The network
/// happened earlier, in MealSuggestionViewModel's enrichment pass — logging
/// never searches again, so the entry logged is exactly the food the user
/// saw in the sheet.
enum SuggestedFoodsLogger {
    static func draft(for food: EnrichedFood) -> LoggedFoodDraft {
        let n = food.nutrition
        return LoggedFoodDraft(
            foodName: food.displayName,
            servingGrams: food.editedGrams,
            calories: n.calories,
            proteinG: n.proteinG,
            carbsG: n.carbsG,
            fatG: n.fatG,
            fibreG: n.fibreG,
            sugarG: n.sugarG,
            sodiumMg: n.sodiumMg,
            barcode: food.realFoodItem?.barcode,
            isEstimated: food.isApproximate
        )
    }

    /// Generic whole-food macro split per gram; calories derived 4/4/9.
    /// Shared by EnrichedFood's display macros and the estimate drafts so
    /// the two can never diverge.
    static func estimatedNutrition(for grams: Double) -> FoodItem.Nutrition {
        let proteinG = grams * 0.25
        let carbsG = grams * 0.45
        let fatG = grams * 0.08
        return FoodItem.Nutrition(
            calories: proteinG * 4 + carbsG * 4 + fatG * 9,
            proteinG: proteinG,
            carbsG: carbsG,
            fatG: fatG,
            fibreG: 0,
            sugarG: 0,
            sodiumMg: 0
        )
    }
}
