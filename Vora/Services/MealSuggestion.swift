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

/// One AI-generated meal suggestion, cached per day.
struct MealSuggestion: Codable, Equatable, Sendable {
    let rawText: String
    let generatedAt: Date

    /// First non-empty line, stripped of surrounding whitespace and markdown asterisks.
    var mealName: String {
        Self.lines(of: rawText).first.map(Self.cleaned) ?? ""
    }

    /// Everything after the meal name line.
    var detail: String {
        Self.lines(of: rawText).dropFirst()
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Extracts the first food name from a suggestion for pre-filling food
    /// search, e.g. "200g chicken breast + 1 cup rice" -> "chicken breast".
    static func firstFoodName(in rawText: String) -> String? {
        let allLines = lines(of: rawText)
        guard let source = allLines.count > 1 ? allLines.dropFirst().first : allLines.first else {
            return nil
        }
        var component = cleaned(String(source))
        if let comma = component.firstIndex(of: ",") {
            component = String(component[..<comma])
        }
        component = component.components(separatedBy: "+")[0]

        let fillerWords: Set<String> = [
            "of", "a", "an", "cup", "cups", "tbsp", "tsp",
            "scoop", "scoops", "slice", "slices", "small", "medium", "large",
        ]
        var words = component.split(separator: " ").map(String.init)
        while let first = words.first,
              first.rangeOfCharacter(from: .decimalDigits) != nil
                  || fillerWords.contains(first.lowercased()) {
            words.removeFirst()
        }
        let name = words.joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,.:;–-"))
        if !name.isEmpty { return name }
        let fallback = component.trimmingCharacters(in: .whitespacesAndNewlines)
        return fallback.isEmpty ? nil : fallback
    }

    private static func lines(of text: String) -> [Substring] {
        text.split(separator: "\n", omittingEmptySubsequences: true)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private static func cleaned(_ line: some StringProtocol) -> String {
        line.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "*"))
            .trimmingCharacters(in: .whitespaces)
    }
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
}
