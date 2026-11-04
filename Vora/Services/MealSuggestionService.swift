//
//  MealSuggestionService.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-26.
//

import Foundation
import OSLog

enum MealSuggestionError: LocalizedError, Equatable {
    /// This build has no app token; see Secrets.example.xcconfig.
    case notConfigured
    /// The backend refused the request or is down; retrying now won't help.
    case unavailable
    case badResponse
    case emptyContent

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Meal suggestions aren't configured in this build."
        case .unavailable: "Meal suggestions aren't available right now. Try again later."
        case .badResponse: "Couldn't read the suggestion. Try again."
        case .emptyContent: "The suggestion came back empty. Try again."
        }
    }

    static let connectionMessage = "Couldn't generate suggestion. Check your connection."

    /// What to tell the user about any failure from a fetch.
    static func message(for error: Error) -> String {
        if let error = error as? MealSuggestionError, let description = error.errorDescription {
            return description
        }
        return connectionMessage
    }

    /// A cancelled request isn't a failure: nobody is waiting for it.
    static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }
}

/// Calls the ProTracker backend to generate a meal suggestion. The backend holds
/// the model credentials and requires a shared app token, which comes from the
/// untracked Secrets.xcconfig by way of Info.plist.
struct MealSuggestionService {
    static let timeout: TimeInterval = 15

    private static let logger = Logger(subsystem: "com.majdarow.Vora", category: "MealSuggestion")
    private static let endpoint = "https://protracker-production.up.railway.app/api/v1/meal-suggestion"
    private static let tokenHeader = "X-App-Token"
    private static let tokenInfoKey = "MealSuggestionAppToken"

    private let token: String?
    /// Injectable so tests never reach the backend.
    private let send: (URLRequest) async throws -> (Data, URLResponse)

    init(
        token: String? = MealSuggestionService.configuredToken(),
        send: @escaping (URLRequest) async throws -> (Data, URLResponse) = { try await URLSession.shared.data(for: $0) }
    ) {
        self.token = token
        self.send = send
    }

    /// The build's token, or nil when Secrets.xcconfig didn't supply one. An
    /// unset build setting leaves the value empty or as its literal `$(NAME)`.
    static func configuredToken(in info: [String: Any]? = Bundle.main.infoDictionary) -> String? {
        guard let value = (info?[tokenInfoKey] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty, !value.hasPrefix("$(") else { return nil }
        return value
    }

    func fetchSuggestion(
        remaining: RemainingMacros,
        goal: GoalType,
        hour: Int,
        mealType: MealSlot? = nil,
        userPreference: String? = nil
    ) async throws -> MealSuggestion {
        // The backend rejects caloriesRemaining <= 0 with a 400; the UI's
        // "targets hit" gate should make this unreachable.
        guard remaining.calories > 0, let url = URL(string: Self.endpoint) else {
            Self.logger.error("Skipped a request: \(remaining.calories, privacy: .public) kcal remaining")
            throw MealSuggestionError.badResponse
        }

        guard let token else {
            Self.logger.notice("No app token in this build; not calling the backend")
            throw MealSuggestionError.notConfigured
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: Self.tokenHeader)
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

        let (data, response) = try await send(request)
        let status = (response as? HTTPURLResponse)?.statusCode
        guard status == 200 else {
            Self.logger.error("Suggestion request failed with status \(status ?? -1, privacy: .public)")
            throw Self.error(forStatus: status)
        }

        let decoded: SuggestionResponse
        do {
            decoded = try JSONDecoder().decode(SuggestionResponse.self, from: data)
        } catch {
            Self.logger.error("Couldn't decode the suggestion: \(String(describing: error), privacy: .public)")
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

    /// Refused and server-side failures are "unavailable", since the user's
    /// connection is fine; anything else means we sent or read something wrong.
    static func error(forStatus status: Int?) -> MealSuggestionError {
        switch status ?? 0 {
        case 401, 403, 404, 429, 500...599: .unavailable
        default: .badResponse
        }
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
