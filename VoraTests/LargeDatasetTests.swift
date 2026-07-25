//
//  LargeDatasetTests.swift
//  VoraTests
//
//  Created by Majd Arow on 2026-07-21.
//

import Foundation
import SwiftData
import Testing
@testable import Vora

/// Edge case from the Phase 5 quality gate: a full year of data must
/// load correctly and stay responsive on every screen's view model.
struct LargeDatasetTests {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            UserProfile.self, FoodEntry.self, CustomFood.self,
            WorkoutSession.self, ExerciseLog.self, SetEntry.self,
            WeightEntry.self, WaterEntry.self, CardioEntry.self, SplitDay.self,
            SavedMeal.self, SavedMealItem.self, Recipe.self, RecipeIngredient.self,
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    private func seedYear(into context: ModelContext) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)

        context.insert(UserProfile(
            name: "Year User",
            dateOfBirth: cal.date(byAdding: .year, value: -28, to: today)!,
            heightCm: 172,
            biologicalSex: .female,
            goalType: .fatLoss,
            activityLevel: .veryActive,
            trainingSplit: .upperLower,
            dailyCalorieTarget: 2000,
            proteinTargetG: 140,
            carbsTargetG: 200,
            fatTargetG: 60,
            goalWeightKg: 62
        ))

        for dayOffset in 0..<365 {
            let day = cal.date(byAdding: .day, value: -dayOffset, to: today)!
            for meal in [MealSlot.breakfast, .lunch, .dinner] {
                context.insert(FoodEntry(
                    date: day.addingTimeInterval(12 * 3600),
                    mealSlot: meal,
                    foodName: "Meal \(dayOffset)",
                    servingGrams: 350,
                    calories: 600,
                    proteinG: 40,
                    carbsG: 60,
                    fatG: 20
                ))
            }
            context.insert(WaterEntry(date: day.addingTimeInterval(9 * 3600), amountMl: 2000))
            if dayOffset % 3 == 0 {
                context.insert(WeightEntry(
                    date: day.addingTimeInterval(7 * 3600),
                    weightKg: 64 + Double(dayOffset) * 0.01
                ))
            }
            if dayOffset % 2 == 1 {
                context.insert(WorkoutSession(
                    date: day.addingTimeInterval(17 * 3600),
                    sessionName: "Session \(dayOffset)",
                    durationSeconds: 2700,
                    totalVolumeKg: 8000
                ))
            }
        }
    }

    @Test func homeStaysCorrectAndFastWithOneYearOfData() throws {
        let context = try makeContext()
        seedYear(into: context)
        try context.save()

        let defaults = UserDefaults(suiteName: "vora.tests.large-home")!
        defaults.removePersistentDomain(forName: "vora.tests.large-home")
        let viewModel = HomeViewModel(defaults: defaults)

        let elapsed = ContinuousClock().measure {
            viewModel.load(from: context)
        }

        #expect(elapsed < .milliseconds(400), "Home load took \(elapsed)")
        #expect(viewModel.todayFood.count == 3, "today's diary must contain only today's meals")
        #expect(viewModel.glassCount == 8)
        #expect(viewModel.weekDots.count == 7)
        #expect(viewModel.daysTracked == 365)
    }

    @Test func progressStaysCorrectAndFastWithOneYearOfData() throws {
        let context = try makeContext()
        seedYear(into: context)
        try context.save()

        let viewModel = ProgressViewModel()
        let elapsed = ContinuousClock().measure {
            viewModel.load(from: context)
        }

        #expect(elapsed < .milliseconds(400), "Progress load took \(elapsed)")
        #expect(viewModel.allWeightsDescending.count == 122)
        #expect(viewModel.weeklyAverages.count == 4)
        // Weight rises going back in time, so the trend moves toward the
        // 62 kg goal and a projection must exist.
        #expect(viewModel.goalProjection != nil)

        viewModel.selectedRange = .all
        viewModel.rangeChanged()
        #expect(viewModel.rangeWeights.count == 122)

        viewModel.selectedRange = .month
        viewModel.rangeChanged()
        #expect(viewModel.rangeWeights.count < 122)
    }

    /// First-use empty state: no data at all must not crash or produce
    /// nonsense values anywhere.
    @Test func emptyStoreProducesCleanFirstUseState() throws {
        let context = try makeContext()

        let defaults = UserDefaults(suiteName: "vora.tests.empty-home")!
        defaults.removePersistentDomain(forName: "vora.tests.empty-home")
        let home = HomeViewModel(defaults: defaults)
        home.load(from: context)

        #expect(home.profile == nil)
        #expect(home.totalCalories == 0)
        #expect(home.glassCount == 0)
        #expect(home.weekDots == Array(repeating: false, count: 7))
        #expect(home.streakDays == 0)
        #expect(home.insight != nil, "even first use shows the fallback insight")
        #expect(home.weekWeightDeltaKg == nil)

        let progress = ProgressViewModel()
        progress.load(from: context)
        #expect(progress.allWeightsDescending.isEmpty)
        #expect(progress.daysTracked == 0)
        #expect(progress.goalProjection == nil)
        #expect(progress.weeklyAverages.allSatisfy { $0.average == 0 })
    }
}
