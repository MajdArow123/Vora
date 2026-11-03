//
//  CalorieCycling.swift
//  Vora
//
//  Created by Majd Arow on 2026-11-03.
//

import Foundation

/// Whether training days get more calories and rest days fewer. Lives in
/// UserDefaults like the other per-device settings, and is off by default.
enum CalorieCyclingSettings {
    static let storageKey = "vora.calorieCycling"
    static let defaultEnabled = false
}

/// Splits a week's calories between training and rest days, keeping the weekly
/// total. Pure: a week is a list of day kinds, Monday first. docs/COACHING.md
/// explains the rules.
enum CalorieCycling {
    static let daysPerWeek = 7
    /// How far a training day sits above a rest day, as a share of the daily
    /// base: enough to feel on the plate, small enough not to strain rest days.
    static let dayGapFraction = 0.1

    enum DayKind: Equatable {
        case training
        case rest
    }

    /// Calories for each day in `kinds`, in order. Later days are unaffected by
    /// what's listed after them, so a past day's number never changes as the
    /// week goes on.
    ///
    /// Each day shares out what's left of the week: the rest-day number is
    /// (budget left − expected training days left × gap) / days left, and a
    /// training day is that plus the gap. The last day takes the remainder, so
    /// a full week adds up to exactly 7 × base unless a floor stopped it. A base
    /// at or below the floor doesn't cycle, since cycling could only lower it.
    static func dayCalories(
        baseCalories: Int,
        floorCalories: Int,
        expectedTrainingDays: Int,
        kinds: [DayKind]
    ) -> [Int] {
        guard baseCalories > floorCalories else { return kinds.map { _ in baseCalories } }

        let gap = Double(baseCalories) * dayGapFraction
        let floor = Double(floorCalories)
        var remaining = Double(baseCalories * daysPerWeek)
        var trainedSoFar = 0
        var result: [Int] = []

        for (index, kind) in kinds.prefix(daysPerWeek).enumerated() {
            let daysLeft = daysPerWeek - index
            let isTraining = kind == .training
            var trainingDaysLeft = max(expectedTrainingDays - trainedSoFar, 0)
            trainingDaysLeft = isTraining ? max(trainingDaysLeft, 1) : min(trainingDaysLeft, daysLeft - 1)

            var calories: Double
            if daysLeft == 1 {
                calories = remaining
            } else {
                var restDay = (remaining - Double(trainingDaysLeft) * gap) / Double(daysLeft)
                var trainingDay = restDay + gap
                if restDay < floor {
                    // The gap shrinks so rest days stay on the floor and the
                    // training days get what's left.
                    restDay = floor
                    let restDays = Double(daysLeft - trainingDaysLeft)
                    trainingDay = trainingDaysLeft > 0 ? (remaining - restDays * floor) / Double(trainingDaysLeft) : floor
                }
                calories = ((isTraining ? trainingDay : restDay) / 10).rounded() * 10
            }
            calories = max(calories, floor)

            result.append(Int(calories.rounded()))
            remaining -= calories
            if isTraining { trainedSoFar += 1 }
        }
        return result
    }

    /// A day's macros at `calories`: protein constant, carbs and fat scaled by
    /// the calories that aren't protein. Unchanged when protein alone covers
    /// the base, where there's nothing to scale.
    static func scaled(_ base: MacroTargets, toCalories calories: Int) -> MacroTargets {
        let proteinKcal = Double(base.proteinG) * 4
        let baseRest = Double(base.calories) - proteinKcal
        guard baseRest > 0 else {
            return MacroTargets(calories: calories, proteinG: base.proteinG, carbsG: base.carbsG, fatG: base.fatG)
        }
        let scale = max(Double(calories) - proteinKcal, 0) / baseRest
        return MacroTargets(
            calories: calories,
            proteinG: base.proteinG,
            carbsG: Int((Double(base.carbsG) * scale).rounded()),
            fatG: Int((Double(base.fatG) * scale).rounded())
        )
    }
}
