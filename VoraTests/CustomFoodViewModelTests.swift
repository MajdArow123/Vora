//
//  CustomFoodViewModelTests.swift
//  VoraTests
//
//  Created by Majd Arow on 2026-07-21.
//

import Foundation
import SwiftData
import Testing
@testable import Vora

struct CustomFoodViewModelTests {
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

    /// A view model whose required fields are all valid; individual tests
    /// then break one field at a time.
    private func validViewModel() -> CustomFoodViewModel {
        let viewModel = CustomFoodViewModel()
        viewModel.name = "Protein Bar"
        viewModel.caloriesText = "380"
        viewModel.servingText = "60"
        return viewModel
    }

    // MARK: - canSave validation

    @Test func canSaveIsTrueWithMinimalValidInput() {
        let viewModel = validViewModel()
        #expect(viewModel.canSave)
    }

    @Test func canSaveRequiresANonBlankName() {
        let viewModel = validViewModel()

        viewModel.name = ""
        #expect(!viewModel.canSave)

        viewModel.name = "   \n  "
        #expect(!viewModel.canSave)

        viewModel.name = "  Bar  "
        #expect(viewModel.canSave)
    }

    @Test(arguments: ["", "0", "-5", "abc", "12abc", "1,5"])
    func canSaveRejectsInvalidCalories(text: String) {
        let viewModel = validViewModel()
        viewModel.caloriesText = text
        #expect(!viewModel.canSave)
    }

    @Test func canSaveAcceptsBoundaryCalories() {
        let viewModel = validViewModel()

        viewModel.caloriesText = "0.1"
        #expect(viewModel.canSave)

        viewModel.caloriesText = " 250 "
        #expect(viewModel.canSave)
    }

    @Test(arguments: ["", "0", "-1", "x"])
    func canSaveRejectsInvalidServing(text: String) {
        let viewModel = validViewModel()
        viewModel.servingText = text
        #expect(!viewModel.canSave)
    }

    @Test func canSaveAcceptsPositiveServing() {
        let viewModel = validViewModel()
        viewModel.servingText = "0.5"
        #expect(viewModel.canSave)
    }

    @Test func canSaveTreatsEmptyOptionalFieldsAsZero() {
        let viewModel = validViewModel()
        viewModel.proteinText = ""
        viewModel.carbsText = "   "
        viewModel.fatText = ""
        viewModel.fibreText = ""
        viewModel.sugarText = ""
        viewModel.sodiumText = ""
        #expect(viewModel.canSave)
    }

    @Test func canSaveAcceptsZeroOptionalFields() {
        let viewModel = validViewModel()
        viewModel.proteinText = "0"
        #expect(viewModel.canSave)
    }

    @Test(arguments: ["-2", "abc", "1,5"])
    func canSaveRejectsInvalidOptionalFields(text: String) {
        let viewModel = validViewModel()

        viewModel.proteinText = text
        #expect(!viewModel.canSave)
        viewModel.proteinText = ""

        viewModel.sodiumText = text
        #expect(!viewModel.canSave)
    }

    // MARK: - Save

    @Test func saveInsertsCustomFoodWithTrimmedAndParsedValues() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let viewModel = CustomFoodViewModel()
        viewModel.name = "  Overnight Oats \n"
        viewModel.brand = "  HomeMade  "
        viewModel.servingText = " 85 "
        viewModel.caloriesText = " 372.5 "
        viewModel.proteinText = "12.5"
        viewModel.carbsText = "60"
        viewModel.fatText = "" // empty optionals default to zero
        viewModel.fibreText = "8.2"
        viewModel.sugarText = "0"
        viewModel.sodiumText = "150"
        #expect(viewModel.canSave)

        viewModel.save(in: context)

        let saved = try #require(try context.fetch(FetchDescriptor<CustomFood>()).first)
        #expect(saved.name == "Overnight Oats")
        #expect(saved.brand == "HomeMade")
        #expect(saved.defaultServingGrams == 85)
        #expect(saved.caloriesPer100g == 372.5)
        #expect(saved.proteinPer100g == 12.5)
        #expect(saved.carbsPer100g == 60)
        #expect(saved.fatPer100g == 0)
        #expect(saved.fibrePer100g == 8.2)
        #expect(saved.sugarPer100g == 0)
        #expect(saved.sodiumMgPer100g == 150)
    }

    @Test func saveDoesNothingWhenInvalid() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let viewModel = validViewModel()
        viewModel.caloriesText = "not a number"
        #expect(!viewModel.canSave)

        viewModel.save(in: context)

        let saved = try context.fetch(FetchDescriptor<CustomFood>())
        #expect(saved.isEmpty)
    }

    @Test func saveDoesNothingWhenNameIsBlank() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let viewModel = validViewModel()
        viewModel.name = "   "
        viewModel.save(in: context)

        #expect(try context.fetch(FetchDescriptor<CustomFood>()).isEmpty)
    }
}
