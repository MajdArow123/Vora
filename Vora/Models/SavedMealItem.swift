//
//  SavedMealItem.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-25.
//

import Foundation
import SwiftData

/// One food inside a SavedMeal. Macros are absolute for `servingGrams`
/// (the FoodEntry convention), snapshotted at save time.
@Model
final class SavedMealItem {
    @Attribute(.unique) var id: UUID
    var foodName: String
    var servingGrams: Double
    var calories: Double
    var proteinG: Double
    var carbsG: Double
    var fatG: Double
    var orderIndex: Int

    var parent: SavedMeal?

    init(
        id: UUID = UUID(),
        foodName: String,
        servingGrams: Double,
        calories: Double,
        proteinG: Double,
        carbsG: Double,
        fatG: Double,
        orderIndex: Int
    ) {
        self.id = id
        self.foodName = foodName
        self.servingGrams = servingGrams
        self.calories = calories
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.orderIndex = orderIndex
    }
}
