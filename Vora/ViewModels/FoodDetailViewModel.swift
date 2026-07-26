//
//  FoodDetailViewModel.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import Foundation
import Observation
import SwiftData

@Observable
final class FoodDetailViewModel {
    let item: FoodItem
    var servingGrams: Double

    init(item: FoodItem) {
        self.item = item
        self.servingGrams = item.defaultServingGrams
    }

    var nutrition: FoodItem.Nutrition {
        item.nutrition(for: servingGrams)
    }

    var servingText: String {
        "\(Int(servingGrams.rounded())) g"
    }

    func adjustServing(by delta: Double) {
        servingGrams = min(max(servingGrams + delta, 5), 2000)
    }

    func setServing(_ grams: Double) {
        servingGrams = min(max(grams, 5), 2000)
    }

    func log(to slot: MealSlot, on date: Date, context: ModelContext) {
        let n = nutrition
        context.insert(FoodEntry(
            date: date,
            mealSlot: slot,
            foodName: item.name,
            servingGrams: servingGrams,
            calories: n.calories,
            proteinG: n.proteinG,
            carbsG: n.carbsG,
            fatG: n.fatG,
            fibreG: n.fibreG,
            sugarG: n.sugarG,
            sodiumMg: n.sodiumMg,
            barcode: item.barcode
        ))
        do {
            try context.save()
        } catch {
            assertionFailure("Failed to log food: \(error)")
        }
    }
}
