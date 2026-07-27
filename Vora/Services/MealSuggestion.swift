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

/// One food line in a suggestion, directly searchable in OpenFoodFacts.
struct SuggestedFood: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    let name: String
    let grams: Double
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
