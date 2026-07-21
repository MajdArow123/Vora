//
//  ProfileViewModel.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import Foundation
import Observation
import SwiftData

@Observable
final class ProfileViewModel {
    private(set) var profile: UserProfile?
    private(set) var latestWeight: WeightEntry?
    private(set) var isEditing = false

    // MARK: - Draft state (populated when editing begins)

    var draftName = ""
    var draftDateOfBirth = Date.now
    var draftBiologicalSex: BiologicalSex = .male
    var draftHeightCm: Double = 175
    var draftGoalType: GoalType = .maintain
    var draftActivityLevel: ActivityLevel = .moderatelyActive
    var draftTrainingSplit: TrainingSplit = .fullBody
    var draftGoalWeightText = ""
    var draftCaloriesText = ""
    var draftProteinText = ""
    var draftCarbsText = ""
    var draftFatText = ""
    var draftUnits: UnitSystem = .metric

    // MARK: - Loading

    func load(from context: ModelContext) {
        profile = try? context.fetch(FetchDescriptor<UserProfile>()).first

        var weightDescriptor = FetchDescriptor<WeightEntry>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        weightDescriptor.fetchLimit = 1
        latestWeight = try? context.fetch(weightDescriptor).first
    }

    // MARK: - Editing lifecycle

    func beginEditing() {
        guard let profile else { return }
        draftName = profile.name
        draftDateOfBirth = profile.dateOfBirth
        draftBiologicalSex = profile.biologicalSex
        draftHeightCm = profile.heightCm
        draftGoalType = profile.goalType
        draftActivityLevel = profile.activityLevel
        draftTrainingSplit = profile.trainingSplit
        draftGoalWeightText = profile.goalWeightKg > 0
            ? String(format: "%.1f", profile.goalWeightKg)
            : ""
        draftCaloriesText = String(profile.dailyCalorieTarget)
        draftProteinText = String(profile.proteinTargetG)
        draftCarbsText = String(profile.carbsTargetG)
        draftFatText = String(profile.fatTargetG)
        draftUnits = profile.preferredUnits
        isEditing = true
    }

    func cancelEditing() {
        isEditing = false
    }

    func saveChanges(in context: ModelContext) {
        guard let profile, canSave,
              let calories = parsedCalories, let protein = parsedProtein,
              let carbs = parsedCarbs, let fat = parsedFat else { return }

        profile.name = trimmedDraftName
        profile.dateOfBirth = draftDateOfBirth
        profile.biologicalSex = draftBiologicalSex
        profile.heightCm = draftHeightCm
        profile.goalType = draftGoalType
        profile.activityLevel = draftActivityLevel
        profile.trainingSplit = draftTrainingSplit
        profile.goalWeightKg = parsedGoalWeight ?? 0
        profile.dailyCalorieTarget = calories
        profile.proteinTargetG = protein
        profile.carbsTargetG = carbs
        profile.fatTargetG = fat
        profile.preferredUnits = draftUnits

        do {
            try context.save()
        } catch {
            assertionFailure("Failed to save profile edits: \(error)")
        }
        isEditing = false
    }

    // MARK: - Validation (same rules as onboarding)

    /// nil when blank (goal weight is optional); invalid text also
    /// resolves to nil and clears the goal.
    private var parsedGoalWeight: Double? {
        let value = Double(draftGoalWeightText.replacingOccurrences(of: ",", with: "."))
        guard let value, (20...400).contains(value) else { return nil }
        return value
    }

    private var parsedCalories: Int? { Int(draftCaloriesText) }
    private var parsedProtein: Int? { Int(draftProteinText) }
    private var parsedCarbs: Int? { Int(draftCarbsText) }
    private var parsedFat: Int? { Int(draftFatText) }

    var trimmedDraftName: String {
        draftName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canSave: Bool {
        guard let calories = parsedCalories, let protein = parsedProtein,
              let carbs = parsedCarbs, let fat = parsedFat else { return false }
        return !trimmedDraftName.isEmpty
            && calories > 0 && protein > 0 && carbs > 0 && fat > 0
    }

    var dateOfBirthRange: ClosedRange<Date> {
        let earliest = Calendar.current.date(byAdding: .year, value: -100, to: .now) ?? .now
        let latest = Calendar.current.date(byAdding: .year, value: -13, to: .now) ?? .now
        return earliest...latest
    }

    // MARK: - Unit-aware draft height bindings (canonical storage is metric)

    var draftHeightCmSelection: Int {
        get { Int(draftHeightCm.rounded()) }
        set { draftHeightCm = Double(newValue) }
    }

    var draftHeightFeet: Int {
        get { UnitConversion.feetAndInches(fromCm: draftHeightCm).feet }
        set { draftHeightCm = UnitConversion.cm(fromFeet: newValue, inches: draftHeightInches) }
    }

    var draftHeightInches: Int {
        get { UnitConversion.feetAndInches(fromCm: draftHeightCm).inches }
        set { draftHeightCm = UnitConversion.cm(fromFeet: draftHeightFeet, inches: newValue) }
    }

    // MARK: - Display helpers

    var age: Int? {
        guard let profile else { return nil }
        return Calendar.current.dateComponents([.year], from: profile.dateOfBirth, to: .now).year
    }

    var heightText: String? {
        guard let profile else { return nil }
        return UnitConversion.heightText(cm: profile.heightCm, units: profile.preferredUnits)
    }

    var weightText: String? {
        guard let profile, let latestWeight else { return nil }
        return UnitConversion.weightText(kg: latestWeight.weightKg, units: profile.preferredUnits)
    }

    var initials: String {
        guard let profile else { return "" }
        return profile.name
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first.map(String.init) }
            .joined()
            .uppercased()
    }
}
