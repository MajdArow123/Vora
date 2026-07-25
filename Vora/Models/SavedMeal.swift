//
//  SavedMeal.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-25.
//

import Foundation
import SwiftData

/// A named snapshot of logged foods, relogged as a batch from the Meals tab.
@Model
final class SavedMeal {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \SavedMealItem.parent)
    var items: [SavedMealItem]

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = .now,
        items: [SavedMealItem] = []
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.items = items
    }
}

extension SavedMeal {
    var sortedItems: [SavedMealItem] {
        items.sorted { $0.orderIndex < $1.orderIndex }
    }

    var totalCalories: Double { items.reduce(0) { $0 + $1.calories } }
    var totalProteinG: Double { items.reduce(0) { $0 + $1.proteinG } }
    var totalCarbsG: Double { items.reduce(0) { $0 + $1.carbsG } }
    var totalFatG: Double { items.reduce(0) { $0 + $1.fatG } }
}
