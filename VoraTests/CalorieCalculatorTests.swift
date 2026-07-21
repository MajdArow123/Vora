//
//  CalorieCalculatorTests.swift
//  VoraTests
//
//  Created by Majd Arow on 2026-07-21.
//

import Foundation
import Testing
@testable import Vora

struct CalorieCalculatorTests {
    // MARK: - Mifflin-St Jeor BMR

    /// Male 80 kg / 180 cm / 30 y: BMR = 800 + 1125 - 150 + 5 = 1780.
    /// TDEE (moderate 1.55) = 2759; fat loss x0.8 = 2207.2 -> 2210.
    @Test func maleFatLossTargets() {
        let targets = CalorieCalculator.suggestedTargets(
            weightKg: 80, heightCm: 180, age: 30,
            sex: .male, activityLevel: .moderatelyActive, goal: .fatLoss
        )
        #expect(targets.calories == 2210)
        #expect(targets.proteinG == 160) // 2.0 g/kg
        #expect(targets.fatG == 61)      // 2207.2 * 0.25 / 9
        #expect(targets.carbsG == 254)   // remainder / 4
        #expect(targets.waterMl == 2750) // 2800 rounded to 250 step
    }

    /// Female 60 kg / 165 cm / 25 y: BMR = 600 + 1031.25 - 125 - 161
    /// = 1345.25. TDEE (sedentary 1.2) = 1614.3 -> 1610 at maintenance.
    @Test func femaleMaintainTargets() {
        let targets = CalorieCalculator.suggestedTargets(
            weightKg: 60, heightCm: 165, age: 25,
            sex: .female, activityLevel: .sedentary, goal: .maintain
        )
        #expect(targets.calories == 1610)
        #expect(targets.proteinG == 96)  // 1.6 g/kg
        #expect(targets.fatG == 45)
        #expect(targets.carbsG == 207)
        #expect(targets.waterMl == 2000) // 2100 rounds to 2000, at the floor
    }

    /// Male 90 kg / 185 cm / 28 y: BMR = 1921.25. TDEE (very 1.725)
    /// = 3314.15625; muscle gain x1.12 = 3711.855 -> 3710.
    @Test func maleMuscleGainTargets() {
        let targets = CalorieCalculator.suggestedTargets(
            weightKg: 90, heightCm: 185, age: 28,
            sex: .male, activityLevel: .veryActive, goal: .muscleGain
        )
        #expect(targets.calories == 3710)
        #expect(targets.proteinG == 162) // 1.8 g/kg
        #expect(targets.fatG == 103)
        #expect(targets.carbsG == 534)
        #expect(targets.waterMl == 3250)
    }

    // MARK: - Activity multipliers

    /// Same person (BMR 1780) at maintenance across every level:
    /// calories = round(1780 x multiplier / 10) x 10.
    @Test(arguments: zip(
        [ActivityLevel.sedentary, .lightlyActive, .moderatelyActive, .veryActive, .athlete],
        [2140, 2450, 2760, 3070, 3380]
    ))
    func activityMultiplierScalesMaintenanceCalories(level: ActivityLevel, expected: Int) {
        let targets = CalorieCalculator.suggestedTargets(
            weightKg: 80, heightCm: 180, age: 30,
            sex: .male, activityLevel: level, goal: .maintain
        )
        #expect(targets.calories == expected)
    }

    // MARK: - Goal adjustments

    /// Same female profile: maintain 1610, fat loss x0.8 -> 1290,
    /// muscle gain x1.12 -> 1810.
    @Test(arguments: zip(
        [GoalType.fatLoss, .maintain, .muscleGain],
        [1290, 1610, 1810]
    ))
    func goalAdjustmentScalesCalories(goal: GoalType, expected: Int) {
        let targets = CalorieCalculator.suggestedTargets(
            weightKg: 60, heightCm: 165, age: 25,
            sex: .female, activityLevel: .sedentary, goal: goal
        )
        #expect(targets.calories == expected)
    }

    @Test(arguments: zip(
        [GoalType.fatLoss, .maintain, .muscleGain],
        [160, 128, 144] // 2.0, 1.6, 1.8 g/kg at 80 kg
    ))
    func proteinPerKgDependsOnGoal(goal: GoalType, expected: Int) {
        let targets = CalorieCalculator.suggestedTargets(
            weightKg: 80, heightCm: 180, age: 30,
            sex: .male, activityLevel: .moderatelyActive, goal: goal
        )
        #expect(targets.proteinG == expected)
    }

    // MARK: - Macro invariants

    @Test func fatIsQuarterOfCaloriesAcrossGoals() {
        for goal in GoalType.allCases {
            let targets = CalorieCalculator.suggestedTargets(
                weightKg: 75, heightCm: 178, age: 35,
                sex: .male, activityLevel: .lightlyActive, goal: goal
            )
            // Reconstruct: fat grams x 9 should be ~25% of unrounded
            // calories; allow slack for the two roundings involved.
            let fatCalories = Double(targets.fatG) * 9
            let share = fatCalories / Double(targets.calories)
            #expect(abs(share - 0.25) < 0.01, "goal \(goal): fat share \(share)")
        }
    }

    @Test func carbsNeverGoNegative() {
        // Extreme inputs where protein + fat calories exceed the calorie
        // budget: 500 kg fat-loss profile puts protein at 4000 kcal alone.
        let targets = CalorieCalculator.suggestedTargets(
            weightKg: 500, heightCm: 150, age: 80,
            sex: .male, activityLevel: .sedentary, goal: .fatLoss
        )
        #expect(targets.carbsG == 0)
    }

    // MARK: - Water clamping

    @Test func waterClampsToLowerBound() {
        let targets = CalorieCalculator.suggestedTargets(
            weightKg: 40, heightCm: 150, age: 30,
            sex: .female, activityLevel: .sedentary, goal: .maintain
        )
        #expect(targets.waterMl == 2000) // 40 x 35 = 1400 -> clamped up
    }

    @Test func waterClampsToUpperBound() {
        let targets = CalorieCalculator.suggestedTargets(
            weightKg: 150, heightCm: 190, age: 30,
            sex: .male, activityLevel: .athlete, goal: .muscleGain
        )
        #expect(targets.waterMl == 5000) // 150 x 35 = 5250 -> clamped down
    }

    @Test func waterRoundsTo250Steps() {
        // 90 x 35 = 3150 -> 12.6 steps -> 13 -> 3250.
        let targets = CalorieCalculator.suggestedTargets(
            weightKg: 90, heightCm: 180, age: 30,
            sex: .male, activityLevel: .moderatelyActive, goal: .maintain
        )
        #expect(targets.waterMl == 3250)
        #expect(targets.waterMl % 250 == 0)
    }

    // MARK: - Rounding

    @Test func caloriesAlwaysRoundToNearestTen() {
        for level in ActivityLevel.allCases {
            for goal in GoalType.allCases {
                let targets = CalorieCalculator.suggestedTargets(
                    weightKg: 72.4, heightCm: 176.5, age: 41,
                    sex: .female, activityLevel: level, goal: goal
                )
                #expect(targets.calories % 10 == 0, "\(level) \(goal): \(targets.calories)")
            }
        }
    }
}
