//
//  FoodDetailViewModelTests.swift
//  VoraTests
//
//  Created by Majd Arow on 2026-07-21.
//

import Foundation
import SwiftData
import Testing
@testable import Vora

struct FoodDetailViewModelTests {
    // MARK: - Fixtures

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            UserProfile.self, FoodEntry.self, CustomFood.self,
            WorkoutSession.self, ExerciseLog.self, SetEntry.self,
            WeightEntry.self, WaterEntry.self, CardioEntry.self, SplitDay.self,
            SavedMeal.self, SavedMealItem.self, Recipe.self, RecipeIngredient.self,
        ])
        return try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
    }

    private var oats: FoodItem {
        FoodItem(
            id: "test-oats",
            name: "Rolled Oats",
            brand: "Quaker",
            caloriesPer100g: 389,
            proteinPer100g: 16.9,
            carbsPer100g: 66.3,
            fatPer100g: 6.9,
            fibrePer100g: 10.6,
            sugarPer100g: 0.99,
            sodiumMgPer100g: 2,
            defaultServingGrams: 40
        )
    }

    private func expectApprox(_ actual: Double, _ expected: Double, _ label: String) {
        #expect(abs(actual - expected) < 0.0001, "\(label): \(actual) vs \(expected)")
    }

    // MARK: - Init and scaling

    @Test func initStartsAtTheItemDefaultServing() {
        let viewModel = FoodDetailViewModel(item: oats)
        #expect(viewModel.servingGrams == 40)
    }

    @Test func nutritionScalesLinearlyWithServing() {
        let viewModel = FoodDetailViewModel(item: oats)
        viewModel.setServing(250) // factor 2.5

        let n = viewModel.nutrition
        expectApprox(n.calories, 972.5, "calories")
        expectApprox(n.proteinG, 42.25, "protein")
        expectApprox(n.carbsG, 165.75, "carbs")
        expectApprox(n.fatG, 17.25, "fat")
        expectApprox(n.fibreG, 26.5, "fibre")
        expectApprox(n.sugarG, 2.475, "sugar")
        expectApprox(n.sodiumMg, 5, "sodium")
    }

    @Test func nutritionAtOneHundredGramsMatchesPer100gValues() {
        let viewModel = FoodDetailViewModel(item: oats)
        viewModel.setServing(100)

        let n = viewModel.nutrition
        expectApprox(n.calories, 389, "calories")
        expectApprox(n.proteinG, 16.9, "protein")
    }

    // MARK: - Serving text

    @Test func servingTextRoundsToWholeGrams() {
        let viewModel = FoodDetailViewModel(item: oats)

        viewModel.setServing(150.4)
        #expect(viewModel.servingText == "150 g")

        viewModel.setServing(150.6)
        #expect(viewModel.servingText == "151 g")

        viewModel.setServing(40)
        #expect(viewModel.servingText == "40 g")
    }

    // MARK: - Clamping

    @Test func adjustServingClampsToFiveGramFloor() {
        let viewModel = FoodDetailViewModel(item: oats)
        viewModel.adjustServing(by: -100)
        #expect(viewModel.servingGrams == 5)

        // Further decrements stay pinned at the floor.
        viewModel.adjustServing(by: -10)
        #expect(viewModel.servingGrams == 5)
    }

    @Test func adjustServingClampsToTwoThousandGramCeiling() {
        let viewModel = FoodDetailViewModel(item: oats)
        viewModel.adjustServing(by: 5000)
        #expect(viewModel.servingGrams == 2000)

        viewModel.adjustServing(by: 1)
        #expect(viewModel.servingGrams == 2000)
    }

    @Test func adjustServingMovesFreelyWithinBounds() {
        let viewModel = FoodDetailViewModel(item: oats)
        viewModel.adjustServing(by: 10)
        #expect(viewModel.servingGrams == 50)
        viewModel.adjustServing(by: -25)
        #expect(viewModel.servingGrams == 25)
    }

    @Test func setServingClampsOutOfRangeValues() {
        let viewModel = FoodDetailViewModel(item: oats)

        viewModel.setServing(1)
        #expect(viewModel.servingGrams == 5)

        viewModel.setServing(-50)
        #expect(viewModel.servingGrams == 5)

        viewModel.setServing(9999)
        #expect(viewModel.servingGrams == 2000)

        viewModel.setServing(80)
        #expect(viewModel.servingGrams == 80)

        // Boundary values are accepted exactly.
        viewModel.setServing(5)
        #expect(viewModel.servingGrams == 5)
        viewModel.setServing(2000)
        #expect(viewModel.servingGrams == 2000)
    }

    // MARK: - Logging

    @Test func logInsertsAScaledFoodEntry() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let viewModel = FoodDetailViewModel(item: oats)
        viewModel.setServing(80) // factor 0.8

        let logDate = Calendar.current.startOfDay(for: .now).addingTimeInterval(13 * 3600)
        viewModel.log(to: .lunch, on: logDate, context: context)

        let saved = try #require(try context.fetch(FetchDescriptor<FoodEntry>()).first)
        #expect(saved.foodName == "Rolled Oats")
        #expect(saved.mealSlot == .lunch)
        #expect(saved.date == logDate)
        #expect(saved.servingGrams == 80)
        expectApprox(saved.calories, 311.2, "calories")
        expectApprox(saved.proteinG, 13.52, "protein")
        expectApprox(saved.carbsG, 53.04, "carbs")
        expectApprox(saved.fatG, 5.52, "fat")
        expectApprox(saved.fibreG, 8.48, "fibre")
        expectApprox(saved.sugarG, 0.792, "sugar")
        expectApprox(saved.sodiumMg, 1.6, "sodium")
    }

    @Test func logPersistsTheItemBarcode() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        var scanned = oats
        scanned.barcode = "0025000058003"
        let viewModel = FoodDetailViewModel(item: scanned)

        viewModel.log(to: .breakfast, on: .now, context: context)

        let saved = try #require(try context.fetch(FetchDescriptor<FoodEntry>()).first)
        #expect(saved.barcode == "0025000058003")
    }

    @Test func barcodeRoundTripsThroughCustomFoodAndEntry() throws {
        let custom = CustomFood(name: "Protein Bar", caloriesPer100g: 400, barcode: "7300400481588")
        #expect(FoodItem(customFood: custom).barcode == "7300400481588")

        let entry = FoodEntry(
            date: .now, mealSlot: .snack, foodName: "Protein Bar",
            servingGrams: 55, calories: 220, proteinG: 20, carbsG: 20, fatG: 7,
            barcode: "7300400481588"
        )
        let item = try #require(FoodItem(entry: entry))
        #expect(item.barcode == "7300400481588")
    }
}
