//
//  SavedMealDetailViewModelTests.swift
//  VoraTests
//
//  Created by Majd Arow on 2026-07-25.
//

import Foundation
import SwiftData
import Testing
@testable import Vora

struct SavedMealDetailViewModelTests {
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

    private func makeMeal() -> SavedMeal {
        SavedMeal(name: "Typical Breakfast", items: [
            SavedMealItem(foodName: "Oats", servingGrams: 80, calories: 300,
                          proteinG: 10, carbsG: 54, fatG: 6, orderIndex: 0),
            SavedMealItem(foodName: "Greek Yogurt", servingGrams: 170, calories: 165,
                          proteinG: 15, carbsG: 7, fatG: 8, orderIndex: 1),
        ])
    }

    @Test func totalsSumAllItems() {
        let meal = makeMeal()
        #expect(meal.totalCalories == 465)
        #expect(meal.totalProteinG == 25)
        #expect(meal.totalCarbsG == 61)
        #expect(meal.totalFatG == 14)
    }

    @Test func sortedItemsFollowOrderIndex() {
        let meal = SavedMeal(name: "Shuffled", items: [
            SavedMealItem(foodName: "Second", servingGrams: 1, calories: 1,
                          proteinG: 0, carbsG: 0, fatG: 0, orderIndex: 1),
            SavedMealItem(foodName: "First", servingGrams: 1, calories: 1,
                          proteinG: 0, carbsG: 0, fatG: 0, orderIndex: 0),
        ])
        #expect(meal.sortedItems.map(\.foodName) == ["First", "Second"])
    }

    @Test func logInsertsOneEntryPerItemInTheGivenSlot() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let meal = makeMeal()
        context.insert(meal)
        try context.save()

        let logDate = Calendar.current.startOfDay(for: .now).addingTimeInterval(12 * 3600)
        let viewModel = SavedMealDetailViewModel(meal: meal)
        viewModel.log(to: .dinner, on: logDate, context: context)

        let entries = try context.fetch(FetchDescriptor<FoodEntry>(
            sortBy: [SortDescriptor(\.foodName)]
        ))
        #expect(entries.count == 2)
        #expect(entries.allSatisfy { $0.mealSlot == .dinner })
        #expect(entries.allSatisfy { $0.date == logDate })

        let oats = try #require(entries.first { $0.foodName == "Oats" })
        #expect(oats.servingGrams == 80)
        #expect(oats.calories == 300)
        #expect(oats.proteinG == 10)
        #expect(oats.carbsG == 54)
        #expect(oats.fatG == 6)
        // SavedMealItem doesn't carry these; they log as zero.
        #expect(oats.fibreG == 0)
        #expect(oats.sugarG == 0)
        #expect(oats.sodiumMg == 0)
    }

    @Test func loggingTwiceDuplicatesEntries() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let meal = makeMeal()
        context.insert(meal)
        try context.save()

        let viewModel = SavedMealDetailViewModel(meal: meal)
        viewModel.log(to: .lunch, on: .now, context: context)
        viewModel.log(to: .lunch, on: .now, context: context)

        #expect(try context.fetchCount(FetchDescriptor<FoodEntry>()) == 4)
    }
}
