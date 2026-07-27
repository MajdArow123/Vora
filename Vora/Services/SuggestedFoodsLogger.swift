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

/// Turns suggested foods into loggable drafts by searching OpenFoodFacts.
/// Never throws: any search failure or empty result degrades to estimated
/// macros so one flaky lookup can't sink the whole "Log all foods" flow.
struct SuggestedFoodsLogger {
    /// Injectable for tests; defaults to the live OpenFoodFacts search.
    var search: (String) async throws -> [FoodItem] = { try await OpenFoodFactsClient().search($0) }

    func draft(for food: SuggestedFood) async -> LoggedFoodDraft {
        if let item = (try? await search(food.name))?.first {
            let n = item.nutrition(for: food.grams)
            return LoggedFoodDraft(
                foodName: item.name,
                servingGrams: food.grams,
                calories: n.calories,
                proteinG: n.proteinG,
                carbsG: n.carbsG,
                fatG: n.fatG,
                fibreG: n.fibreG,
                sugarG: n.sugarG,
                sodiumMg: n.sodiumMg,
                barcode: item.barcode,
                isEstimated: false
            )
        }
        return Self.estimatedDraft(for: food)
    }

    /// Generic whole-food macro split per gram; calories derived 4/4/9.
    static func estimatedDraft(for food: SuggestedFood) -> LoggedFoodDraft {
        let proteinG = food.grams * 0.25
        let carbsG = food.grams * 0.45
        let fatG = food.grams * 0.08
        return LoggedFoodDraft(
            foodName: food.name.capitalized,
            servingGrams: food.grams,
            calories: proteinG * 4 + carbsG * 4 + fatG * 9,
            proteinG: proteinG,
            carbsG: carbsG,
            fatG: fatG,
            fibreG: 0,
            sugarG: 0,
            sodiumMg: 0,
            barcode: nil,
            isEstimated: true
        )
    }
}
