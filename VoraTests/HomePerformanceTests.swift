//
//  HomePerformanceTests.swift
//  VoraTests
//
//  Created by Majd Arow on 2026-07-21.
//

import Foundation
import SwiftData
import Testing
@testable import Vora

struct HomePerformanceTests {
    /// Quality gate: HomeViewModel loads in under 400ms against 90 days
    /// of realistic synthetic data.
    @Test func homeLoadsUnder400msWith90DaysOfData() throws {
        let schema = Schema([
            UserProfile.self, FoodEntry.self, CustomFood.self,
            WorkoutSession.self, ExerciseLog.self, SetEntry.self,
            WeightEntry.self, WaterEntry.self, CardioEntry.self, SplitDay.self,
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        seedNinetyDays(into: context)
        try context.save()

        let defaults = UserDefaults(suiteName: "vora.tests.home-performance")!
        defaults.removePersistentDomain(forName: "vora.tests.home-performance")
        let viewModel = HomeViewModel(defaults: defaults)

        let clock = ContinuousClock()
        let elapsed = clock.measure {
            viewModel.load(from: context)
        }

        #expect(elapsed < .milliseconds(400), "Home load took \(elapsed)")
        #expect(viewModel.profile != nil)
        #expect(viewModel.insight != nil)
        #expect(viewModel.weekDots.count == 7)
    }

    private func seedNinetyDays(into context: ModelContext) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)

        context.insert(UserProfile(
            name: "Synthetic User",
            dateOfBirth: cal.date(byAdding: .year, value: -30, to: today)!,
            heightCm: 180,
            biologicalSex: .male,
            goalType: .fatLoss,
            activityLevel: .moderatelyActive,
            trainingSplit: .ppl,
            dailyCalorieTarget: 2400,
            proteinTargetG: 170,
            carbsTargetG: 250,
            fatTargetG: 70,
            goalWeightKg: 78
        ))

        for (index, template) in TrainingSplit.ppl.weeklyTemplate.enumerated() {
            context.insert(SplitDay(
                dayIndex: index,
                title: template.title,
                muscleGroups: template.muscleGroups,
                isRest: template.isRest
            ))
        }

        for dayOffset in 0..<90 {
            let day = cal.date(byAdding: .day, value: -dayOffset, to: today)!

            for meal in [MealSlot.breakfast, .lunch, .dinner, .snack] {
                context.insert(FoodEntry(
                    date: day.addingTimeInterval(10 * 3600),
                    mealSlot: meal,
                    foodName: "Synthetic \(meal.rawValue)",
                    servingGrams: 300,
                    calories: 550,
                    proteinG: 35,
                    carbsG: 55,
                    fatG: 18
                ))
            }

            for glass in 0..<8 {
                context.insert(WaterEntry(
                    date: day.addingTimeInterval(Double(8 + glass) * 3600),
                    amountMl: 250
                ))
            }

            context.insert(WeightEntry(
                date: day.addingTimeInterval(7 * 3600),
                weightKg: 84 - Double(90 - dayOffset) * 0.03
            ))

            if dayOffset % 2 == 0 {
                let exercises = (0..<6).map { exerciseIndex in
                    let sets = (1...3).map { setNumber in
                        SetEntry(setNumber: setNumber, weightKg: 60, reps: 10, isCompleted: true)
                    }
                    return ExerciseLog(
                        exerciseName: "Exercise \(exerciseIndex)",
                        orderIndex: exerciseIndex,
                        sets: sets
                    )
                }
                context.insert(WorkoutSession(
                    date: day.addingTimeInterval(18 * 3600),
                    sessionName: "Synthetic Session",
                    durationSeconds: 3600,
                    totalVolumeKg: 10_800,
                    exercises: exercises
                ))
            }
        }
    }
}
