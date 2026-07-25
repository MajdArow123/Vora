//
//  NutritionProgressViewModelTests.swift
//  VoraTests
//
//  Created by Majd Arow on 2026-07-25.
//

import Foundation
import SwiftData
import Testing
@testable import Vora

struct NutritionProgressViewModelTests {
    private let calendar = Calendar.current
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    private func day(_ offset: Int, hour: Double = 12) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))!
            .addingTimeInterval(hour * 3600)
    }

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

    private func makeEntry(date: Date, calories: Double, protein: Double) -> FoodEntry {
        FoodEntry(
            date: date,
            mealSlot: .lunch,
            foodName: "Test Food",
            servingGrams: 100,
            calories: calories,
            proteinG: protein,
            carbsG: 10,
            fatG: 5,
            fibreG: 2,
            sugarG: 1,
            sodiumMg: 100
        )
    }

    // MARK: - Daily totals

    @Test func multipleEntriesPerDayAreSummed() {
        let entries = [
            makeEntry(date: day(0, hour: 8), calories: 400, protein: 20),
            makeEntry(date: day(0, hour: 13), calories: 600, protein: 40),
            makeEntry(date: day(0, hour: 19), calories: 500, protein: 35),
        ]
        let points = NutritionProgressViewModel.dailyTotals(
            entries: entries, range: .month, now: now, calendar: calendar
        )
        #expect(points.count == 1)
        #expect(points.first?.calories == 1500)
        #expect(points.first?.proteinG == 95)
        #expect(points.first?.day == calendar.startOfDay(for: now))
    }

    @Test func untrackedDaysAreOmittedNotZero() {
        let entries = [
            makeEntry(date: day(-4), calories: 2000, protein: 150),
            makeEntry(date: day(0), calories: 2200, protein: 160),
        ]
        let points = NutritionProgressViewModel.dailyTotals(
            entries: entries, range: .month, now: now, calendar: calendar
        )
        #expect(points.count == 2)
        #expect(!points.contains { $0.calories == 0 })
    }

    @Test func rangeCutoffExcludesOldEntries() {
        let entries = [
            makeEntry(date: day(-45), calories: 1800, protein: 120),
            makeEntry(date: day(-2), calories: 2100, protein: 155),
        ]
        let month = NutritionProgressViewModel.dailyTotals(
            entries: entries, range: .month, now: now, calendar: calendar
        )
        #expect(month.count == 1)
        #expect(month.first?.calories == 2100)

        let all = NutritionProgressViewModel.dailyTotals(
            entries: entries, range: .all, now: now, calendar: calendar
        )
        #expect(all.count == 2)
    }

    @Test func pointsAreSortedAscendingByDay() {
        let entries = [
            makeEntry(date: day(0), calories: 2200, protein: 160),
            makeEntry(date: day(-7), calories: 2000, protein: 150),
            makeEntry(date: day(-3), calories: 2100, protein: 155),
        ]
        let points = NutritionProgressViewModel.dailyTotals(
            entries: entries, range: .month, now: now, calendar: calendar
        )
        #expect(points.map(\.calories) == [2000, 2100, 2200])
    }

    // MARK: - Load

    @Test func loadReadsTargetsFromProfile() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        context.insert(UserProfile(
            name: "Test User",
            dateOfBirth: calendar.date(byAdding: .year, value: -30, to: now)!,
            heightCm: 180,
            biologicalSex: .male,
            goalType: .fatLoss,
            activityLevel: .moderatelyActive,
            trainingSplit: .ppl,
            dailyCalorieTarget: 2400,
            proteinTargetG: 170,
            carbsTargetG: 250,
            fatTargetG: 70
        ))
        context.insert(makeEntry(date: day(-1), calories: 2000, protein: 150))
        context.insert(makeEntry(date: day(0), calories: 2200, protein: 160))
        try context.save()

        let viewModel = NutritionProgressViewModel()
        viewModel.load(from: context, now: now)

        #expect(viewModel.calorieTarget == 2400)
        #expect(viewModel.proteinTarget == 170)
        #expect(viewModel.dailyPoints.count == 2)
    }

    @Test func loadWithoutProfileLeavesTargetsZero() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let viewModel = NutritionProgressViewModel()
        viewModel.load(from: context, now: now)

        #expect(viewModel.calorieTarget == 0)
        #expect(viewModel.proteinTarget == 0)
        #expect(viewModel.dailyPoints.isEmpty)
    }
}
