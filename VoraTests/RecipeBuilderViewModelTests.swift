//
//  RecipeBuilderViewModelTests.swift
//  VoraTests
//
//  Created by Majd Arow on 2026-07-25.
//

import Foundation
import SwiftData
import Testing
@testable import Vora

struct RecipeBuilderViewModelTests {
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

    private func makeItem(name: String = "Oats") -> FoodItem {
        FoodItem(
            id: "test-\(name.lowercased())",
            name: name,
            brand: nil,
            caloriesPer100g: 100,
            proteinPer100g: 10,
            carbsPer100g: 5,
            fatPer100g: 2,
            fibrePer100g: 1,
            sugarPer100g: 0.5,
            sodiumMgPer100g: 10,
            defaultServingGrams: 100
        )
    }

    @Test func addIngredientScalesPer100gToChosenGrams() throws {
        let viewModel = RecipeBuilderViewModel()
        viewModel.addIngredient(from: makeItem(), grams: 250)

        let draft = try #require(viewModel.ingredients.first)
        #expect(draft.foodName == "Oats")
        #expect(draft.servingGrams == 250)
        #expect(abs(draft.calories - 250) < 0.001)
        #expect(abs(draft.proteinG - 25) < 0.001)
        #expect(abs(draft.carbsG - 12.5) < 0.001)
        #expect(abs(draft.fatG - 5) < 0.001)
    }

    @Test func canSaveRequiresNameAndAtLeastOneIngredient() {
        let viewModel = RecipeBuilderViewModel()
        #expect(!viewModel.canSave)

        viewModel.name = "Pancakes"
        #expect(!viewModel.canSave)

        viewModel.addIngredient(from: makeItem(), grams: 100)
        #expect(viewModel.canSave)

        viewModel.name = "   "
        #expect(!viewModel.canSave)
    }

    @Test func removeDeletesTheRightDraft() {
        let viewModel = RecipeBuilderViewModel()
        viewModel.addIngredient(from: makeItem(name: "Oats"), grams: 100)
        viewModel.addIngredient(from: makeItem(name: "Whey"), grams: 50)

        let oats = viewModel.ingredients[0]
        viewModel.remove(oats)

        #expect(viewModel.ingredients.map(\.foodName) == ["Whey"])
    }

    @Test func adjustServingsClampsBetweenOneAndTwenty() {
        let viewModel = RecipeBuilderViewModel()
        viewModel.adjustServings(by: -5)
        #expect(viewModel.servings == 1)
        viewModel.adjustServings(by: 100)
        #expect(viewModel.servings == 20)
    }

    @Test func savePersistsRecipeWithSequentialOrderIndex() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let viewModel = RecipeBuilderViewModel()
        viewModel.name = "  Pancakes  "
        viewModel.servings = 3
        viewModel.addIngredient(from: makeItem(name: "Oats"), grams: 200)
        viewModel.addIngredient(from: makeItem(name: "Whey"), grams: 60)
        viewModel.save(in: context)

        let recipes = try context.fetch(FetchDescriptor<Recipe>())
        #expect(recipes.count == 1)
        let recipe = try #require(recipes.first)
        #expect(recipe.name == "Pancakes")
        #expect(recipe.servings == 3)
        #expect(recipe.sortedIngredients.map(\.foodName) == ["Oats", "Whey"])
        #expect(recipe.sortedIngredients.map(\.orderIndex) == [0, 1])
        #expect(abs(recipe.totalCalories - 260) < 0.001)
        #expect(try context.fetchCount(FetchDescriptor<RecipeIngredient>()) == 2)
    }

    @Test func saveDoesNothingWhenInvalid() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let viewModel = RecipeBuilderViewModel()
        viewModel.addIngredient(from: makeItem(), grams: 100)
        viewModel.save(in: context)   // no name

        #expect(try context.fetchCount(FetchDescriptor<Recipe>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<RecipeIngredient>()) == 0)
    }

    @Test func cancellingWithoutSaveLeavesContextUntouched() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let viewModel = RecipeBuilderViewModel()
        viewModel.name = "Abandoned"
        viewModel.addIngredient(from: makeItem(), grams: 100)
        // Builder dismissed without save(in:) — drafts are value types.

        #expect(try context.fetchCount(FetchDescriptor<Recipe>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<RecipeIngredient>()) == 0)
    }
}
