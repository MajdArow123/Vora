//
//  MealSuggestionViewModel.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-26.
//

import Foundation
import Observation
import OSLog

/// Drives one AI meal suggestion surface (Home card or the diary sheet).
/// Each surface owns its own instance; the UserDefaults cache holds one
/// suggestion per meal per day and is the shared source of truth, so either
/// surface can reuse what the other fetched.
@MainActor
@Observable
final class MealSuggestionViewModel {
    private nonisolated static let logger = Logger(subsystem: "com.majdarow.Vora", category: "MealSuggestion")

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
    /// Wait before the one retry of a failed lookup; OpenFoodFacts often
    /// answers 503 under load. Tests pass .zero.
    private let enrichmentRetryDelay: Duration
    /// Identifies the latest load, so a slower older one can't overwrite it.
    private var loadGeneration = 0

    static let cacheDateKey = "vora.mealSuggestion.date"
    /// JSON of `[String: MealSuggestion]` by `cacheKey(for:)`.
    static let cachePayloadKey = "vora.mealSuggestion.payloads"
    /// The single-suggestion format this replaced.
    private static let legacyCachePayloadKey = "vora.mealSuggestion.payload"

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
        enrichmentStagger: Duration = .milliseconds(100),
        enrichmentRetryDelay: Duration = .seconds(1)
    ) {
        self.defaults = defaults
        self.fetch = fetch
        self.search = search
        self.enrichmentStagger = enrichmentStagger
        self.enrichmentRetryDelay = enrichmentRetryDelay
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
        let retryDelay = enrichmentRetryDelay
        enrichmentTask = Task { [weak self] in
            await withTaskGroup(of: (UUID, FoodItem?).self) { group in
                for (index, lookup) in lookups.enumerated() {
                    group.addTask {
                        (lookup.id, await Self.lookUp(lookup.name, after: stagger * index, retryDelay: retryDelay, search: search))
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

    /// The product that really is this food, or nil to fall back on an estimate.
    /// A failed search is tried once more; a cancelled run stops quietly.
    private nonisolated static func lookUp(
        _ name: String,
        after delay: Duration,
        retryDelay: Duration,
        search: @Sendable (String) async throws -> [FoodItem]
    ) async -> FoodItem? {
        for wait in [delay, retryDelay] {
            do {
                try await Task.sleep(for: wait)
                return FoodMatcher.bestMatch(for: name, in: try await search(name))
            } catch {
                if Task.isCancelled { return nil }
                logger.notice("Food lookup failed: \(String(describing: error), privacy: .public)")
            }
        }
        return nil
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
    /// surfaces converge. `preference` is always a fresh input, never cached.
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
        loadGeneration += 1
        let generation = loadGeneration
        if !force, let cached = cachedSuggestions(todayKey: todayKey)[Self.cacheKey(for: mealType)] {
            state = .loaded(cached)
            return
        }

        let previous = state == .loading ? SuggestionState.idle : state
        state = .loading
        do {
            let suggestion = try await fetch(
                remaining,
                goal,
                calendar.component(.hour, from: now),
                mealType,
                preference
            )
            // Still worth keeping for its meal, even if it's no longer wanted here.
            store(suggestion, mealType: mealType, todayKey: todayKey)
            if generation == loadGeneration { state = .loaded(suggestion) }
        } catch {
            guard generation == loadGeneration else { return }
            state = MealSuggestionError.isCancellation(error)
                ? previous
                : .failed(MealSuggestionError.message(for: error))
        }
    }

    /// Shows the cached suggestion for this meal without ever hitting the
    /// network, or nothing on a miss: another meal's suggestion must not stay
    /// on screen. The suggestion sheet uses this so generation stays button-driven.
    func loadCached(mealType: MealSlot? = nil, now: Date = .now) {
        loadGeneration += 1
        let todayKey = Self.dayKey(for: now, calendar: .current)
        if let cached = cachedSuggestions(todayKey: todayKey)[Self.cacheKey(for: mealType)] {
            state = .loaded(cached)
        } else {
            cancelEnrichment()
            enrichedFoods = []
            state = .idle
        }
    }

    /// Forgets a meal's suggestion once it's logged, so it isn't offered again.
    func clearCached(mealType: MealSlot?, now: Date = .now) {
        let todayKey = Self.dayKey(for: now, calendar: .current)
        var suggestions = cachedSuggestions(todayKey: todayKey)
        suggestions[Self.cacheKey(for: mealType)] = nil
        write(suggestions, todayKey: todayKey)
    }

    static func cacheKey(for mealType: MealSlot?) -> String {
        mealType?.rawValue ?? "any"
    }

    private func store(_ suggestion: MealSuggestion, mealType: MealSlot?, todayKey: String) {
        var suggestions = cachedSuggestions(todayKey: todayKey)
        suggestions[Self.cacheKey(for: mealType)] = suggestion
        write(suggestions, todayKey: todayKey)
    }

    /// A failed write only costs a repeat fetch later.
    private func write(_ suggestions: [String: MealSuggestion], todayKey: String) {
        do {
            defaults.set(try JSONEncoder().encode(suggestions), forKey: Self.cachePayloadKey)
            defaults.set(todayKey, forKey: Self.cacheDateKey)
            defaults.removeObject(forKey: Self.legacyCachePayloadKey)
        } catch {
            Self.logger.error("Couldn't cache the suggestion: \(String(describing: error), privacy: .public)")
        }
    }

    /// Today's suggestions by meal. Other days and unreadable payloads read as
    /// empty, which just means a fresh fetch.
    private func cachedSuggestions(todayKey: String) -> [String: MealSuggestion] {
        guard defaults.string(forKey: Self.cacheDateKey) == todayKey,
              let data = defaults.data(forKey: Self.cachePayloadKey) else { return [:] }
        do {
            return try JSONDecoder().decode([String: MealSuggestion].self, from: data)
        } catch {
            Self.logger.notice("Ignoring an unreadable suggestion cache: \(String(describing: error), privacy: .public)")
            return [:]
        }
    }

    static func dayKey(for date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }
}
