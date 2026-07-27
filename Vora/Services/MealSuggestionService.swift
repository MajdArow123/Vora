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
        hour: Int
    ) async throws -> MealSuggestion {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = Self.timeout
        request.httpBody = try JSONEncoder().encode(
            SuggestionRequest(
                caloriesRemaining: max(0, remaining.calories),
                proteinRemaining: max(0, remaining.proteinG),
                carbsRemaining: max(0, remaining.carbsG),
                fatRemaining: max(0, remaining.fatG),
                goalType: goal.rawValue,
                timeOfDay: MealSuggestionContext.timeOfDay(hour: hour)
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
        guard !mealName.isEmpty else {
            throw MealSuggestionError.emptyContent
        }
        let detail = decoded.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        return MealSuggestion(
            rawText: detail.isEmpty ? mealName : "\(mealName)\n\(detail)",
            generatedAt: Self.parseDate(decoded.generatedAt) ?? .now
        )
    }

    /// The backend sends ISO 8601, with or without fractional seconds.
    static func parseDate(_ string: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: string) ?? ISO8601DateFormatter().date(from: string)
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
}

private struct SuggestionResponse: Decodable {
    let mealName: String
    let detail: String
    let generatedAt: String
}
