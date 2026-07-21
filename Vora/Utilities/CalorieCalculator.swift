//
//  CalorieCalculator.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import Foundation

struct SuggestedTargets {
    let calories: Int
    let proteinG: Int
    let carbsG: Int
    let fatG: Int
    let waterMl: Int
}

enum CalorieCalculator {
    /// Mifflin-St Jeor BMR × activity multiplier, adjusted for goal.
    /// Protein is set per kg of body weight by goal, fat at 25% of
    /// calories, carbs from the remainder.
    static func suggestedTargets(
        weightKg: Double,
        heightCm: Double,
        age: Int,
        sex: BiologicalSex,
        activityLevel: ActivityLevel,
        goal: GoalType
    ) -> SuggestedTargets {
        let bmr = 10 * weightKg + 6.25 * heightCm - 5 * Double(age) + sex.mifflinConstant
        let tdee = bmr * activityLevel.multiplier

        let calories: Double
        let proteinPerKg: Double
        switch goal {
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

        return SuggestedTargets(
            calories: Int((calories / 10).rounded() * 10),
            proteinG: Int(protein.rounded()),
            carbsG: Int(carbs.rounded()),
            fatG: Int(fat.rounded()),
            waterMl: Int(water)
        )
    }
}
