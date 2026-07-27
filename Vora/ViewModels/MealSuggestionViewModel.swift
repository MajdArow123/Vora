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
    private let fetch: (RemainingMacros, GoalType, Int, MealSlot?, String?) async throws -> MealSuggestion
    private let cacheDateKey = "vora.mealSuggestion.date"
    private let cachePayloadKey = "vora.mealSuggestion.payload"

    init(
        defaults: UserDefaults = .standard,
        fetch: @escaping (RemainingMacros, GoalType, Int, MealSlot?, String?) async throws -> MealSuggestion = { remaining, goal, hour, mealType, preference in
            try await MealSuggestionService().fetchSuggestion(
                remaining: remaining,
                goal: goal,
                hour: hour,
                mealType: mealType,
                userPreference: preference
            )
        }
    ) {
        self.defaults = defaults
        self.fetch = fetch
    }

    /// Cache-first load. `force` (the Refresh / Get suggestion buttons)
    /// skips the cache read but still writes the fresh result back so all
    /// surfaces converge. `mealType` and `preference` are always fresh
    /// inputs — never cached.
    func load(
        remaining: RemainingMacros,
        goal: GoalType,
        mealType: MealSlot? = nil,
        preference: String? = nil,
        force: Bool = false,
        now: Date = .now
    ) async {
        let calendar = Calendar.current
        let todayKey = Self.dayKey(for: now, calendar: calendar)
        if !force, let cached = cachedSuggestion(todayKey: todayKey) {
            state = .loaded(cached)
            return
        }

        state = .loading
        do {
            let suggestion = try await fetch(
                remaining,
                goal,
                calendar.component(.hour, from: now),
                mealType,
                preference
            )
            defaults.set(todayKey, forKey: cacheDateKey)
            defaults.set(try? JSONEncoder().encode(suggestion), forKey: cachePayloadKey)
            state = .loaded(suggestion)
        } catch {
            state = .failed("Couldn't generate suggestion. Check your connection.")
        }
    }

    /// Reads the day cache without ever hitting the network: `.loaded` on a
    /// hit, stays `.idle` on a miss. The suggestion sheet uses this on
    /// appear so generation stays button-driven.
    func loadCached(now: Date = .now) {
        let todayKey = Self.dayKey(for: now, calendar: .current)
        if let cached = cachedSuggestion(todayKey: todayKey) {
            state = .loaded(cached)
        }
    }

    private func cachedSuggestion(todayKey: String) -> MealSuggestion? {
        guard defaults.string(forKey: cacheDateKey) == todayKey,
              let data = defaults.data(forKey: cachePayloadKey) else { return nil }
        // Pre-structured cache payloads (rawText format) fail to decode and
        // fall through to a fresh fetch — the intended migration path.
        return try? JSONDecoder().decode(MealSuggestion.self, from: data)
    }

    static func dayKey(for date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }
}
