//
//  SuggestedFoodsLoggerTests.swift
//  VoraTests
//
//  Created by Majd Arow on 2026-07-27.
//

import Foundation
import Testing
@testable import Vora

struct SuggestedFoodsLoggerTests {
    private let matchedItem = FoodItem(
        id: "off-123",
        name: "Chicken Breast",
        brand: nil,
        caloriesPer100g: 120,
        proteinPer100g: 22,
        carbsPer100g: 1,
        fatPer100g: 3,
        fibrePer100g: 0.5,
        sugarPer100g: 0.2,
        sodiumMgPer100g: 60,
        defaultServingGrams: 100,
        barcode: "5000112637922"
    )

    private func enrichedFood(grams: Double = 200, item: FoodItem? = nil) -> EnrichedFood {
        var food = EnrichedFood(from: SuggestedFood(name: "chicken breast", grams: grams, unit: "g"))
        food.realFoodItem = item
        food.isLoading = false
        return food
    }

    @Test func matchedFoodUsesScaledOpenFoodFactsNutrition() {
        let draft = SuggestedFoodsLogger.draft(for: enrichedFood(item: matchedItem))

        #expect(draft.isEstimated == false)
        #expect(draft.foodName == "Chicken Breast")
        #expect(draft.servingGrams == 200)
        #expect(draft.calories == 240)
        #expect(draft.proteinG == 44)
        #expect(draft.carbsG == 2)
        #expect(draft.fatG == 6)
        #expect(draft.fibreG == 1)
        #expect(draft.sodiumMg == 120)
        #expect(draft.barcode == "5000112637922")
    }

    @Test func editedGramsDriveTheDraft() {
        var food = enrichedFood(item: matchedItem)
        food.editedGrams = 100

        let draft = SuggestedFoodsLogger.draft(for: food)
        #expect(draft.servingGrams == 100)
        #expect(draft.calories == 120)
        #expect(draft.proteinG == 22)
    }

    @Test func missingItemFallsBackToTypicalValuesForThatFood() {
        let draft = SuggestedFoodsLogger.draft(for: enrichedFood(item: nil))

        #expect(draft.isEstimated == true)
        #expect(draft.foodName == "Chicken Breast (estimated)")
        #expect(draft.servingGrams == 200)
        #expect(draft.proteinG == 62)
        #expect(draft.carbsG == 0)
        #expect(abs(draft.fatG - 7.2) < 0.001)
        #expect(abs(draft.calories - 312.8) < 0.001)
        #expect(draft.fibreG == 0)
        #expect(draft.sodiumMg == 0)
        #expect(draft.barcode == nil)
    }
}
