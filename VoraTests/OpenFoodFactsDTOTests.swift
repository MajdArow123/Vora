//
//  OpenFoodFactsDTOTests.swift
//  VoraTests
//
//  Created by Majd Arow on 2026-07-21.
//

import Foundation
import Testing
@testable import Vora

struct OpenFoodFactsDTOTests {
    // MARK: - Helpers

    private func decodeProduct(_ json: String) throws -> OFFProduct {
        try JSONDecoder().decode(OFFProduct.self, from: Data(json.utf8))
    }

    private func expectApprox(_ actual: Double?, _ expected: Double, _ label: String) {
        let actual = actual ?? .nan
        #expect(abs(actual - expected) < 0.0001, "\(label): \(actual) vs \(expected)")
    }

    // MARK: - Complete product

    @Test func completeProductMapsEveryField() throws {
        let json = """
        {
            "code": "0025000058003",
            "product_name": "Rolled Oats",
            "brands": "Quaker, PepsiCo",
            "serving_quantity": 40,
            "nutriments": {
                "energy-kcal_100g": 389,
                "energy_100g": 1628,
                "proteins_100g": 16.9,
                "carbohydrates_100g": 66.3,
                "fat_100g": 6.9,
                "fiber_100g": 10.6,
                "sugars_100g": 0.99,
                "sodium_100g": 0.002,
                "salt_100g": 0.005
            }
        }
        """
        let product = try decodeProduct(json)
        let item = try #require(FoodItem(offProduct: product))

        #expect(item.id == "0025000058003")
        #expect(item.barcode == "0025000058003")
        #expect(item.name == "Rolled Oats")
        // Only the first comma-separated brand is kept.
        #expect(item.brand == "Quaker")
        // kcal wins over the kJ field when both are present.
        #expect(item.caloriesPer100g == 389)
        expectApprox(item.proteinPer100g, 16.9, "protein")
        expectApprox(item.carbsPer100g, 66.3, "carbs")
        expectApprox(item.fatPer100g, 6.9, "fat")
        expectApprox(item.fibrePer100g, 10.6, "fibre")
        expectApprox(item.sugarPer100g, 0.99, "sugar")
        // sodium_100g is in grams; 0.002 g -> 2 mg, preferred over salt.
        expectApprox(item.sodiumMgPer100g, 2, "sodium")
        #expect(item.defaultServingGrams == 40)
    }

    @Test func stringEncodedNumbersDecodeLikeNumbers() throws {
        let json = """
        {
            "code": "123",
            "product_name": "String Numbers",
            "serving_quantity": "30",
            "nutriments": {
                "energy-kcal_100g": "250",
                "proteins_100g": "12.5"
            }
        }
        """
        let product = try decodeProduct(json)
        #expect(product.servingQuantity?.value == 30)

        let item = try #require(FoodItem(offProduct: product))
        #expect(item.caloriesPer100g == 250)
        expectApprox(item.proteinPer100g, 12.5, "protein")
        #expect(item.defaultServingGrams == 30)
    }

    // MARK: - Missing optional fields

    @Test func missingOptionalFieldsFallBackToDefaults() throws {
        let json = """
        {
            "product_name": "Bare Minimum",
            "nutriments": {
                "energy-kcal_100g": 100
            }
        }
        """
        let product = try decodeProduct(json)
        let item = try #require(FoodItem(offProduct: product))

        #expect(item.name == "Bare Minimum")
        #expect(item.brand == nil)
        #expect(item.caloriesPer100g == 100)
        #expect(item.proteinPer100g == 0)
        #expect(item.carbsPer100g == 0)
        #expect(item.fatPer100g == 0)
        #expect(item.fibrePer100g == 0)
        #expect(item.sugarPer100g == 0)
        #expect(item.sodiumMgPer100g == 0)
        // No serving quantity -> 100 g default.
        #expect(item.defaultServingGrams == 100)
        // No code -> a generated UUID id, never empty.
        #expect(!item.id.isEmpty)
    }

    @Test func emptyOrWhitespaceBrandBecomesNil() throws {
        for brands in ["\"brands\": \"\",", "\"brands\": \"  , Other\",", ""] {
            let json = """
            {
                "product_name": "Brandless",
                \(brands)
                "nutriments": { "energy-kcal_100g": 50 }
            }
            """
            let product = try decodeProduct(json)
            let item = try #require(FoodItem(offProduct: product))
            #expect(item.brand == nil, "brands fragment: \(brands)")
        }
    }

    @Test func zeroOrMalformedServingQuantityFallsBackTo100() throws {
        for serving in ["0", "-5", "\"abc\"", "null"] {
            let json = """
            {
                "product_name": "Odd Serving",
                "serving_quantity": \(serving),
                "nutriments": { "energy-kcal_100g": 50 }
            }
            """
            let product = try decodeProduct(json)
            let item = try #require(FoodItem(offProduct: product))
            #expect(item.defaultServingGrams == 100, "serving: \(serving)")
        }
    }

    // MARK: - Energy fallbacks

    @Test func kilojoulesConvertToKcalWhenKcalIsMissing() throws {
        let json = """
        {
            "product_name": "KJ Only",
            "nutriments": {
                "energy_100g": 1628
            }
        }
        """
        let product = try decodeProduct(json)
        let item = try #require(FoodItem(offProduct: product))
        #expect(item.caloriesPer100g == 1628 / 4.184)
    }

    @Test func saltFallbackDerivesSodiumWhenSodiumIsMissing() throws {
        let json = """
        {
            "product_name": "Salty",
            "nutriments": {
                "energy-kcal_100g": 200,
                "salt_100g": 1.2
            }
        }
        """
        let product = try decodeProduct(json)
        let item = try #require(FoodItem(offProduct: product))
        // salt / 2.5 * 1000: 1.2 g salt -> 480 mg sodium.
        expectApprox(item.sodiumMgPer100g, 480, "sodium")
    }

    // MARK: - Per-serving-only nutriments

    @Test func perServingOnlyNutrimentsAreIgnoredSoTheProductIsRejected() throws {
        // The DTO maps only the *_100g keys; per-serving values are not
        // read, so a product with per-serving energy alone has no way to
        // derive calories and the mapping returns nil.
        let json = """
        {
            "product_name": "Serving Only",
            "serving_quantity": 30,
            "nutriments": {
                "energy-kcal_serving": 120,
                "proteins_serving": 4,
                "carbohydrates_serving": 20
            }
        }
        """
        let product = try decodeProduct(json)
        #expect(product.nutriments?.energyKcal100g?.value == nil)
        #expect(product.nutriments?.proteins100g?.value == nil)
        #expect(FoodItem(offProduct: product) == nil)
    }

    @Test func per100gValuesStillWinWhenServingValuesCoexist() throws {
        let json = """
        {
            "product_name": "Both Granularities",
            "nutriments": {
                "energy-kcal_100g": 400,
                "energy-kcal_serving": 120,
                "proteins_100g": 10,
                "proteins_serving": 3
            }
        }
        """
        let item = try #require(FoodItem(offProduct: try decodeProduct(json)))
        #expect(item.caloriesPer100g == 400)
        #expect(item.proteinPer100g == 10)
    }

    // MARK: - Rejection cases

    @Test func missingOrBlankNameReturnsNil() throws {
        let noName = """
        {
            "code": "1",
            "nutriments": { "energy-kcal_100g": 100 }
        }
        """
        #expect(FoodItem(offProduct: try decodeProduct(noName)) == nil)

        let blankName = """
        {
            "product_name": "   ",
            "nutriments": { "energy-kcal_100g": 100 }
        }
        """
        #expect(FoodItem(offProduct: try decodeProduct(blankName)) == nil)
    }

    @Test func missingEnergyReturnsNil() throws {
        let noEnergy = """
        {
            "product_name": "No Energy",
            "nutriments": { "proteins_100g": 20 }
        }
        """
        #expect(FoodItem(offProduct: try decodeProduct(noEnergy)) == nil)

        let noNutriments = """
        {
            "product_name": "No Nutriments"
        }
        """
        #expect(FoodItem(offProduct: try decodeProduct(noNutriments)) == nil)
    }

    // MARK: - Response envelopes

    @Test func searchResponseDecodesAndFiltersUnusableProducts() throws {
        let json = """
        {
            "products": [
                {
                    "product_name": "Good Product",
                    "nutriments": { "energy-kcal_100g": 100 }
                },
                {
                    "product_name": "No Calories Product",
                    "nutriments": { "proteins_100g": 5 }
                },
                {
                    "nutriments": { "energy-kcal_100g": 100 }
                }
            ]
        }
        """
        let response = try JSONDecoder().decode(OFFSearchResponse.self, from: Data(json.utf8))
        #expect(response.products.count == 3)

        let usable = response.products.compactMap(FoodItem.init(offProduct:))
        #expect(usable.map(\.name) == ["Good Product"])
    }

    @Test func productResponseDecodesStatusAndOptionalProduct() throws {
        let found = """
        {
            "status": 1,
            "product": {
                "code": "555",
                "product_name": "Found",
                "nutriments": { "energy-kcal_100g": 210 }
            }
        }
        """
        let foundResponse = try JSONDecoder().decode(OFFProductResponse.self, from: Data(found.utf8))
        #expect(foundResponse.status == 1)
        let product = try #require(foundResponse.product)
        #expect(FoodItem(offProduct: product)?.name == "Found")

        let notFound = """
        { "status": 0 }
        """
        let notFoundResponse = try JSONDecoder().decode(OFFProductResponse.self, from: Data(notFound.utf8))
        #expect(notFoundResponse.status == 0)
        #expect(notFoundResponse.product == nil)
    }
}
