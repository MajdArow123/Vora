//
//  FoodEntry.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import Foundation
import SwiftData

enum MealSlot: String, Codable, CaseIterable {
    case breakfast
    case postWorkout
    case lunch
    case dinner
    case snack
}

@Model
final class FoodEntry {
    @Attribute(.unique) var id: UUID
    var date: Date
    var mealSlot: MealSlot
    var foodName: String
    var servingGrams: Double
    var calories: Double
    var proteinG: Double
    var carbsG: Double
    var fatG: Double
    var fibreG: Double
    var sodiumMg: Double

    init(
        id: UUID = UUID(),
        date: Date,
        mealSlot: MealSlot,
        foodName: String,
        servingGrams: Double,
        calories: Double,
        proteinG: Double,
        carbsG: Double,
        fatG: Double,
        fibreG: Double = 0,
        sodiumMg: Double = 0
    ) {
        self.id = id
        self.date = date
        self.mealSlot = mealSlot
        self.foodName = foodName
        self.servingGrams = servingGrams
        self.calories = calories
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.fibreG = fibreG
        self.sodiumMg = sodiumMg
    }
}
