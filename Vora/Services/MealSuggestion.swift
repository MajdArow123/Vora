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

/// How much of the day's targets a meal gets. docs/MEAL_SUGGESTIONS.md explains
/// the rules.
enum MealAllocation {
    typealias Consumed = (calories: Double, proteinG: Double, carbsG: Double, fatG: Double)

    /// Each slot's share on a training day; they sum to 1.0.
    static func share(for slot: MealSlot) -> Double {
        switch slot {
        case .breakfast: 0.25
        case .postWorkout: 0.15
        case .lunch: 0.25
        case .dinner: 0.25
        case .snack: 0.10
        }
    }

    /// Without training, the post-workout share goes to the other meals, so
    /// following the suggestions still reaches the daily target. Choosing
    /// post-workout anyway keeps its usual share.
    static func share(for slot: MealSlot, isTrainingDay: Bool) -> Double {
        guard !isTrainingDay, slot != .postWorkout else { return share(for: slot) }
        return share(for: slot) / (1 - share(for: .postWorkout))
    }

    /// Below this many remaining kcal a slot counts as already hit: no
    /// meaningful meal fits, so the API should never be called under it.
    static let minimumMealCalories = 100

    /// From this hour, dinner and snacks are the last chance to close the
    /// day's gap, so they may take more than their usual share.
    static let closingHour = 18
    /// The most a closing meal asks for, so a big gap at night doesn't become
    /// one enormous meal.
    static let closingMealShare = 0.4

    /// This slot's share of the daily targets, rounded per macro.
    static func targets(for slot: MealSlot, daily: MacroTargets, isTrainingDay: Bool = true) -> MacroTargets {
        targets(share: share(for: slot, isTrainingDay: isTrainingDay), daily: daily)
    }

    private static func targets(share: Double, daily: MacroTargets) -> MacroTargets {
        MacroTargets(
            calories: Int((Double(daily.calories) * share).rounded()),
            proteinG: Int((Double(daily.proteinG) * share).rounded()),
            carbsG: Int((Double(daily.carbsG) * share).rounded()),
            fatG: Int((Double(daily.fatG) * share).rounded())
        )
    }

    /// What this meal should provide: its target minus what's already logged
    /// in the slot, and never more than what's left of the day.
    static func remaining(
        for slot: MealSlot,
        daily: MacroTargets,
        slotConsumed: [Consumed],
        dayConsumed: [Consumed],
        isTrainingDay: Bool,
        hour: Int
    ) -> RemainingMacros {
        var share = share(for: slot, isTrainingDay: isTrainingDay)
        if hour >= closingHour, slot == .dinner || slot == .snack {
            share = max(share, closingMealShare)
        }
        let target = targets(share: share, daily: daily)
        let slotEaten = total(slotConsumed)
        let dayEaten = total(dayConsumed)

        func left(_ target: Int, _ slotEaten: Double, _ dailyTarget: Int, _ dayEaten: Double) -> Int {
            max(0, min(target - Int(slotEaten.rounded()), dailyTarget - Int(dayEaten.rounded())))
        }
        return RemainingMacros(
            calories: left(target.calories, slotEaten.calories, daily.calories, dayEaten.calories),
            proteinG: left(target.proteinG, slotEaten.proteinG, daily.proteinG, dayEaten.proteinG),
            carbsG: left(target.carbsG, slotEaten.carbsG, daily.carbsG, dayEaten.carbsG),
            fatG: left(target.fatG, slotEaten.fatG, daily.fatG, dayEaten.fatG)
        )
    }

    /// The same, from a day's diary entries.
    static func remaining(
        for slot: MealSlot,
        daily: MacroTargets,
        entries: [FoodEntry],
        isTrainingDay: Bool,
        hour: Int
    ) -> RemainingMacros {
        let consumed: (FoodEntry) -> Consumed = { ($0.calories, $0.proteinG, $0.carbsG, $0.fatG) }
        return remaining(
            for: slot,
            daily: daily,
            slotConsumed: entries.filter { $0.mealSlot == slot }.map(consumed),
            dayConsumed: entries.map(consumed),
            isTrainingDay: isTrainingDay,
            hour: hour
        )
    }

    private static func total(_ consumed: [Consumed]) -> Consumed {
        consumed.reduce((calories: 0.0, proteinG: 0.0, carbsG: 0.0, fatG: 0.0)) {
            ($0.calories + $1.calories, $0.proteinG + $1.proteinG,
             $0.carbsG + $1.carbsG, $0.fatG + $1.fatG)
        }
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

    /// The meal the suggestion should target: the first one not yet logged, in
    /// the order that suits the clock. Distinct from MealSlot.suggested(for:),
    /// which pre-selects a quick-log slot without workout or logged-meal context.
    static func mealType(hour: Int, hasTrainedToday: Bool, loggedSlots: Set<MealSlot>) -> MealSlot {
        let postWorkout: [MealSlot] = hasTrainedToday ? [.postWorkout] : []
        let order: [MealSlot] = switch hour {
        case ..<10: [.breakfast] + postWorkout + [.lunch]
        case 10..<13: postWorkout + [.lunch, .snack]
        case 13..<17: [.lunch] + postWorkout + [.snack, .dinner]
        case 17..<21: [.dinner, .snack]
        default: [.snack]
        }
        return order.first { !loggedSlots.contains($0) } ?? order.last ?? .snack
    }
}
