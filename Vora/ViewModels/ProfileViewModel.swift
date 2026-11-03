//
//  ProfileViewModel.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import Foundation
import Observation
import OSLog
import SwiftData

@Observable
final class ProfileViewModel {
    private static let logger = Logger(subsystem: "com.majdarow.Vora", category: "Profile")

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
    private var draftGoalWeight = WeightField(kg: nil, units: .metric)
    var draftCaloriesText = ""
    var draftProteinText = ""
    var draftCarbsText = ""
    var draftFatText = ""
    /// Switching units reconverts the goal, so 172 lb never becomes 172 kg.
    var draftUnits: UnitSystem = .metric {
        didSet {
            guard draftUnits != oldValue else { return }
            draftGoalWeight = WeightField(kg: draftGoalWeight.kg, units: draftUnits)
        }
    }

    /// The goal as typed, in `draftUnits`. Untouched text keeps its exact kg.
    var draftGoalWeightText: String {
        get { draftGoalWeight.text }
        set { draftGoalWeight.text = newValue }
    }

    // MARK: - Loading

    func load(from context: ModelContext) {
        do {
            profile = try context.fetch(FetchDescriptor<UserProfile>()).first
        } catch {
            Self.logger.error("Failed to fetch profile: \(String(describing: error), privacy: .public)")
            profile = nil
        }

        var weightDescriptor = FetchDescriptor<WeightEntry>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        weightDescriptor.fetchLimit = 1
        do {
            latestWeight = try context.fetch(weightDescriptor).first
        } catch {
            Self.logger.error("Failed to fetch latest weight: \(String(describing: error), privacy: .public)")
            latestWeight = nil
        }
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
        draftCaloriesText = String(profile.dailyCalorieTarget)
        draftProteinText = String(profile.proteinTargetG)
        draftCarbsText = String(profile.carbsTargetG)
        draftFatText = String(profile.fatTargetG)
        draftUnits = profile.preferredUnits
        draftGoalWeight = WeightField(
            kg: profile.goalWeightKg > 0 ? profile.goalWeightKg : nil,
            units: profile.preferredUnits
        )
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
        profile.goalWeightKg = draftGoalWeight.bodyWeightKg ?? 0
        profile.dailyCalorieTarget = calories
        profile.proteinTargetG = protein
        profile.carbsTargetG = carbs
        profile.fatTargetG = fat
        profile.preferredUnits = draftUnits

        do {
            try context.save()
        } catch {
            Self.logger.error("Failed to save profile edits: \(String(describing: error), privacy: .public)")
            context.rollback()
            return
        }
        isEditing = false
    }

    // MARK: - Validation (same rules as onboarding)

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
