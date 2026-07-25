//
//  OnboardingViewModelTests.swift
//  VoraTests
//
//  Created by Majd Arow on 2026-07-21.
//

import Foundation
import SwiftData
import Testing
@testable import Vora

struct OnboardingViewModelTests {
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

    /// A view model filled in to the point where onboarding can finish.
    private func filledViewModel() -> OnboardingViewModel {
        let vm = OnboardingViewModel()
        vm.name = "  Majd Arow  "
        vm.biologicalSex = .male
        vm.goalType = .muscleGain
        vm.activityLevel = .veryActive
        vm.trainingSplit = .ppl
        vm.caloriesText = "2800"
        vm.proteinText = "160"
        vm.carbsText = "330"
        vm.fatText = "80"
        vm.waterText = "3000"
        return vm
    }

    // MARK: - Step gating

    @Test func welcomeAndSummaryAlwaysContinue() {
        let vm = OnboardingViewModel()
        vm.step = .welcome
        #expect(vm.canContinue)
        vm.step = .summary
        #expect(vm.canContinue)
    }

    @Test func basicsRequiresNameAndSex() {
        let vm = OnboardingViewModel()
        vm.step = .basics
        #expect(!vm.canContinue)
        vm.name = "   "
        vm.biologicalSex = .female
        #expect(!vm.canContinue)
        vm.name = "Sam"
        #expect(vm.canContinue)
        vm.biologicalSex = nil
        #expect(!vm.canContinue)
    }

    @Test func goalRequiresGoalAndActivity() {
        let vm = OnboardingViewModel()
        vm.step = .goal
        #expect(!vm.canContinue)
        vm.goalType = .fatLoss
        #expect(!vm.canContinue)
        vm.activityLevel = .sedentary
        #expect(vm.canContinue)
    }

    @Test(arguments: [
        ("0", "150", "250", "70", "3000"),
        ("2400", "0", "250", "70", "3000"),
        ("2400", "150", "abc", "70", "3000"),
        ("2400", "150", "250", "", "3000"),
        ("2400", "150", "250", "70", "-1"),
    ])
    func targetsRejectInvalidValues(calories: String, protein: String, carbs: String, fat: String, water: String) {
        let vm = OnboardingViewModel()
        vm.step = .targets
        vm.caloriesText = calories
        vm.proteinText = protein
        vm.carbsText = carbs
        vm.fatText = fat
        vm.waterText = water
        #expect(!vm.canContinue)
    }

    @Test func targetsAcceptPositiveIntegers() {
        let vm = filledViewModel()
        vm.step = .targets
        #expect(vm.canContinue)
    }

    @Test func trainingSplitRequiresSelection() {
        let vm = OnboardingViewModel()
        vm.step = .trainingSplit
        #expect(!vm.canContinue)
        vm.trainingSplit = .fullBody
        #expect(vm.canContinue)
    }

    // MARK: - Navigation

    @Test func advanceWalksAllStepsAndStopsAtSummary() {
        let vm = OnboardingViewModel()
        let expected: [OnboardingStep] = [.welcome, .basics, .goal, .targets, .trainingSplit, .summary]
        for step in expected {
            #expect(vm.step == step)
            vm.advance()
        }
        #expect(vm.step == .summary)
    }

    @Test func goBackStopsAtWelcome() {
        let vm = OnboardingViewModel()
        #expect(!vm.canGoBack)
        vm.goBack()
        #expect(vm.step == .welcome)
        vm.advance()
        #expect(vm.canGoBack)
        vm.goBack()
        #expect(vm.step == .welcome)
    }

    @Test func advancingPastGoalSuggestsTargetsOnce() {
        let vm = OnboardingViewModel()
        vm.biologicalSex = .male
        vm.goalType = .maintain
        vm.activityLevel = .moderatelyActive
        vm.step = .goal

        vm.advance()
        #expect(vm.step == .targets)
        let suggested = vm.caloriesText
        #expect(Int(suggested) ?? 0 > 0)
        #expect(Int(vm.waterText) ?? 0 >= 2000)

        // User edits survive revisiting the goal step.
        vm.caloriesText = "1234"
        vm.goBack()
        vm.advance()
        #expect(vm.caloriesText == "1234")
    }

    @Test func noSuggestionWithoutGoalInputs() {
        let vm = OnboardingViewModel()
        vm.step = .goal
        vm.advance()
        #expect(vm.caloriesText.isEmpty)
    }

    // MARK: - Unit bindings

    @Test func heightAndWeightSelectionBindingsRoundTrip() {
        let vm = OnboardingViewModel()
        vm.heightCmSelection = 182
        #expect(vm.heightCm == 182)
        vm.weightKgSelection = 91
        #expect(vm.weightKg == 91)

        vm.heightFeet = 6
        let inches = vm.heightInches
        vm.heightInches = inches
        #expect(vm.heightFeet == 6)

        vm.weightPounds = 200
        #expect(abs(vm.weightKg - 90.72) < 0.1)
    }

    @Test func derivedTextsAndAge() {
        let vm = OnboardingViewModel()
        vm.preferredUnits = .metric
        #expect(!vm.heightText.isEmpty)
        #expect(!vm.weightText.isEmpty)
        #expect(vm.age == 25)
        #expect(vm.dateOfBirthRange.contains(vm.dateOfBirth))
    }

    // MARK: - Completion

    @Test func completeOnboardingCreatesProfileAndFirstWeighIn() throws {
        let context = try makeContext()
        let vm = filledViewModel()
        vm.step = .summary
        vm.weightKg = 82.5

        vm.completeOnboarding(in: context)

        let profile = try #require(try context.fetch(FetchDescriptor<UserProfile>()).first)
        #expect(profile.name == "Majd Arow")
        #expect(profile.dailyCalorieTarget == 2800)
        #expect(profile.proteinTargetG == 160)
        #expect(profile.carbsTargetG == 330)
        #expect(profile.fatTargetG == 80)
        #expect(profile.waterTargetMl == 3000)
        #expect(profile.trainingSplit == .ppl)
        #expect(profile.goalWeightKg == 0)

        let weights = try context.fetch(FetchDescriptor<WeightEntry>())
        #expect(weights.count == 1)
        #expect(weights.first?.weightKg == 82.5)
    }

    @Test func completeOnboardingRefusesIncompleteData() throws {
        let context = try makeContext()
        let vm = filledViewModel()
        vm.trainingSplit = nil

        vm.completeOnboarding(in: context)

        #expect(try context.fetch(FetchDescriptor<UserProfile>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<WeightEntry>()).isEmpty)
    }
}
