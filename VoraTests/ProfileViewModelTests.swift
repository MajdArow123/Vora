//
//  ProfileViewModelTests.swift
//  VoraTests
//
//  Created by Majd Arow on 2026-07-21.
//

import Foundation
import SwiftData
import Testing
@testable import Vora

struct ProfileViewModelTests {
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

    @discardableResult
    private func insertProfile(
        _ context: ModelContext,
        name: String = "Majd Arow",
        goalWeightKg: Double = 78,
        units: UnitSystem = .metric
    ) -> UserProfile {
        let profile = UserProfile(
            name: name,
            dateOfBirth: Calendar.current.date(byAdding: .year, value: -30, to: .now)!,
            heightCm: 180,
            biologicalSex: .male,
            goalType: .fatLoss,
            activityLevel: .moderatelyActive,
            trainingSplit: .ppl,
            dailyCalorieTarget: 2400,
            proteinTargetG: 170,
            carbsTargetG: 250,
            fatTargetG: 70,
            goalWeightKg: goalWeightKg,
            preferredUnits: units
        )
        context.insert(profile)
        return profile
    }

    /// Loaded view model with an editing session already begun.
    private func makeEditingViewModel(
        goalWeightKg: Double = 78
    ) throws -> (ProfileViewModel, ModelContext, UserProfile, ModelContainer) {
        let container = try makeContainer()
        let context = ModelContext(container)
        let profile = insertProfile(context, goalWeightKg: goalWeightKg)
        try context.save()
        let viewModel = ProfileViewModel()
        viewModel.load(from: context)
        viewModel.beginEditing()
        return (viewModel, context, profile, container)
    }

    // MARK: - Loading

    @Test func loadPicksLatestWeightEntry() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        insertProfile(context)
        let cal = Calendar.current
        context.insert(WeightEntry(date: cal.date(byAdding: .day, value: -2, to: .now)!, weightKg: 80))
        context.insert(WeightEntry(date: cal.date(byAdding: .day, value: -1, to: .now)!, weightKg: 79))
        try context.save()

        let viewModel = ProfileViewModel()
        viewModel.load(from: context)

        #expect(viewModel.profile != nil)
        #expect(viewModel.latestWeight?.weightKg == 79)
        #expect(viewModel.weightText == "79 kg")
        #expect(viewModel.heightText == "180 cm")
    }

    // MARK: - Editing lifecycle

    @Test func beginEditingPopulatesAllDraftsFromProfile() throws {
        let (viewModel, _, profile, _) = try makeEditingViewModel()

        #expect(viewModel.isEditing)
        #expect(viewModel.draftName == "Majd Arow")
        #expect(viewModel.draftDateOfBirth == profile.dateOfBirth)
        #expect(viewModel.draftBiologicalSex == .male)
        #expect(viewModel.draftHeightCm == 180)
        #expect(viewModel.draftGoalType == .fatLoss)
        #expect(viewModel.draftActivityLevel == .moderatelyActive)
        #expect(viewModel.draftTrainingSplit == .ppl)
        #expect(viewModel.draftGoalWeightText == "78.0")
        #expect(viewModel.draftCaloriesText == "2400")
        #expect(viewModel.draftProteinText == "170")
        #expect(viewModel.draftCarbsText == "250")
        #expect(viewModel.draftFatText == "70")
        #expect(viewModel.draftUnits == .metric)
    }

    @Test func beginEditingLeavesGoalWeightBlankWhenUnset() throws {
        let (viewModel, _, _, _) = try makeEditingViewModel(goalWeightKg: 0)
        #expect(viewModel.draftGoalWeightText.isEmpty)
    }

    @Test func beginEditingWithoutProfileDoesNothing() {
        let viewModel = ProfileViewModel()
        viewModel.beginEditing()
        #expect(!viewModel.isEditing)
    }

    @Test func cancelEditingExitsEditMode() throws {
        let (viewModel, _, _, _) = try makeEditingViewModel()
        viewModel.cancelEditing()
        #expect(!viewModel.isEditing)
    }

    // MARK: - Saving

    @Test func saveChangesAppliesEveryField() throws {
        let (viewModel, context, profile, _) = try makeEditingViewModel()

        viewModel.draftName = "  New Name  "
        viewModel.draftBiologicalSex = .female
        viewModel.draftHeightCm = 170
        viewModel.draftGoalType = .muscleGain
        viewModel.draftActivityLevel = .veryActive
        viewModel.draftTrainingSplit = .upperLower
        viewModel.draftGoalWeightText = "75,5"
        viewModel.draftCaloriesText = "2800"
        viewModel.draftProteinText = "180"
        viewModel.draftCarbsText = "300"
        viewModel.draftFatText = "80"
        viewModel.draftUnits = .imperial

        viewModel.saveChanges(in: context)

        #expect(!viewModel.isEditing)
        #expect(profile.name == "New Name") // trimmed
        #expect(profile.biologicalSex == .female)
        #expect(profile.heightCm == 170)
        #expect(profile.goalType == .muscleGain)
        #expect(profile.activityLevel == .veryActive)
        #expect(profile.trainingSplit == .upperLower)
        #expect(profile.goalWeightKg == 75.5) // comma decimal parsed
        #expect(profile.dailyCalorieTarget == 2800)
        #expect(profile.proteinTargetG == 180)
        #expect(profile.carbsTargetG == 300)
        #expect(profile.fatTargetG == 80)
        #expect(profile.preferredUnits == .imperial)
    }

    @Test func blankGoalWeightClearsToZero() throws {
        let (viewModel, context, profile, _) = try makeEditingViewModel()
        viewModel.draftGoalWeightText = ""
        viewModel.saveChanges(in: context)
        #expect(profile.goalWeightKg == 0)
    }

    @Test(arguments: ["10", "500", "abc"])
    func invalidGoalWeightClearsToZero(text: String) throws {
        let (viewModel, context, profile, _) = try makeEditingViewModel()
        viewModel.draftGoalWeightText = text
        viewModel.saveChanges(in: context)
        #expect(profile.goalWeightKg == 0)
    }

    @Test(arguments: zip(["20", "400"], [20.0, 400.0]))
    func goalWeightBoundariesAreAccepted(text: String, expected: Double) throws {
        let (viewModel, context, profile, _) = try makeEditingViewModel()
        viewModel.draftGoalWeightText = text
        viewModel.saveChanges(in: context)
        #expect(profile.goalWeightKg == expected)
    }

    @Test func saveChangesRefusesWhenInvalidAndStaysEditing() throws {
        let (viewModel, context, profile, _) = try makeEditingViewModel()
        viewModel.draftName = ""
        viewModel.saveChanges(in: context)

        #expect(viewModel.isEditing)
        #expect(profile.name == "Majd Arow")
    }

    // MARK: - Validation

    @Test func canSaveIsTrueForValidDrafts() throws {
        let (viewModel, _, _, _) = try makeEditingViewModel()
        #expect(viewModel.canSave)
    }

    @Test func canSaveRejectsBlankOrWhitespaceName() throws {
        let (viewModel, _, _, _) = try makeEditingViewModel()
        viewModel.draftName = ""
        #expect(!viewModel.canSave)
        viewModel.draftName = "   \n"
        #expect(!viewModel.canSave)
    }

    @Test func canSaveRejectsNonNumericOrNonPositiveTargets() throws {
        let (viewModel, _, _, _) = try makeEditingViewModel()

        viewModel.draftCaloriesText = "abc"
        #expect(!viewModel.canSave)
        viewModel.draftCaloriesText = "0"
        #expect(!viewModel.canSave)
        viewModel.draftCaloriesText = "2400"
        #expect(viewModel.canSave)

        viewModel.draftProteinText = ""
        #expect(!viewModel.canSave)
        viewModel.draftProteinText = "170"

        viewModel.draftCarbsText = "12.5" // Int-only field
        #expect(!viewModel.canSave)
        viewModel.draftCarbsText = "250"

        viewModel.draftFatText = "0"
        #expect(!viewModel.canSave)
        viewModel.draftFatText = "70"
        #expect(viewModel.canSave)
    }

    @Test func trimmedDraftNameStripsSurroundingWhitespace() {
        let viewModel = ProfileViewModel()
        viewModel.draftName = "  Majd \n"
        #expect(viewModel.trimmedDraftName == "Majd")
    }

    // MARK: - Initials

    @Test func initialsUseFirstTwoNameParts() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let profile = insertProfile(context, name: "Majd Arow")
        try context.save()
        let viewModel = ProfileViewModel()
        viewModel.load(from: context)

        #expect(viewModel.initials == "MA")

        profile.name = "cher"
        #expect(viewModel.initials == "C")

        profile.name = "John Ronald Reuel"
        #expect(viewModel.initials == "JR")
    }

    @Test func initialsAreEmptyWithoutProfile() {
        let viewModel = ProfileViewModel()
        #expect(viewModel.initials.isEmpty)
    }

    // MARK: - Draft height unit bindings

    @Test func heightCmSelectionRoundsAndWritesBack() {
        let viewModel = ProfileViewModel()
        viewModel.draftHeightCm = 179.6
        #expect(viewModel.draftHeightCmSelection == 180)

        viewModel.draftHeightCmSelection = 175
        #expect(viewModel.draftHeightCm == 175)
    }

    @Test func heightFeetAndInchesReadFromCanonicalCm() {
        let viewModel = ProfileViewModel()
        viewModel.draftHeightCm = 180 // 71 in -> 5 ft 11 in
        #expect(viewModel.draftHeightFeet == 5)
        #expect(viewModel.draftHeightInches == 11)
    }

    @Test func settingFeetPreservesInches() {
        let viewModel = ProfileViewModel()
        viewModel.draftHeightCm = 180 // 5 ft 11 in

        viewModel.draftHeightFeet = 6

        #expect(viewModel.draftHeightFeet == 6)
        #expect(viewModel.draftHeightInches == 11)
        #expect(abs(viewModel.draftHeightCm - UnitConversion.cm(fromFeet: 6, inches: 11)) < 0.0001)
    }

    @Test func settingInchesPreservesFeet() {
        let viewModel = ProfileViewModel()
        viewModel.draftHeightCm = 180 // 5 ft 11 in

        viewModel.draftHeightInches = 0

        #expect(viewModel.draftHeightFeet == 5)
        #expect(viewModel.draftHeightInches == 0)
        #expect(abs(viewModel.draftHeightCm - UnitConversion.cm(fromFeet: 5, inches: 0)) < 0.0001)
    }

    // MARK: - Display helpers

    @Test func imperialDisplayTextsUseImperialUnits() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        insertProfile(context, units: .imperial)
        context.insert(WeightEntry(date: .now, weightKg: 80))
        try context.save()

        let viewModel = ProfileViewModel()
        viewModel.load(from: context)

        #expect(viewModel.heightText == "5 ft 11 in")
        #expect(viewModel.weightText == "176 lb")
    }

    @Test func ageIsDerivedFromDateOfBirth() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        insertProfile(context) // born exactly 30 years ago
        try context.save()

        let viewModel = ProfileViewModel()
        viewModel.load(from: context)

        #expect(viewModel.age == 30)
    }

    @Test func displayHelpersAreNilWithoutProfile() {
        let viewModel = ProfileViewModel()
        #expect(viewModel.age == nil)
        #expect(viewModel.heightText == nil)
        #expect(viewModel.weightText == nil)
    }
}
