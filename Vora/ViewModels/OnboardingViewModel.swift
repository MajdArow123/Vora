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
    case summary
}

/// Asked during onboarding only to compute suggested targets; not persisted.
enum ActivityLevel: String, CaseIterable {
    case sedentary
    case lightlyActive
    case moderatelyActive
    case veryActive
    case athlete

    var displayName: String {
        switch self {
        case .sedentary: "Sedentary"
        case .lightlyActive: "Lightly Active"
        case .moderatelyActive: "Moderately Active"
        case .veryActive: "Very Active"
        case .athlete: "Athlete"
        }
    }

    var detail: String {
        switch self {
        case .sedentary: "Little or no exercise"
        case .lightlyActive: "1–3 workouts a week"
        case .moderatelyActive: "3–5 workouts a week"
        case .veryActive: "6–7 workouts a week"
        case .athlete: "Physical job or twice-daily training"
        }
    }

    var multiplier: Double {
        switch self {
        case .sedentary: 1.2
        case .lightlyActive: 1.375
        case .moderatelyActive: 1.55
        case .veryActive: 1.725
        case .athlete: 1.9
        }
    }
}

@Observable
final class OnboardingViewModel {
    var step: OnboardingStep = .welcome

    // Basics
    var preferredUnits: UnitSystem = .metric
    var name = ""
    var dateOfBirth = Calendar.current.date(byAdding: .year, value: -25, to: .now) ?? .now
    var heightCm: Double = 175
    var weightKg: Double = 75

    // Goal
    var goalType: GoalType?
    var activityLevel: ActivityLevel?

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
            return !trimmedName.isEmpty
        case .goal:
            return goalType != nil && activityLevel != nil
        case .targets:
            guard let calories = parsedCalories, let protein = parsedProtein,
                  let carbs = parsedCarbs, let fat = parsedFat,
                  let water = parsedWater else { return false }
            return calories > 0 && protein > 0 && carbs > 0 && fat > 0 && water > 0
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

    /// Mifflin-St Jeor with a sex-neutral midpoint constant — the profile
    /// model stores no biological sex, so the male/female offset is averaged.
    private func suggestTargets() {
        guard let goalType, let activityLevel else { return }

        let bmr = 10 * weightKg + 6.25 * heightCm - 5 * Double(age) - 78
        let tdee = bmr * activityLevel.multiplier

        let calories: Double
        let proteinPerKg: Double
        switch goalType {
        case .fatLoss:
            calories = tdee * 0.8
            proteinPerKg = 2.0
        case .maintain:
            calories = tdee
            proteinPerKg = 1.6
        case .muscleGain:
            calories = tdee * 1.12
            proteinPerKg = 1.8
        }

        let protein = weightKg * proteinPerKg
        let fat = calories * 0.25 / 9
        let carbs = max((calories - protein * 4 - fat * 9) / 4, 0)
        let water = min(max((weightKg * 35 / 250).rounded() * 250, 2000), 5000)

        caloriesText = String(Int((calories / 10).rounded() * 10))
        proteinText = String(Int(protein.rounded()))
        carbsText = String(Int(carbs.rounded()))
        fatText = String(Int(fat.rounded()))
        waterText = String(Int(water))
    }

    // MARK: - Completion

    func completeOnboarding(in context: ModelContext) {
        guard let goalType, canContinue,
              let calories = parsedCalories, let protein = parsedProtein,
              let carbs = parsedCarbs, let fat = parsedFat,
              let water = parsedWater else { return }

        let profile = UserProfile(
            name: trimmedName,
            dateOfBirth: dateOfBirth,
            heightCm: heightCm,
            goalType: goalType,
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
