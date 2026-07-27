//
//  MealSuggestionTests.swift
//  VoraTests
//
//  Created by Majd Arow on 2026-07-26.
//

import Foundation
import Testing
@testable import Vora

private func makeSuggestion(
    mealName: String = "Chicken Bowl",
    mealType: String = "dinner",
    foods: [SuggestedFood] = [SuggestedFood(name: "chicken breast", grams: 200, unit: "g")]
) -> MealSuggestion {
    MealSuggestion(
        mealName: mealName,
        mealType: mealType,
        description: "A balanced plate.",
        foods: foods,
        cookingTip: "Season well.",
        generatedAt: .now
    )
}

struct SuggestedFoodCodableTests {
    @Test func decodesBackendJSONWithoutID() throws {
        let json = Data(#"{"name":"chicken breast","grams":200,"unit":"g"}"#.utf8)
        let food = try JSONDecoder().decode(SuggestedFood.self, from: json)
        #expect(food.name == "chicken breast")
        #expect(food.grams == 200)
        #expect(food.unit == "g")
    }

    @Test func encodingOmitsID() throws {
        let food = SuggestedFood(name: "rice", grams: 150, unit: "g")
        let data = try JSONEncoder().encode(food)
        let keys = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any]).keys
        #expect(Set(keys) == ["name", "grams", "unit"])
    }

    @Test func equalityIgnoresID() {
        let a = SuggestedFood(name: "rice", grams: 150, unit: "g")
        let b = SuggestedFood(name: "rice", grams: 150, unit: "g")
        #expect(a == b)
        #expect(a.id != b.id)
    }

    @Test func slotMapsMealTypeWithSnackFallback() {
        #expect(makeSuggestion(mealType: "postWorkout").slot == .postWorkout)
        #expect(makeSuggestion(mealType: "dinner").slot == .dinner)
        #expect(makeSuggestion(mealType: "brunch").slot == .snack)
    }
}

struct MealSuggestionContextTests {
    @Test func timeOfDayBoundaries() {
        #expect(MealSuggestionContext.timeOfDay(hour: 4) == "night")
        #expect(MealSuggestionContext.timeOfDay(hour: 5) == "morning")
        #expect(MealSuggestionContext.timeOfDay(hour: 11) == "morning")
        #expect(MealSuggestionContext.timeOfDay(hour: 12) == "afternoon")
        #expect(MealSuggestionContext.timeOfDay(hour: 16) == "afternoon")
        #expect(MealSuggestionContext.timeOfDay(hour: 17) == "evening")
        #expect(MealSuggestionContext.timeOfDay(hour: 20) == "evening")
        #expect(MealSuggestionContext.timeOfDay(hour: 21) == "night")
        #expect(MealSuggestionContext.timeOfDay(hour: 0) == "night")
    }

    @Test func mealTypeBoundaries() {
        #expect(MealSuggestionContext.mealType(hour: 9, hasTrainedToday: false, loggedSlots: []) == .breakfast)
        #expect(MealSuggestionContext.mealType(hour: 10, hasTrainedToday: false, loggedSlots: []) == .lunch)
        #expect(MealSuggestionContext.mealType(hour: 12, hasTrainedToday: false, loggedSlots: []) == .lunch)
        #expect(MealSuggestionContext.mealType(hour: 13, hasTrainedToday: false, loggedSlots: []) == .lunch)
        #expect(MealSuggestionContext.mealType(hour: 16, hasTrainedToday: false, loggedSlots: []) == .lunch)
        #expect(MealSuggestionContext.mealType(hour: 17, hasTrainedToday: false, loggedSlots: []) == .dinner)
        #expect(MealSuggestionContext.mealType(hour: 20, hasTrainedToday: false, loggedSlots: []) == .dinner)
        #expect(MealSuggestionContext.mealType(hour: 21, hasTrainedToday: false, loggedSlots: []) == .snack)
        #expect(MealSuggestionContext.mealType(hour: 23, hasTrainedToday: false, loggedSlots: []) == .snack)
    }

    @Test func mealTypeMidMorningPrefersPostWorkoutAfterTraining() {
        #expect(MealSuggestionContext.mealType(hour: 11, hasTrainedToday: true, loggedSlots: []) == .postWorkout)
        #expect(MealSuggestionContext.mealType(hour: 11, hasTrainedToday: false, loggedSlots: []) == .lunch)
    }

    @Test func mealTypeAfternoonBecomesSnackOnceLunchIsLogged() {
        #expect(MealSuggestionContext.mealType(hour: 14, hasTrainedToday: false, loggedSlots: [.lunch]) == .snack)
        #expect(MealSuggestionContext.mealType(hour: 14, hasTrainedToday: false, loggedSlots: [.breakfast]) == .lunch)
    }
}

struct MealSuggestionServiceTests {
    @Test func parseDateAcceptsISO8601WithAndWithoutFractionalSeconds() {
        #expect(MealSuggestionService.parseDate("2026-07-27T12:34:56Z") != nil)
        #expect(MealSuggestionService.parseDate("2026-07-27T12:34:56.789Z") != nil)
        #expect(MealSuggestionService.parseDate("not a date") == nil)
    }

    @Test func normalizedPreferenceTrimsAndCaps() {
        #expect(MealSuggestionService.normalizedPreference(nil) == nil)
        #expect(MealSuggestionService.normalizedPreference("   ") == nil)
        #expect(MealSuggestionService.normalizedPreference(" chicken ") == "chicken")
        let long = String(repeating: "a", count: 150)
        #expect(MealSuggestionService.normalizedPreference(long)?.count == 100)
    }
}

@MainActor
struct MealSuggestionViewModelTests {
    private func makeDefaults() -> UserDefaults {
        let suiteName = "MealSuggestionVMTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func cache(_ suggestion: MealSuggestion, in defaults: UserDefaults) {
        defaults.set(
            MealSuggestionViewModel.dayKey(for: .now, calendar: .current),
            forKey: "vora.mealSuggestion.date"
        )
        defaults.set(try? JSONEncoder().encode(suggestion), forKey: "vora.mealSuggestion.payload")
    }

    private let remaining = RemainingMacros(calories: 700, proteinG: 50, carbsG: 70, fatG: 20)

    /// Stands in for the ProTracker endpoint: returns a structured
    /// suggestion the way the live service does after decoding.
    private func backendMock(
        mealName: String
    ) -> (RemainingMacros, GoalType, Int, MealSlot?, String?) async throws -> MealSuggestion {
        { _, _, _, _, _ in makeSuggestion(mealName: mealName) }
    }

    @Test func loadFetchesFromBackendAndCaches() async {
        let defaults = makeDefaults()
        let viewModel = MealSuggestionViewModel(
            defaults: defaults,
            fetch: backendMock(mealName: "Chicken Bowl")
        )
        await viewModel.load(remaining: remaining, goal: .maintain)
        guard case .loaded(let suggestion) = viewModel.state else {
            Issue.record("expected loaded state, got \(viewModel.state)")
            return
        }
        #expect(suggestion.mealName == "Chicken Bowl")

        let storedData = defaults.data(forKey: "vora.mealSuggestion.payload")
        let stored = storedData.flatMap { try? JSONDecoder().decode(MealSuggestion.self, from: $0) }
        #expect(stored?.mealName == "Chicken Bowl")
        #expect(stored?.foods.count == 1)
    }

    @Test func sameDayCacheSkipsFetch() async {
        let defaults = makeDefaults()
        let cached = makeSuggestion(mealName: "Cached Meal")
        cache(cached, in: defaults)

        let viewModel = MealSuggestionViewModel(defaults: defaults) { _, _, _, _, _ in
            Issue.record("fetch should not run on a same-day cache hit")
            return makeSuggestion(mealName: "Wrong")
        }
        await viewModel.load(remaining: remaining, goal: .fatLoss)
        #expect(viewModel.state == .loaded(cached))
    }

    @Test func forceRefreshBypassesCacheAndRewritesIt() async {
        let defaults = makeDefaults()
        cache(makeSuggestion(mealName: "Stale Meal"), in: defaults)

        let viewModel = MealSuggestionViewModel(
            defaults: defaults,
            fetch: backendMock(mealName: "Fresh Meal")
        )
        await viewModel.load(remaining: remaining, goal: .maintain, force: true)
        guard case .loaded(let suggestion) = viewModel.state else {
            Issue.record("expected loaded state, got \(viewModel.state)")
            return
        }
        #expect(suggestion.mealName == "Fresh Meal")

        let storedData = defaults.data(forKey: "vora.mealSuggestion.payload")
        let stored = storedData.flatMap { try? JSONDecoder().decode(MealSuggestion.self, from: $0) }
        #expect(stored?.mealName == "Fresh Meal")
    }

    @Test func oldRawTextCacheFormatFallsThroughToFetch() async {
        let defaults = makeDefaults()
        defaults.set(
            MealSuggestionViewModel.dayKey(for: .now, calendar: .current),
            forKey: "vora.mealSuggestion.date"
        )
        defaults.set(
            Data(#"{"rawText":"Chicken Bowl\n200g chicken","generatedAt":0}"#.utf8),
            forKey: "vora.mealSuggestion.payload"
        )

        let viewModel = MealSuggestionViewModel(
            defaults: defaults,
            fetch: backendMock(mealName: "Migrated Meal")
        )
        await viewModel.load(remaining: remaining, goal: .maintain)
        guard case .loaded(let suggestion) = viewModel.state else {
            Issue.record("expected loaded state, got \(viewModel.state)")
            return
        }
        #expect(suggestion.mealName == "Migrated Meal")
    }

    @Test func loadCachedHitLoadsWithoutFetching() {
        let defaults = makeDefaults()
        let cached = makeSuggestion(mealName: "Cached Meal")
        cache(cached, in: defaults)

        let viewModel = MealSuggestionViewModel(defaults: defaults) { _, _, _, _, _ in
            Issue.record("loadCached must never fetch")
            return makeSuggestion(mealName: "Wrong")
        }
        viewModel.loadCached()
        #expect(viewModel.state == .loaded(cached))
    }

    @Test func loadCachedMissStaysIdle() {
        let viewModel = MealSuggestionViewModel(defaults: makeDefaults()) { _, _, _, _, _ in
            Issue.record("loadCached must never fetch")
            return makeSuggestion(mealName: "Wrong")
        }
        viewModel.loadCached()
        #expect(viewModel.state == .idle)
    }

    @Test func mealTypeAndPreferenceReachTheBackend() async {
        var receivedMealType: MealSlot?
        var receivedPreference: String?
        let viewModel = MealSuggestionViewModel(defaults: makeDefaults()) { _, _, _, mealType, preference in
            receivedMealType = mealType
            receivedPreference = preference
            return makeSuggestion(mealName: "Any")
        }
        await viewModel.load(
            remaining: remaining,
            goal: .maintain,
            mealType: .postWorkout,
            preference: "something with chicken",
            force: true
        )
        #expect(receivedMealType == .postWorkout)
        #expect(receivedPreference == "something with chicken")
    }

    @Test func fetchFailureShowsConnectionCopy() async {
        let viewModel = MealSuggestionViewModel(defaults: makeDefaults()) { _, _, _, _, _ in
            throw URLError(.notConnectedToInternet)
        }
        await viewModel.load(remaining: remaining, goal: .maintain)
        #expect(viewModel.state == MealSuggestionViewModel.SuggestionState.failed("Couldn't generate suggestion. Check your connection."))
    }

    @Test func backendErrorShowsConnectionCopy() async {
        let viewModel = MealSuggestionViewModel(defaults: makeDefaults()) { _, _, _, _, _ in
            throw MealSuggestionError.badResponse
        }
        await viewModel.load(remaining: remaining, goal: .maintain)
        #expect(viewModel.state == MealSuggestionViewModel.SuggestionState.failed("Couldn't generate suggestion. Check your connection."))
    }
}
