//
//  RecipeDetailViewModelTests.swift
//  VoraTests
//
//  Created by Majd Arow on 2026-07-25.
//

import Foundation
import SwiftData
import Testing
@testable import Vora

struct RecipeDetailViewModelTests {
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

    /// Totals: 400 g, 800 kcal, 50 P, 80 C, 15 F. With 4 servings:
    /// 100 g, 200 kcal, 12.5 P, 20 C, 3.75 F per serving.
    private func makeRecipe(servings: Int = 4) -> Recipe {
        Recipe(name: "Batch Chili", servings: servings, ingredients: [
            RecipeIngredient(foodName: "Beef", servingGrams: 300, calories: 600,
                             proteinG: 40, carbsG: 60, fatG: 10, orderIndex: 0),
            RecipeIngredient(foodName: "Beans", servingGrams: 100, calories: 200,
                             proteinG: 10, carbsG: 20, fatG: 5, orderIndex: 1),
        ])
    }

    // MARK: - Per-serving math

    @Test func perServingDividesTotalsByServings() {
        let recipe = makeRecipe()
        #expect(abs(recipe.perServingCalories - 200) < 0.001)
        #expect(abs(recipe.perServingProteinG - 12.5) < 0.001)
        #expect(abs(recipe.perServingCarbsG - 20) < 0.001)
        #expect(abs(recipe.perServingFatG - 3.75) < 0.001)
    }

    @Test func perServingGuardsAgainstZeroServings() {
        let recipe = makeRecipe(servings: 1)
        // The init clamps, but hand-set values must not divide by zero either.
        recipe.servings = 0
        #expect(abs(recipe.perServingCalories - 800) < 0.001)
    }

    @Test func initClampsServingsToAtLeastOne() {
        #expect(Recipe(name: "X", servings: 0).servings == 1)
        #expect(Recipe(name: "X", servings: -3).servings == 1)
    }

    // MARK: - Servings stepper

    @Test func adjustServingsClampsBetweenOneAndTwenty() {
        let viewModel = RecipeDetailViewModel(recipe: makeRecipe())
        viewModel.adjustServings(by: -5)
        #expect(viewModel.servingsToLog == 1)
        viewModel.adjustServings(by: 100)
        #expect(viewModel.servingsToLog == 20)
    }

    @Test func portionScalesWithServingsToLog() {
        let viewModel = RecipeDetailViewModel(recipe: makeRecipe())
        viewModel.servingsToLog = 3
        // factor 3/4: 300 g, 600 kcal, 37.5 P, 60 C, 11.25 F.
        #expect(abs(viewModel.portion.grams - 300) < 0.001)
        #expect(abs(viewModel.portion.calories - 600) < 0.001)
        #expect(abs(viewModel.portion.proteinG - 37.5) < 0.001)
        #expect(abs(viewModel.portion.carbsG - 60) < 0.001)
        #expect(abs(viewModel.portion.fatG - 11.25) < 0.001)
    }

    // MARK: - Logging

    @Test func logInsertsSingleEntryNamedAfterRecipe() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let recipe = makeRecipe()
        context.insert(recipe)
        try context.save()

        let logDate = Calendar.current.startOfDay(for: .now).addingTimeInterval(13 * 3600)
        let viewModel = RecipeDetailViewModel(recipe: recipe)
        viewModel.log(to: .lunch, on: logDate, context: context)

        let entries = try context.fetch(FetchDescriptor<FoodEntry>())
        #expect(entries.count == 1)
        let entry = try #require(entries.first)
        #expect(entry.foodName == "Batch Chili")
        #expect(entry.mealSlot == .lunch)
        #expect(entry.date == logDate)
        #expect(abs(entry.servingGrams - 100) < 0.001)
        #expect(abs(entry.calories - 200) < 0.001)
        #expect(abs(entry.proteinG - 12.5) < 0.001)
        #expect(abs(entry.carbsG - 20) < 0.001)
        #expect(abs(entry.fatG - 3.75) < 0.001)
        #expect(entry.fibreG == 0)
        #expect(entry.sugarG == 0)
        #expect(entry.sodiumMg == 0)
    }

    @Test func logRespectsChosenServingCount() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let recipe = makeRecipe()
        context.insert(recipe)
        try context.save()

        let viewModel = RecipeDetailViewModel(recipe: recipe)
        viewModel.servingsToLog = 3
        viewModel.log(to: .dinner, on: .now, context: context)

        let entry = try #require(try context.fetch(FetchDescriptor<FoodEntry>()).first)
        #expect(abs(entry.servingGrams - 300) < 0.001)
        #expect(abs(entry.calories - 600) < 0.001)
    }
}
