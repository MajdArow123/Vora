//
//  SuggestedFoodsLogger.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-27.
//

import Foundation
import SwiftData

/// A FoodEntry-shaped value built from one suggested food, before insertion.
/// `isEstimated` marks entries whose macros came from `GenericFoods` rather
/// than an OpenFoodFacts match.
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
    /// The diary has no field for estimates, so the name carries it.
    static let estimatedSuffix = " (estimated)"

    static func draft(for food: EnrichedFood) -> LoggedFoodDraft {
        let n = food.nutrition
        return LoggedFoodDraft(
            foodName: food.isApproximate ? food.displayName + estimatedSuffix : food.displayName,
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

    /// Adds the drafts to the diary, all or none: a failed save removes what
    /// it inserted and throws, so the caller can't report a false success.
    static func log(
        _ drafts: [LoggedFoodDraft],
        to slot: MealSlot,
        on date: Date,
        context: ModelContext,
        save: (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        let entries = drafts.map { draft in
            FoodEntry(
                date: date,
                mealSlot: slot,
                foodName: draft.foodName,
                servingGrams: draft.servingGrams,
                calories: draft.calories,
                proteinG: draft.proteinG,
                carbsG: draft.carbsG,
                fatG: draft.fatG,
                fibreG: draft.fibreG,
                sugarG: draft.sugarG,
                sodiumMg: draft.sodiumMg,
                barcode: draft.barcode
            )
        }
        entries.forEach(context.insert)
        do {
            try save(context)
        } catch {
            entries.forEach(context.delete)
            throw error
        }
    }
}
