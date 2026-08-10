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

    /// The loaded suggestion's foods with real OpenFoodFacts data and the
    /// sheet's portion edits. Only populated by `enrich()`, which the sheet
    /// calls — the Home card's instance never enriches, so it stays offline.
    private(set) var enrichedFoods: [EnrichedFood] = []
    /// Exposed so tests can await a full enrichment pass.
    private(set) var enrichmentTask: Task<Void, Never>?

    private let defaults: UserDefaults
    /// Injectable for tests; defaults to the live ProTracker backend call.
    private let fetch: (RemainingMacros, GoalType, Int, MealSlot?, String?) async throws -> MealSuggestion
    /// Injectable for tests; defaults to the live OpenFoodFacts search.
    private let search: @Sendable (String) async throws -> [FoodItem]
    /// Delay between lookup starts — courtesy spacing for the OpenFoodFacts
    /// rate limit. Tests pass .zero.
    private let enrichmentStagger: Duration
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
        },
        search: @escaping @Sendable (String) async throws -> [FoodItem] = {
            try await OpenFoodFactsClient().search($0)
        },
        enrichmentStagger: Duration = .milliseconds(100)
    ) {
        self.defaults = defaults
        self.fetch = fetch
        self.search = search
        self.enrichmentStagger = enrichmentStagger
    }

    // MARK: - Enrichment

    /// Rebuilds `enrichedFoods` from the loaded suggestion and starts
    /// concurrent (staggered) OpenFoodFacts lookups, updating each food as
    /// its result lands. Cancels any in-flight run first; no-op unless a
    /// suggestion is loaded.
    func enrich() {
        guard case .loaded(let suggestion) = state else { return }
        cancelEnrichment()
        enrichedFoods = suggestion.foods.map(EnrichedFood.init)

        let lookups = enrichedFoods.map { (id: $0.id, name: $0.suggestedName) }
        let search = search
        let stagger = enrichmentStagger
        enrichmentTask = Task { [weak self] in
            await withTaskGroup(of: (UUID, FoodItem?).self) { group in
                for (index, lookup) in lookups.enumerated() {
                    group.addTask {
                        try? await Task.sleep(for: stagger * index)
                        guard !Task.isCancelled else { return (lookup.id, nil) }
                        return (lookup.id, (try? await search(lookup.name))?.first)
                    }
                }
                for await (id, item) in group {
                    // A cancelled run must never stamp a food as resolved —
                    // a fresh enrich() may already have reseeded the array.
                    guard !Task.isCancelled else { return }
                    self?.applyEnrichment(id: id, item: item)
                }
            }
        }
    }

    func cancelEnrichment() {
        enrichmentTask?.cancel()
        enrichmentTask = nil
    }

    private func applyEnrichment(id: UUID, item: FoodItem?) {
        guard let index = enrichedFoods.firstIndex(where: { $0.id == id }) else { return }
        enrichedFoods[index].realFoodItem = item
        enrichedFoods[index].isLoading = false
    }

    // MARK: - Portion edits

    func adjustGrams(id: UUID, by delta: Double, minimum: Double = 10) {
        guard let index = enrichedFoods.firstIndex(where: { $0.id == id }) else { return }
        enrichedFoods[index].editedGrams = max(minimum, enrichedFoods[index].editedGrams + delta)
    }

    /// Marks a food removed rather than deleting it, so late lookup results
    /// still find their row and `hasEdits` can see the removal.
    func removeFood(id: UUID) {
        guard let index = enrichedFoods.firstIndex(where: { $0.id == id }) else { return }
        enrichedFoods[index].isRemoved = true
    }

    var activeFoods: [EnrichedFood] { enrichedFoods.filter { !$0.isRemoved } }

    /// Double equality is safe here: edits move in fixed ±10 steps from the
    /// same original value.
    var hasEdits: Bool {
        enrichedFoods.contains { $0.isRemoved || $0.editedGrams != $0.originalGrams }
    }

    var isEnriching: Bool { activeFoods.contains(where: \.isLoading) }

    var mealTotals: (calories: Double, proteinG: Double, carbsG: Double, fatG: Double) {
        activeFoods.reduce((calories: 0.0, proteinG: 0.0, carbsG: 0.0, fatG: 0.0)) { acc, food in
            let n = food.nutrition
            return (acc.calories + n.calories, acc.proteinG + n.proteinG,
                    acc.carbsG + n.carbsG, acc.fatG + n.fatG)
        }
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
