//
//  EnrichedFood.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-28.
//

import Foundation

/// One suggestion food after (or during) its OpenFoodFacts lookup, carrying
/// the sheet's portion edits. Never persisted: FoodItem isn't Codable, so
/// enrichment re-runs each time the sheet opens, including for a cached
/// suggestion. The suggestion's `unit` is dropped — foods are always grams.
struct EnrichedFood: Identifiable, Equatable {
    let id: UUID
    /// The AI's original food name — kept for estimate display and as the
    /// search seed (OpenFoodFacts names are often brand-noisy).
    let suggestedName: String
    let originalGrams: Double
    var editedGrams: Double
    var isRemoved = false
    /// Real per-100g data from OpenFoodFacts; nil when the lookup failed
    /// or found nothing.
    var realFoodItem: FoodItem?
    var isLoading = true

    var isApproximate: Bool { realFoodItem == nil }

    var displayName: String { realFoodItem?.name ?? suggestedName.capitalized }

    /// Single source for row macros, the meal total, AND the logged draft —
    /// what the user sees is exactly what gets logged.
    var nutrition: FoodItem.Nutrition {
        realFoodItem?.nutrition(for: editedGrams)
            ?? SuggestedFoodsLogger.estimatedNutrition(for: editedGrams)
    }

    init(from food: SuggestedFood) {
        self.id = food.id
        self.suggestedName = food.name
        self.originalGrams = food.grams
        self.editedGrams = food.grams
    }
}
