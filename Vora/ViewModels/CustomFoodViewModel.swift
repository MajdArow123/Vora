//
//  CustomFoodViewModel.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import Foundation
import Observation
import SwiftData

@Observable
final class CustomFoodViewModel {
    var name = ""
    var brand = ""
    var barcodeText = ""
    var servingText = "100"
    var caloriesText = ""
    var proteinText = ""
    var carbsText = ""
    var fatText = ""
    var fibreText = ""
    var sugarText = ""
    var sodiumText = ""

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Empty optional fields count as zero; calories and serving must be
    /// positive numbers.
    private func optionalValue(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return 0 }
        guard let value = Double(trimmed), value >= 0 else { return nil }
        return value
    }

    var canSave: Bool {
        guard !trimmedName.isEmpty,
              let calories = Double(caloriesText.trimmingCharacters(in: .whitespaces)), calories > 0,
              let serving = Double(servingText.trimmingCharacters(in: .whitespaces)), serving > 0
        else { return false }
        return [proteinText, carbsText, fatText, fibreText, sugarText, sodiumText]
            .allSatisfy { optionalValue($0) != nil }
    }

    func save(in context: ModelContext) {
        guard canSave,
              let calories = Double(caloriesText.trimmingCharacters(in: .whitespaces)),
              let serving = Double(servingText.trimmingCharacters(in: .whitespaces))
        else { return }

        let barcode = barcodeText.trimmingCharacters(in: .whitespacesAndNewlines)
        context.insert(CustomFood(
            name: trimmedName,
            brand: brand.trimmingCharacters(in: .whitespacesAndNewlines),
            defaultServingGrams: serving,
            caloriesPer100g: calories,
            proteinPer100g: optionalValue(proteinText) ?? 0,
            carbsPer100g: optionalValue(carbsText) ?? 0,
            fatPer100g: optionalValue(fatText) ?? 0,
            fibrePer100g: optionalValue(fibreText) ?? 0,
            sugarPer100g: optionalValue(sugarText) ?? 0,
            sodiumMgPer100g: optionalValue(sodiumText) ?? 0,
            barcode: barcode.isEmpty ? nil : barcode
        ))
        do {
            try context.save()
        } catch {
            assertionFailure("Failed to save custom food: \(error)")
        }
    }
}
