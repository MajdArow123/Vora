//
//  MealSuggestion.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-26.
//

import Foundation

/// Remaining macros for the day (target minus consumed, may be negative).
struct RemainingMacros: Equatable, Sendable {
    let calories: Int
    let proteinG: Int
    let carbsG: Int
    let fatG: Int
}

/// Daily macro targets from the user's profile (no water).
struct MacroTargets: Equatable, Sendable {
    let calories: Int
    let proteinG: Int
    let carbsG: Int
    let fatG: Int
}

/// Fixed share of the daily targets each meal slot gets. The shares sum to
/// 1.0 across all five slots; on rest days postWorkout's share simply goes
/// unallocated rather than being redistributed.
enum MealAllocation {
    static func share(for slot: MealSlot) -> Double {
        switch slot {
        case .breakfast: 0.25
        case .postWorkout: 0.20
        case .lunch: 0.25
        case .dinner: 0.25
        case .snack: 0.05
        }
    }

    /// Below this many remaining kcal a slot counts as already hit — no
    /// meaningful meal fits, so the API should never be called under it.
    static let minimumMealCalories = 100

    /// This slot's share of the daily targets, rounded per macro.
    static func targets(for slot: MealSlot, daily: MacroTargets) -> MacroTargets {
        let share = share(for: slot)
        return MacroTargets(
            calories: Int((Double(daily.calories) * share).rounded()),
            proteinG: Int((Double(daily.proteinG) * share).rounded()),
            carbsG: Int((Double(daily.carbsG) * share).rounded()),
            fatG: Int((Double(daily.fatG) * share).rounded())
        )
    }

    /// Slot targets minus what's already logged in that slot, clamped ≥ 0.
    static func remaining(
        for slot: MealSlot,
        daily: MacroTargets,
        slotConsumed: [(calories: Double, proteinG: Double, carbsG: Double, fatG: Double)]
    ) -> RemainingMacros {
        let target = targets(for: slot, daily: daily)
        let eaten = slotConsumed.reduce((calories: 0.0, proteinG: 0.0, carbsG: 0.0, fatG: 0.0)) {
            ($0.calories + $1.calories, $0.proteinG + $1.proteinG,
             $0.carbsG + $1.carbsG, $0.fatG + $1.fatG)
        }
        return RemainingMacros(
            calories: max(0, target.calories - Int(eaten.calories.rounded())),
            proteinG: max(0, target.proteinG - Int(eaten.proteinG.rounded())),
            carbsG: max(0, target.carbsG - Int(eaten.carbsG.rounded())),
            fatG: max(0, target.fatG - Int(eaten.fatG.rounded()))
        )
    }

    static func isSlotHit(_ remaining: RemainingMacros) -> Bool {
        remaining.calories < minimumMealCalories
    }
}

/// One food line in a suggestion, directly searchable in OpenFoodFacts.
/// `grams` is mutable so the suggestion sheet can adjust portions before
/// logging; edits stay in the sheet and never reach the day cache.
struct SuggestedFood: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    let name: String
    var grams: Double
    let unit: String

    // The backend sends no id; regenerating one per decode is fine because
    // equality and coding both ignore it.
    private enum CodingKeys: String, CodingKey {
        case name, grams, unit
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.name == rhs.name && lhs.grams == rhs.grams && lhs.unit == rhs.unit
    }
}

/// One AI-generated meal suggestion, cached per day.
struct MealSuggestion: Codable, Equatable, Sendable {
    let mealName: String
    let mealType: String
    let description: String
    let foods: [SuggestedFood]
    let cookingTip: String
    let generatedAt: Date

    /// The backend's mealType strings are exactly MealSlot rawValues;
    /// anything unexpected degrades to a snack rather than crashing UI.
    var slot: MealSlot { MealSlot(rawValue: mealType) ?? .snack }
}

/// Context fields sent to the ProTracker backend alongside the macros.
enum MealSuggestionContext {
    static func timeOfDay(hour: Int) -> String {
        switch hour {
        case 5..<12: "morning"
        case 12..<17: "afternoon"
        case 17..<21: "evening"
        default: "night"
        }
    }

    /// The meal the suggestion should target, from the clock plus what has
    /// already happened today. Distinct from MealSlot.suggested(for:), which
    /// pre-selects a quick-log slot without workout or logged-meal context.
    static func mealType(hour: Int, hasTrainedToday: Bool, loggedSlots: Set<MealSlot>) -> MealSlot {
        switch hour {
        case ..<10: .breakfast
        case 10..<13: hasTrainedToday ? .postWorkout : .lunch
        case 13..<17: loggedSlots.contains(.lunch) ? .snack : .lunch
        case 17..<21: .dinner
        default: .snack
        }
    }
}
