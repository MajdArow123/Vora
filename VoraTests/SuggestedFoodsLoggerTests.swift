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
    private let food = SuggestedFood(name: "chicken breast", grams: 200, unit: "g")

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

    @Test func matchedFoodUsesScaledOpenFoodFactsNutrition() async {
        let item = matchedItem
        let logger = SuggestedFoodsLogger(search: { _ in [item] })
        let draft = await logger.draft(for: food)

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

    @Test func searchFailureFallsBackToEstimates() async {
        let logger = SuggestedFoodsLogger(search: { _ in throw URLError(.notConnectedToInternet) })
        let draft = await logger.draft(for: food)

        #expect(draft.isEstimated == true)
        #expect(draft.proteinG == 50)
        #expect(draft.carbsG == 90)
        #expect(draft.fatG == 16)
        #expect(draft.calories == 704)
        #expect(draft.barcode == nil)
    }

    @Test func emptyResultsFallBackToEstimates() async {
        let logger = SuggestedFoodsLogger(search: { _ in [] })
        let draft = await logger.draft(for: food)
        #expect(draft.isEstimated == true)
    }

    @Test func estimatedDraftCapitalizesTheName() {
        let draft = SuggestedFoodsLogger.estimatedDraft(for: food)
        #expect(draft.foodName == "Chicken Breast")
        #expect(draft.servingGrams == 200)
    }
}
