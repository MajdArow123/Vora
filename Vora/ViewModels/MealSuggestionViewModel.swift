//
//  MealSuggestionViewModel.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-26.
//

import Foundation
import Observation

/// Drives one AI meal suggestion surface (Home card or the diary sheet).
/// Each surface owns its own instance; the per-day UserDefaults cache is
/// the shared source of truth, so at most one backend call happens per day
/// no matter which surface fetches first.
@MainActor
@Observable
final class MealSuggestionViewModel {
    enum SuggestionState: Equatable {
        case idle
        case loading
        case loaded(MealSuggestion)
        case failed(String)
    }

    private(set) var state: SuggestionState = .idle

    private let defaults: UserDefaults
    /// Injectable for tests; defaults to the live ProTracker backend call.
    private let fetch: (RemainingMacros, GoalType, Int) async throws -> MealSuggestion
    private let cacheDateKey = "vora.mealSuggestion.date"
    private let cachePayloadKey = "vora.mealSuggestion.payload"

    init(
        defaults: UserDefaults = .standard,
        fetch: @escaping (RemainingMacros, GoalType, Int) async throws -> MealSuggestion = { remaining, goal, hour in
            try await MealSuggestionService().fetchSuggestion(remaining: remaining, goal: goal, hour: hour)
        }
    ) {
        self.defaults = defaults
        self.fetch = fetch
    }

    /// Cache-first load. `force` (the Refresh button) skips the cache read
    /// but still writes the fresh result back so all surfaces converge.
    func load(remaining: RemainingMacros, goal: GoalType, force: Bool = false, now: Date = .now) async {
        let calendar = Calendar.current
        let todayKey = Self.dayKey(for: now, calendar: calendar)
        if !force,
           defaults.string(forKey: cacheDateKey) == todayKey,
           let data = defaults.data(forKey: cachePayloadKey),
           let cached = try? JSONDecoder().decode(MealSuggestion.self, from: data) {
            state = .loaded(cached)
            return
        }

        state = .loading
        do {
            let suggestion = try await fetch(
                remaining,
                goal,
                calendar.component(.hour, from: now)
            )
            defaults.set(todayKey, forKey: cacheDateKey)
            defaults.set(try? JSONEncoder().encode(suggestion), forKey: cachePayloadKey)
            state = .loaded(suggestion)
        } catch {
            state = .failed("Couldn't generate suggestion. Check your connection.")
        }
    }

    static func dayKey(for date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }
}
