//
//  CustomFood.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import Foundation
import SwiftData

/// A user-created food. Nutrition is stored per 100 g so any serving
/// size can be computed exactly.
@Model
final class CustomFood {
    @Attribute(.unique) var id: UUID
    var name: String
    var brand: String
    var defaultServingGrams: Double
    var caloriesPer100g: Double
    var proteinPer100g: Double
    var carbsPer100g: Double
    var fatPer100g: Double
    var fibrePer100g: Double
    var sugarPer100g: Double
    var sodiumMgPer100g: Double
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        brand: String = "",
        defaultServingGrams: Double = 100,
        caloriesPer100g: Double,
        proteinPer100g: Double = 0,
        carbsPer100g: Double = 0,
        fatPer100g: Double = 0,
        fibrePer100g: Double = 0,
        sugarPer100g: Double = 0,
        sodiumMgPer100g: Double = 0,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.brand = brand
        self.defaultServingGrams = defaultServingGrams
        self.caloriesPer100g = caloriesPer100g
        self.proteinPer100g = proteinPer100g
        self.carbsPer100g = carbsPer100g
        self.fatPer100g = fatPer100g
        self.fibrePer100g = fibrePer100g
        self.sugarPer100g = sugarPer100g
        self.sodiumMgPer100g = sodiumMgPer100g
        self.createdAt = createdAt
    }
}
