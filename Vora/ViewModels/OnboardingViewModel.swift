//
//  OnboardingViewModel.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import Foundation
import Observation
import SwiftData

enum OnboardingStep: Int, CaseIterable {
    case welcome
    case basics
    case goal
    case targets
    case trainingSplit
    case summary
}

@Observable
final class OnboardingViewModel {
    var step: OnboardingStep = .welcome

    // Basics
    var preferredUnits: UnitSystem = .metric
    var name = ""
    var dateOfBirth = Calendar.current.date(byAdding: .year, value: -25, to: .now) ?? .now
    var biologicalSex: BiologicalSex?
    var heightCm: Double = 175
    var weightKg: Double = 75

    // Goal
    var goalType: GoalType?
    var activityLevel: ActivityLevel?

    // Training split
    var trainingSplit: TrainingSplit?

    // Targets — string-backed so free-form edits never silently fail to commit
    var caloriesText = ""
    var proteinText = ""
    var carbsText = ""
    var fatText = ""
    var waterText = ""
    private var hasSuggestedTargets = false

    // MARK: - Imperial bindings (canonical storage is always metric)

    var heightCmSelection: Int {
        get { Int(heightCm.rounded()) }
        set { heightCm = Double(newValue) }
    }

    var heightFeet: Int {
        get { UnitConversion.feetAndInches(fromCm: heightCm).feet }
        set { heightCm = UnitConversion.cm(fromFeet: newValue, inches: heightInches) }
    }

    var heightInches: Int {
        get { UnitConversion.feetAndInches(fromCm: heightCm).inches }
        set { heightCm = UnitConversion.cm(fromFeet: heightFeet, inches: newValue) }
    }

    var weightKgSelection: Int {
        get { Int(weightKg.rounded()) }
        set { weightKg = Double(newValue) }
    }

    var weightPounds: Int {
        get { Int(UnitConversion.pounds(fromKg: weightKg).rounded()) }
        set { weightKg = UnitConversion.kg(fromPounds: Double(newValue)) }
    }

    // MARK: - Derived values

    var dateOfBirthRange: ClosedRange<Date> {
        let earliest = Calendar.current.date(byAdding: .year, value: -100, to: .now) ?? .now
        let latest = Calendar.current.date(byAdding: .year, value: -13, to: .now) ?? .now
        return earliest...latest
    }

    var age: Int {
        Calendar.current.dateComponents([.year], from: dateOfBirth, to: .now).year ?? 0
    }

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var heightText: String {
        UnitConversion.heightText(cm: heightCm, units: preferredUnits)
    }

    var weightText: String {
        UnitConversion.weightText(kg: weightKg, units: preferredUnits)
    }

    private var parsedCalories: Int? { Int(caloriesText) }
    private var parsedProtein: Int? { Int(proteinText) }
    private var parsedCarbs: Int? { Int(carbsText) }
    private var parsedFat: Int? { Int(fatText) }
    private var parsedWater: Double? { Double(waterText) }

    var canContinue: Bool {
        switch step {
        case .welcome, .summary:
            return true
        case .basics:
            return !trimmedName.isEmpty && biologicalSex != nil
        case .goal:
            return goalType != nil && activityLevel != nil
        case .targets:
            guard let calories = parsedCalories, let protein = parsedProtein,
                  let carbs = parsedCarbs, let fat = parsedFat,
                  let water = parsedWater else { return false }
            return calories > 0 && protein > 0 && carbs > 0 && fat > 0 && water > 0
        case .trainingSplit:
            return trainingSplit != nil
        }
    }

    var canGoBack: Bool {
        step != .welcome
    }

    // MARK: - Navigation

    func advance() {
        if step == .goal, !hasSuggestedTargets {
            suggestTargets()
            hasSuggestedTargets = true
        }
        if let next = OnboardingStep(rawValue: step.rawValue + 1) {
            step = next
        }
    }

    func goBack() {
        if let previous = OnboardingStep(rawValue: step.rawValue - 1) {
            step = previous
        }
    }

    // MARK: - Target suggestion

    private func suggestTargets() {
        guard let goalType, let activityLevel, let biologicalSex else { return }

        let targets = CalorieCalculator.suggestedTargets(
            weightKg: weightKg,
            heightCm: heightCm,
            age: age,
            sex: biologicalSex,
            activityLevel: activityLevel,
            goal: goalType
        )

        caloriesText = String(targets.calories)
        proteinText = String(targets.proteinG)
        carbsText = String(targets.carbsG)
        fatText = String(targets.fatG)
        waterText = String(targets.waterMl)
    }

    // MARK: - Completion

    func completeOnboarding(in context: ModelContext) {
        guard let goalType, let activityLevel, let biologicalSex, let trainingSplit,
              canContinue,
              let calories = parsedCalories, let protein = parsedProtein,
              let carbs = parsedCarbs, let fat = parsedFat,
              let water = parsedWater else { return }

        let profile = UserProfile(
            name: trimmedName,
            dateOfBirth: dateOfBirth,
            heightCm: heightCm,
            biologicalSex: biologicalSex,
            goalType: goalType,
            activityLevel: activityLevel,
            trainingSplit: trainingSplit,
            dailyCalorieTarget: calories,
            proteinTargetG: protein,
            carbsTargetG: carbs,
            fatTargetG: fat,
            waterTargetMl: water,
            preferredUnits: preferredUnits
        )
        context.insert(profile)
        context.insert(WeightEntry(date: .now, weightKg: weightKg))

        do {
            try context.save()
        } catch {
            assertionFailure("Failed to save onboarding data: \(error)")
        }
    }
}
