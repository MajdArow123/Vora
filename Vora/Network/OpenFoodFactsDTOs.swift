//
//  OpenFoodFactsDTOs.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import Foundation

/// OpenFoodFacts encodes numeric fields as numbers or strings
/// interchangeably; this wrapper absorbs both.
struct OFFDouble: Decodable {
    let value: Double?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Double.self) {
            value = number
        } else if let string = try? container.decode(String.self) {
            value = Double(string)
        } else {
            value = nil
        }
    }
}

struct OFFSearchResponse: Decodable {
    let products: [OFFProduct]
}

struct OFFProductResponse: Decodable {
    let status: Int?
    let product: OFFProduct?
}

struct OFFProduct: Decodable {
    let code: String?
    let productName: String?
    let brands: String?
    let servingQuantity: OFFDouble?
    let nutriments: OFFNutriments?

    enum CodingKeys: String, CodingKey {
        case code
        case productName = "product_name"
        case brands
        case servingQuantity = "serving_quantity"
        case nutriments
    }
}

struct OFFNutriments: Decodable {
    let energyKcal100g: OFFDouble?
    let energyKj100g: OFFDouble?
    let proteins100g: OFFDouble?
    let carbohydrates100g: OFFDouble?
    let fat100g: OFFDouble?
    let fiber100g: OFFDouble?
    let sugars100g: OFFDouble?
    let sodium100g: OFFDouble?
    let salt100g: OFFDouble?

    enum CodingKeys: String, CodingKey {
        case energyKcal100g = "energy-kcal_100g"
        case energyKj100g = "energy_100g"
        case proteins100g = "proteins_100g"
        case carbohydrates100g = "carbohydrates_100g"
        case fat100g = "fat_100g"
        case fiber100g = "fiber_100g"
        case sugars100g = "sugars_100g"
        case sodium100g = "sodium_100g"
        case salt100g = "salt_100g"
    }
}

extension FoodItem {
    /// Maps an OFF product to the neutral shape. Returns nil when the
    /// product is unusable (no name, or no way to derive calories).
    init?(offProduct p: OFFProduct) {
        let name = (p.productName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }

        let n = p.nutriments
        let calories: Double
        if let kcal = n?.energyKcal100g?.value {
            calories = kcal
        } else if let kj = n?.energyKj100g?.value {
            calories = kj / 4.184
        } else {
            return nil
        }

        // OFF stores sodium in grams; convert to mg. Fall back to salt
        // (NaCl is ~40% sodium → sodium = salt / 2.5).
        let sodiumMg: Double
        if let sodiumG = n?.sodium100g?.value {
            sodiumMg = sodiumG * 1000
        } else if let saltG = n?.salt100g?.value {
            sodiumMg = saltG / 2.5 * 1000
        } else {
            sodiumMg = 0
        }

        let brand = (p.brands ?? "")
            .split(separator: ",")
            .first
            .map { $0.trimmingCharacters(in: .whitespaces) }

        let serving = p.servingQuantity?.value
        self.init(
            id: p.code ?? UUID().uuidString,
            name: name,
            brand: (brand?.isEmpty ?? true) ? nil : brand,
            caloriesPer100g: calories,
            proteinPer100g: n?.proteins100g?.value ?? 0,
            carbsPer100g: n?.carbohydrates100g?.value ?? 0,
            fatPer100g: n?.fat100g?.value ?? 0,
            fibrePer100g: n?.fiber100g?.value ?? 0,
            sugarPer100g: n?.sugars100g?.value ?? 0,
            sodiumMgPer100g: sodiumMg,
            defaultServingGrams: (serving ?? 0) > 0 ? serving! : 100
        )
    }
}
