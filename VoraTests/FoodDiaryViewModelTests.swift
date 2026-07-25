//
//  FoodDiaryViewModelTests.swift
//  VoraTests
//
//  Created by Majd Arow on 2026-07-21.
//

import Foundation
import SwiftData
import Testing
@testable import Vora

struct FoodDiaryViewModelTests {
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

    private func seedProfile(into context: ModelContext, calorieTarget: Int = 2400) {
        let cal = Calendar.current
        context.insert(UserProfile(
            name: "Test User",
            dateOfBirth: cal.date(byAdding: .year, value: -30, to: .now)!,
            heightCm: 180,
            biologicalSex: .male,
            goalType: .fatLoss,
            activityLevel: .moderatelyActive,
            trainingSplit: .ppl,
            dailyCalorieTarget: calorieTarget,
            proteinTargetG: 170,
            carbsTargetG: 250,
            fatTargetG: 70,
            goalWeightKg: 78
        ))
    }

    private func entry(
        on day: Date,
        hourOffset: Double,
        slot: MealSlot = .lunch,
        name: String = "Food",
        calories: Double = 500,
        protein: Double = 30,
        carbs: Double = 50,
        fat: Double = 15,
        fibre: Double = 5,
        sugar: Double = 10,
        sodium: Double = 400
    ) -> FoodEntry {
        FoodEntry(
            date: day.addingTimeInterval(hourOffset * 3600),
            mealSlot: slot,
            foodName: name,
            servingGrams: 200,
            calories: calories,
            proteinG: protein,
            carbsG: carbs,
            fatG: fat,
            fibreG: fibre,
            sugarG: sugar,
            sodiumMg: sodium
        )
    }

    // MARK: - Loading and day filtering

    @Test func loadFiltersEntriesToSelectedDayOnly() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let viewModel = FoodDiaryViewModel()
        let cal = Calendar.current
        let today = viewModel.selectedDate
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today)!

        context.insert(entry(on: today, hourOffset: 8, name: "Today Breakfast"))
        context.insert(entry(on: today, hourOffset: 23.9, name: "Today Late"))
        context.insert(entry(on: yesterday, hourOffset: 12, name: "Yesterday Lunch"))
        context.insert(entry(on: tomorrow, hourOffset: 0, name: "Tomorrow Midnight"))
        try context.save()

        viewModel.load(from: context)

        #expect(viewModel.entries.count == 2)
        #expect(Set(viewModel.entries.map(\.foodName)) == ["Today Breakfast", "Today Late"])
    }

    @Test func totalsSumEveryNutrient() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let viewModel = FoodDiaryViewModel()
        let today = viewModel.selectedDate

        context.insert(entry(
            on: today, hourOffset: 8,
            calories: 420.5, protein: 25.5, carbs: 40.25, fat: 12.5,
            fibre: 4.5, sugar: 8.25, sodium: 350
        ))
        context.insert(entry(
            on: today, hourOffset: 13,
            calories: 610, protein: 44.5, carbs: 55.75, fat: 20,
            fibre: 7.5, sugar: 3.75, sodium: 620
        ))
        try context.save()

        viewModel.load(from: context)

        #expect(abs(viewModel.totalCalories - 1030.5) < 0.0001)
        #expect(abs(viewModel.totalProtein - 70.0) < 0.0001)
        #expect(abs(viewModel.totalCarbs - 96.0) < 0.0001)
        #expect(abs(viewModel.totalFat - 32.5) < 0.0001)
        #expect(abs(viewModel.totalFibre - 12.0) < 0.0001)
        #expect(abs(viewModel.totalSugar - 12.0) < 0.0001)
        #expect(abs(viewModel.totalSodiumMg - 970.0) < 0.0001)
    }

    @Test func totalsAreZeroOnEmptyDay() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let viewModel = FoodDiaryViewModel()

        viewModel.load(from: context)

        #expect(viewModel.totalCalories == 0)
        #expect(viewModel.totalProtein == 0)
        #expect(viewModel.totalSodiumMg == 0)
    }

    @Test func entriesForSlotFiltersBySlot() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let viewModel = FoodDiaryViewModel()
        let today = viewModel.selectedDate

        context.insert(entry(on: today, hourOffset: 8, slot: .breakfast, name: "Oats"))
        context.insert(entry(on: today, hourOffset: 9, slot: .breakfast, name: "Eggs"))
        context.insert(entry(on: today, hourOffset: 13, slot: .lunch, name: "Chicken"))
        context.insert(entry(on: today, hourOffset: 16, slot: .postWorkout, name: "Shake"))
        try context.save()

        viewModel.load(from: context)

        #expect(viewModel.entries(for: .breakfast).map(\.foodName) == ["Oats", "Eggs"])
        #expect(viewModel.entries(for: .lunch).map(\.foodName) == ["Chicken"])
        #expect(viewModel.entries(for: .postWorkout).map(\.foodName) == ["Shake"])
        #expect(viewModel.entries(for: .dinner).isEmpty)
        #expect(viewModel.entries(for: .snack).isEmpty)
    }

    // MARK: - Date navigation

    @Test func dateNavigationReloadsTheRightDay() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let viewModel = FoodDiaryViewModel()
        let cal = Calendar.current
        let today = viewModel.selectedDate
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today)!

        context.insert(entry(on: today, hourOffset: 12, name: "Today"))
        context.insert(entry(on: yesterday, hourOffset: 12, name: "Yesterday"))
        context.insert(entry(on: tomorrow, hourOffset: 12, name: "Tomorrow"))
        try context.save()

        viewModel.load(from: context)
        #expect(viewModel.entries.map(\.foodName) == ["Today"])

        viewModel.goToPreviousDay(context: context)
        #expect(viewModel.selectedDate == yesterday)
        #expect(viewModel.entries.map(\.foodName) == ["Yesterday"])

        viewModel.goToNextDay(context: context)
        #expect(viewModel.selectedDate == today)
        #expect(viewModel.entries.map(\.foodName) == ["Today"])

        viewModel.goToNextDay(context: context)
        #expect(viewModel.selectedDate == tomorrow)
        #expect(viewModel.entries.map(\.foodName) == ["Tomorrow"])
    }

    // MARK: - Remaining calories

    @Test func remainingCaloriesSubtractsRoundedTotalFromTarget() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        seedProfile(into: context, calorieTarget: 2400)
        let viewModel = FoodDiaryViewModel()
        let today = viewModel.selectedDate

        context.insert(entry(on: today, hourOffset: 8, calories: 300.6))
        try context.save()

        viewModel.load(from: context)

        #expect(viewModel.calorieTarget == 2400)
        // 300.6 rounds to 301.
        #expect(viewModel.remainingCalories == 2400 - 301)
    }

    @Test func remainingCaloriesGoesNegativeWithoutProfile() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let viewModel = FoodDiaryViewModel()
        let today = viewModel.selectedDate

        context.insert(entry(on: today, hourOffset: 8, calories: 500))
        try context.save()

        viewModel.load(from: context)

        #expect(viewModel.calorieTarget == 0)
        #expect(viewModel.remainingCalories == -500)
    }

    // MARK: - Water

    @Test func glassCountFloorsPartialGlasses() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let viewModel = FoodDiaryViewModel()
        let today = viewModel.selectedDate

        context.insert(WaterEntry(date: today.addingTimeInterval(8 * 3600), amountMl: 250))
        context.insert(WaterEntry(date: today.addingTimeInterval(9 * 3600), amountMl: 250))
        context.insert(WaterEntry(date: today.addingTimeInterval(10 * 3600), amountMl: 100))
        try context.save()

        viewModel.load(from: context)

        #expect(viewModel.waterTotalMl == 600)
        // 600 / 250 = 2.4 -> floors to 2 full glasses.
        #expect(viewModel.glassCount == 2)
    }

    @Test func glassCountIsZeroWithNoWater() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let viewModel = FoodDiaryViewModel()

        viewModel.load(from: context)

        #expect(viewModel.glassCount == 0)
        #expect(viewModel.waterTotalMl == 0)
    }

    @Test func addGlassInsertsOneGlassAndReloads() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let viewModel = FoodDiaryViewModel()
        viewModel.load(from: context)
        #expect(viewModel.glassCount == 0)

        viewModel.addGlass(context: context)

        #expect(viewModel.glassCount == 1)
        #expect(viewModel.waterTotalMl == FoodDiaryViewModel.glassMl)
        let persisted = try context.fetch(FetchDescriptor<WaterEntry>())
        #expect(persisted.count == 1)
        #expect(persisted.first?.amountMl == FoodDiaryViewModel.glassMl)
    }

    @Test func removeGlassDeletesTheLatestEntry() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let viewModel = FoodDiaryViewModel()
        let today = viewModel.selectedDate

        context.insert(WaterEntry(date: today.addingTimeInterval(8 * 3600), amountMl: 300))
        context.insert(WaterEntry(date: today.addingTimeInterval(10 * 3600), amountMl: 250))
        try context.save()

        viewModel.load(from: context)
        viewModel.removeGlass(context: context)

        // The 10:00 entry (latest) is removed; the 8:00 one remains.
        #expect(viewModel.waterEntries.count == 1)
        #expect(viewModel.waterTotalMl == 300)
        let persisted = try context.fetch(FetchDescriptor<WaterEntry>())
        #expect(persisted.count == 1)
        #expect(persisted.first?.amountMl == 300)
    }

    @Test func removeGlassOnEmptyDayIsANoOp() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let viewModel = FoodDiaryViewModel()
        viewModel.load(from: context)

        viewModel.removeGlass(context: context)

        #expect(viewModel.waterEntries.isEmpty)
        let persisted = try context.fetch(FetchDescriptor<WaterEntry>())
        #expect(persisted.isEmpty)
    }

    @Test func waterTargetFallsBackTo3500WithoutProfile() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let viewModel = FoodDiaryViewModel()

        viewModel.load(from: context)

        #expect(viewModel.waterTargetMl == 3500)
    }

    // MARK: - Entry deletion

    @Test func deleteRemovesTheEntryAndReloads() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let viewModel = FoodDiaryViewModel()
        let today = viewModel.selectedDate

        context.insert(entry(on: today, hourOffset: 8, name: "Keep"))
        let doomed = entry(on: today, hourOffset: 9, name: "Doomed")
        context.insert(doomed)
        try context.save()

        viewModel.load(from: context)
        viewModel.delete(doomed, context: context)

        #expect(viewModel.entries.map(\.foodName) == ["Keep"])
        let persisted = try context.fetch(FetchDescriptor<FoodEntry>())
        #expect(persisted.count == 1)
    }

    // MARK: - Copy previous day

    @Test func copyPreviousDayDuplicatesEntriesPreservingTimeOfDay() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let viewModel = FoodDiaryViewModel()
        let cal = Calendar.current
        let today = viewModel.selectedDate
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!

        let breakfast = entry(
            on: yesterday, hourOffset: 7.5, slot: .breakfast, name: "Oats",
            calories: 380, protein: 13, carbs: 66, fat: 7, fibre: 10, sugar: 1, sodium: 6
        )
        let dinner = entry(
            on: yesterday, hourOffset: 19, slot: .dinner, name: "Salmon",
            calories: 520, protein: 42, carbs: 5, fat: 34, fibre: 0, sugar: 2, sodium: 480
        )
        context.insert(breakfast)
        context.insert(dinner)
        try context.save()

        viewModel.load(from: context)
        #expect(viewModel.entries.isEmpty)

        viewModel.copyPreviousDay(context: context)

        #expect(viewModel.entries.count == 2)

        let copiedBreakfast = try #require(viewModel.entries.first { $0.foodName == "Oats" })
        let expectedBreakfastDate = today.addingTimeInterval(breakfast.date.timeIntervalSince(yesterday))
        #expect(copiedBreakfast.date == expectedBreakfastDate)
        #expect(copiedBreakfast.mealSlot == .breakfast)
        #expect(copiedBreakfast.servingGrams == 200)
        #expect(copiedBreakfast.calories == 380)
        #expect(copiedBreakfast.proteinG == 13)
        #expect(copiedBreakfast.carbsG == 66)
        #expect(copiedBreakfast.fatG == 7)
        #expect(copiedBreakfast.fibreG == 10)
        #expect(copiedBreakfast.sugarG == 1)
        #expect(copiedBreakfast.sodiumMg == 6)

        let copiedDinner = try #require(viewModel.entries.first { $0.foodName == "Salmon" })
        let expectedDinnerDate = today.addingTimeInterval(dinner.date.timeIntervalSince(yesterday))
        #expect(copiedDinner.date == expectedDinnerDate)
        #expect(copiedDinner.mealSlot == .dinner)

        // The originals are untouched; the copies are new rows.
        let all = try context.fetch(FetchDescriptor<FoodEntry>())
        #expect(all.count == 4)
    }

    @Test func copyPreviousDayDoesNothingWhenPreviousDayIsEmpty() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let viewModel = FoodDiaryViewModel()
        let cal = Calendar.current
        let today = viewModel.selectedDate
        // An entry two days back must not be picked up.
        let twoDaysAgo = cal.date(byAdding: .day, value: -2, to: today)!
        context.insert(entry(on: twoDaysAgo, hourOffset: 12, name: "Old"))
        try context.save()

        viewModel.load(from: context)
        viewModel.copyPreviousDay(context: context)

        #expect(viewModel.entries.isEmpty)
        let all = try context.fetch(FetchDescriptor<FoodEntry>())
        #expect(all.count == 1)
    }

    // MARK: - Log timestamp

    @Test func logTimestampIsMiddayForNonTodayDays() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let viewModel = FoodDiaryViewModel()

        viewModel.goToPreviousDay(context: context)
        #expect(viewModel.logTimestamp == viewModel.selectedDate.addingTimeInterval(12 * 3600))

        viewModel.goToNextDay(context: context)
        viewModel.goToNextDay(context: context)
        #expect(viewModel.logTimestamp == viewModel.selectedDate.addingTimeInterval(12 * 3600))
    }

    @Test func logTimestampIsNowForToday() throws {
        let viewModel = FoodDiaryViewModel()
        // Guard against the pathological midnight rollover between the view
        // model's init and this assertion; the branch only applies to today.
        guard Calendar.current.isDateInToday(viewModel.selectedDate) else { return }
        #expect(abs(viewModel.logTimestamp.timeIntervalSinceNow) < 5)
    }
}
