//
//  MealSuggestionService.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-26.
//

import Foundation

enum MealSuggestionError: LocalizedError {
    case badResponse
    case emptyContent

    var errorDescription: String? {
        switch self {
        case .badResponse: "Couldn't generate suggestion. Check your connection."
        case .emptyContent: "The suggestion came back empty. Try again."
        }
    }
}

/// Calls the ProTracker backend to generate a meal suggestion. No API key
/// or setup is required — the backend holds the model credentials.
struct MealSuggestionService {
    static let timeout: TimeInterval = 15

    private static let endpoint = URL(
        string: "https://protracker-production.up.railway.app/api/v1/meal-suggestion"
    )!

    func fetchSuggestion(
        remaining: RemainingMacros,
        goal: GoalType,
        hour: Int,
        mealType: MealSlot? = nil,
        userPreference: String? = nil
    ) async throws -> MealSuggestion {
        // The backend rejects caloriesRemaining <= 0 with a 400.
        guard remaining.calories > 0 else {
            throw MealSuggestionError.badResponse
        }

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = Self.timeout
        request.httpBody = try JSONEncoder().encode(
            SuggestionRequest(
                caloriesRemaining: remaining.calories,
                proteinRemaining: max(0, remaining.proteinG),
                carbsRemaining: max(0, remaining.carbsG),
                fatRemaining: max(0, remaining.fatG),
                goalType: goal.rawValue,
                timeOfDay: MealSuggestionContext.timeOfDay(hour: hour),
                mealType: mealType?.rawValue,
                userPreference: Self.normalizedPreference(userPreference)
            )
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw MealSuggestionError.badResponse
        }

        guard let decoded = try? JSONDecoder().decode(SuggestionResponse.self, from: data) else {
            throw MealSuggestionError.badResponse
        }
        let mealName = decoded.mealName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !mealName.isEmpty, !decoded.foods.isEmpty else {
            throw MealSuggestionError.emptyContent
        }
        return MealSuggestion(
            mealName: mealName,
            mealType: decoded.mealType,
            description: decoded.description.trimmingCharacters(in: .whitespacesAndNewlines),
            foods: decoded.foods,
            cookingTip: decoded.cookingTip.trimmingCharacters(in: .whitespacesAndNewlines),
            generatedAt: Self.parseDate(decoded.generatedAt) ?? .now
        )
    }

    /// The backend sends ISO 8601, with or without fractional seconds.
    static func parseDate(_ string: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }

    /// The backend caps userPreference at 100 characters; nil when empty
    /// so the field is omitted from the request entirely.
    static func normalizedPreference(_ preference: String?) -> String? {
        guard let trimmed = preference?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(100))
    }
}

// MARK: - ProTracker wire types

private struct SuggestionRequest: Encodable {
    let caloriesRemaining: Int
    let proteinRemaining: Int
    let carbsRemaining: Int
    let fatRemaining: Int
    let goalType: String
    let timeOfDay: String
    let mealType: String?
    let userPreference: String?
}

private struct SuggestionResponse: Decodable {
    let mealName: String
    let mealType: String
    let description: String
    let foods: [SuggestedFood]
    let cookingTip: String
    let generatedAt: String
}
