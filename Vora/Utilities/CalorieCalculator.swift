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

/// Targets proposed from a measured expenditure.
struct ExpenditureTargets: Equatable {
    let calories: Int
    let proteinG: Int
    let carbsG: Int
    let fatG: Int
    /// True when a floor raised the calories above what the goal asks for.
    let isFloored: Bool
}

enum CalorieCalculator {
    /// No adaptive target goes below this, whatever the BMR.
    static let minimumCalories = 1200.0

    /// Mifflin-St Jeor resting expenditure.
    static func bmr(weightKg: Double, heightCm: Double, age: Int, sex: BiologicalSex) -> Double {
        10 * weightKg + 6.25 * heightCm - 5 * Double(age) + sex.mifflinConstant
    }

    /// Mifflin-St Jeor BMR × activity multiplier.
    static func formulaTDEE(
        weightKg: Double,
        heightCm: Double,
        age: Int,
        sex: BiologicalSex,
        activityLevel: ActivityLevel
    ) -> Double {
        bmr(weightKg: weightKg, heightCm: heightCm, age: age, sex: sex) * activityLevel.multiplier
    }

    /// Formula TDEE adjusted for goal, with no floor.
    static func suggestedTargets(
        weightKg: Double,
        heightCm: Double,
        age: Int,
        sex: BiologicalSex,
        activityLevel: ActivityLevel,
        goal: GoalType
    ) -> SuggestedTargets {
        let tdee = formulaTDEE(weightKg: weightKg, heightCm: heightCm, age: age, sex: sex, activityLevel: activityLevel)
        let calories = tdee * goal.calorieMultiplier
        let split = macros(calories: calories, weightKg: weightKg, goal: goal)
        let water = min(max((weightKg * 35 / 250).rounded() * 250, 2000), 5000)

        return SuggestedTargets(
            calories: roundedCalories(calories),
            proteinG: split.proteinG,
            carbsG: split.carbsG,
            fatG: split.fatG,
            waterMl: Int(water)
        )
    }

    /// A measured expenditure adjusted for goal, floored at `bmr` and at
    /// `minimumCalories`. A floored value rounds up, so rounding can't take
    /// it back under the floor.
    static func targets(fromExpenditure expenditure: Double, weightKg: Double, goal: GoalType, bmr: Double) -> ExpenditureTargets {
        let floor = max(bmr, minimumCalories)
        let rounded = roundedCalories(expenditure * goal.calorieMultiplier)
        let isFloored = Double(rounded) < floor
        let calories = isFloored ? Int((floor / 10).rounded(.up) * 10) : rounded
        let split = macros(calories: Double(calories), weightKg: weightKg, goal: goal)

        return ExpenditureTargets(
            calories: calories,
            proteinG: split.proteinG,
            carbsG: split.carbsG,
            fatG: split.fatG,
            isFloored: isFloored
        )
    }

    /// `targets` with a coaching adjustment on top. Protein stays constant,
    /// floors still apply, and neither direction can cross expenditure: easing
    /// a deficit stops at maintenance, and so does trimming a surplus. nil when
    /// those limits leave nothing to change.
    static func adjusted(
        _ targets: ExpenditureTargets,
        byKcal delta: Int,
        expenditure: Double,
        weightKg: Double,
        goal: GoalType,
        bmr: Double
    ) -> ExpenditureTargets? {
        let floor = Int((max(bmr, minimumCalories) / 10).rounded(.up) * 10)
        let maintenance = roundedCalories(expenditure)
        let moved = targets.calories + delta
        let calories = delta > 0
            ? min(moved, max(maintenance, targets.calories))
            : min(targets.calories, max(moved, maintenance, floor))
        guard calories != targets.calories else { return nil }
        let split = macros(calories: Double(calories), weightKg: weightKg, goal: goal)

        return ExpenditureTargets(
            calories: calories,
            proteinG: split.proteinG,
            carbsG: split.carbsG,
            fatG: split.fatG,
            isFloored: false
        )
    }

    /// The weekly weight change a goal's calorie multiplier aims for at this
    /// expenditure, in kg: negative for loss, positive for gain, 0 at maintenance.
    static func goalWeeklyRateKg(expenditure: Double, goal: GoalType) -> Double {
        expenditure * (goal.calorieMultiplier - 1) * 7 / ExpenditureEstimator.energyDensityKcalPerKg
    }

    /// Protein per kg of body weight by goal, fat at 25% of calories, carbs
    /// from the remainder.
    private static func macros(calories: Double, weightKg: Double, goal: GoalType) -> (proteinG: Int, carbsG: Int, fatG: Int) {
        let protein = weightKg * goal.proteinPerKg
        let fat = calories * 0.25 / 9
        let carbs = max((calories - protein * 4 - fat * 9) / 4, 0)
        return (Int(protein.rounded()), Int(carbs.rounded()), Int(fat.rounded()))
    }

    private static func roundedCalories(_ calories: Double) -> Int {
        Int((calories / 10).rounded() * 10)
    }
}

private extension GoalType {
    var calorieMultiplier: Double {
        switch self {
        case .fatLoss: 0.8
        case .maintain: 1
        case .muscleGain: 1.12
        }
    }

    var proteinPerKg: Double {
        switch self {
        case .fatLoss: 2.0
        case .maintain: 1.6
        case .muscleGain: 1.8
        }
    }
}
