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

    @Test func mutatingGramsPreservesIDAndReencodes() throws {
        var food = SuggestedFood(name: "rice", grams: 150, unit: "g")
        let id = food.id
        food.grams = 180
        #expect(food.id == id)
        #expect(food.grams == 180)

        let data = try JSONEncoder().encode(food)
        let decoded = try JSONDecoder().decode(SuggestedFood.self, from: data)
        #expect(decoded.grams == 180)
        #expect(decoded.name == "rice")
    }
}

struct MealAllocationTests {
    private let daily = MacroTargets(calories: 2600, proteinG: 180, carbsG: 280, fatG: 80)

    @Test func sharesSumToOne() {
        let total = MealSlot.allCases.reduce(0) { $0 + MealAllocation.share(for: $1) }
        #expect(abs(total - 1.0) < 0.0001)
    }

    @Test func perSlotShares() {
        #expect(MealAllocation.share(for: .breakfast) == 0.25)
        #expect(MealAllocation.share(for: .postWorkout) == 0.20)
        #expect(MealAllocation.share(for: .lunch) == 0.25)
        #expect(MealAllocation.share(for: .dinner) == 0.25)
        #expect(MealAllocation.share(for: .snack) == 0.05)
    }

    @Test func targetsScaleDailyPerSlot() {
        let dinner = MealAllocation.targets(for: .dinner, daily: daily)
        #expect(dinner == MacroTargets(calories: 650, proteinG: 45, carbsG: 70, fatG: 20))

        let postWorkout = MealAllocation.targets(for: .postWorkout, daily: daily)
        #expect(postWorkout == MacroTargets(calories: 520, proteinG: 36, carbsG: 56, fatG: 16))

        let snack = MealAllocation.targets(for: .snack, daily: daily)
        #expect(snack == MacroTargets(calories: 130, proteinG: 9, carbsG: 14, fatG: 4))
    }

    @Test func emptySlotConsumedEqualsFullShare() {
        let remaining = MealAllocation.remaining(for: .dinner, daily: daily, slotConsumed: [])
        #expect(remaining == RemainingMacros(calories: 650, proteinG: 45, carbsG: 70, fatG: 20))
    }

    @Test func remainingSubtractsSlotConsumed() {
        let remaining = MealAllocation.remaining(
            for: .dinner,
            daily: daily,
            slotConsumed: [
                (calories: 250, proteinG: 20, carbsG: 30, fatG: 5),
                (calories: 150, proteinG: 10, carbsG: 10, fatG: 5),
            ]
        )
        #expect(remaining == RemainingMacros(calories: 250, proteinG: 15, carbsG: 30, fatG: 10))
    }

    @Test func remainingClampsAtZeroWhenSlotOvereaten() {
        let remaining = MealAllocation.remaining(
            for: .snack,
            daily: daily,
            slotConsumed: [(calories: 900, proteinG: 60, carbsG: 100, fatG: 40)]
        )
        #expect(remaining == RemainingMacros(calories: 0, proteinG: 0, carbsG: 0, fatG: 0))
    }

    @Test func slotHitThreshold() {
        #expect(MealAllocation.isSlotHit(RemainingMacros(calories: 99, proteinG: 10, carbsG: 10, fatG: 5)))
        #expect(!MealAllocation.isSlotHit(RemainingMacros(calories: 100, proteinG: 10, carbsG: 10, fatG: 5)))
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

// MARK: - Enrichment

private func makeItem(name: String, caloriesPer100g: Double = 120, proteinPer100g: Double = 22) -> FoodItem {
    FoodItem(
        id: "off-\(name)",
        name: name,
        brand: nil,
        caloriesPer100g: caloriesPer100g,
        proteinPer100g: proteinPer100g,
        carbsPer100g: 1,
        fatPer100g: 3,
        fibrePer100g: 0,
        sugarPer100g: 0,
        sodiumMgPer100g: 0,
        defaultServingGrams: 100
    )
}

private actor CallCounter {
    private(set) var count = 0
    func increment() -> Int {
        count += 1
        return count
    }
}

struct EnrichedFoodTests {
    @Test func initCopiesTheSuggestedFood() {
        let suggested = SuggestedFood(name: "brown rice", grams: 150, unit: "g")
        let food = EnrichedFood(from: suggested)

        #expect(food.id == suggested.id)
        #expect(food.suggestedName == "brown rice")
        #expect(food.originalGrams == 150)
        #expect(food.editedGrams == 150)
        #expect(food.isRemoved == false)
        #expect(food.isLoading == true)
        #expect(food.isApproximate == true)
    }

    @Test func displayNamePrefersTheRealItem() {
        var food = EnrichedFood(from: SuggestedFood(name: "chicken breast", grams: 200, unit: "g"))
        #expect(food.displayName == "Chicken Breast")

        food.realFoodItem = makeItem(name: "Poulet Fermier")
        #expect(food.displayName == "Poulet Fermier")
    }

    /// The "displayed == logged" contract: a food's nutrition and its
    /// logged draft must agree exactly, on both the real and estimate path.
    @Test func nutritionMatchesLoggedDraftOnBothPaths() {
        var real = EnrichedFood(from: SuggestedFood(name: "chicken breast", grams: 180, unit: "g"))
        real.realFoodItem = makeItem(name: "Chicken Breast")
        var estimate = EnrichedFood(from: SuggestedFood(name: "mystery stew", grams: 130, unit: "g"))
        estimate.editedGrams = 170

        for food in [real, estimate] {
            let n = food.nutrition
            let draft = SuggestedFoodsLogger.draft(for: food)
            #expect(draft.calories == n.calories)
            #expect(draft.proteinG == n.proteinG)
            #expect(draft.carbsG == n.carbsG)
            #expect(draft.fatG == n.fatG)
            #expect(draft.servingGrams == food.editedGrams)
            #expect(draft.isEstimated == food.isApproximate)
        }
    }
}

@MainActor
struct MealSuggestionEnrichmentTests {
    private func makeDefaults() -> UserDefaults {
        let suiteName = "MealSuggestionEnrichmentTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    /// A view model with a same-day cached suggestion already loaded, so
    /// enrich() has something to work on without any fetch.
    private func loadedViewModel(
        foods: [SuggestedFood] = [SuggestedFood(name: "chicken breast", grams: 200, unit: "g")],
        search: @escaping @Sendable (String) async throws -> [FoodItem]
    ) -> MealSuggestionViewModel {
        let defaults = makeDefaults()
        let suggestion = makeSuggestion(foods: foods)
        defaults.set(
            MealSuggestionViewModel.dayKey(for: .now, calendar: .current),
            forKey: "vora.mealSuggestion.date"
        )
        defaults.set(try? JSONEncoder().encode(suggestion), forKey: "vora.mealSuggestion.payload")

        let viewModel = MealSuggestionViewModel(
            defaults: defaults,
            search: search,
            enrichmentStagger: .zero
        )
        viewModel.loadCached()
        return viewModel
    }

    @Test func enrichSeedsPlaceholdersImmediately() {
        let viewModel = loadedViewModel(search: { _ in [] })
        viewModel.enrich()

        #expect(viewModel.enrichedFoods.count == 1)
        #expect(viewModel.enrichedFoods.allSatisfy { $0.isLoading })
        #expect(viewModel.isEnriching)
        viewModel.cancelEnrichment()
    }

    @Test func enrichWithoutLoadedSuggestionIsANoOp() {
        let viewModel = MealSuggestionViewModel(
            defaults: makeDefaults(),
            search: { _ in
                Issue.record("enrich must not search without a suggestion")
                return []
            },
            enrichmentStagger: .zero
        )
        viewModel.enrich()
        #expect(viewModel.enrichedFoods.isEmpty)
        #expect(viewModel.enrichmentTask == nil)
    }

    @Test func enrichResolvesRealItemsPerFood() async {
        let viewModel = loadedViewModel(
            foods: [
                SuggestedFood(name: "rice", grams: 100, unit: "g"),
                SuggestedFood(name: "chicken breast", grams: 200, unit: "g"),
            ],
            search: { name in [makeItem(name: name.capitalized)] }
        )
        viewModel.enrich()
        await viewModel.enrichmentTask?.value

        #expect(viewModel.enrichedFoods.count == 2)
        #expect(viewModel.enrichedFoods.allSatisfy { !$0.isLoading && !$0.isApproximate })
        #expect(viewModel.enrichedFoods[0].realFoodItem?.name == "Rice")
        #expect(viewModel.enrichedFoods[1].realFoodItem?.name == "Chicken Breast")
        #expect(!viewModel.isEnriching)
    }

    @Test func searchFailureLeavesTheFoodApproximate() async {
        let viewModel = loadedViewModel(search: { _ in throw URLError(.notConnectedToInternet) })
        viewModel.enrich()
        await viewModel.enrichmentTask?.value

        let food = viewModel.enrichedFoods[0]
        #expect(food.isLoading == false)
        #expect(food.isApproximate == true)
    }

    @Test func emptyResultsLeaveTheFoodApproximate() async {
        let viewModel = loadedViewModel(search: { _ in [] })
        viewModel.enrich()
        await viewModel.enrichmentTask?.value

        let food = viewModel.enrichedFoods[0]
        #expect(food.isLoading == false)
        #expect(food.isApproximate == true)
    }

    @Test func duplicateNamesResolveIndependently() async {
        let counter = CallCounter()
        let viewModel = loadedViewModel(
            foods: [
                SuggestedFood(name: "rice", grams: 100, unit: "g"),
                SuggestedFood(name: "rice", grams: 50, unit: "g"),
            ],
            search: { name in
                _ = await counter.increment()
                return [makeItem(name: name.capitalized)]
            }
        )
        viewModel.enrich()
        await viewModel.enrichmentTask?.value

        #expect(await counter.count == 2)
        #expect(viewModel.enrichedFoods.allSatisfy { !$0.isLoading && !$0.isApproximate })
        #expect(viewModel.enrichedFoods[0].editedGrams == 100)
        #expect(viewModel.enrichedFoods[1].editedGrams == 50)
    }

    @Test func reEnrichCancelsTheInFlightRun() async {
        let counter = CallCounter()
        let (entered, enteredContinuation) = AsyncStream.makeStream(of: Void.self)
        let (release, releaseContinuation) = AsyncStream.makeStream(of: Void.self)
        let viewModel = loadedViewModel(search: { name in
            if await counter.increment() == 1 {
                // First run signals it's in flight, then blocks until the
                // test releases it (or the run is cancelled) and reports
                // "nothing found".
                enteredContinuation.yield()
                for await _ in release {}
                return []
            }
            return [makeItem(name: name.capitalized)]
        })

        viewModel.enrich()
        let firstRun = viewModel.enrichmentTask
        // Without this wait, enrich() below can cancel the first run before
        // its child ever searches — the second run's search would then be
        // call #1, block forever, and deadlock the await beneath it.
        var enteredIterator = entered.makeAsyncIterator()
        _ = await enteredIterator.next()
        viewModel.enrich()
        await viewModel.enrichmentTask?.value

        #expect(viewModel.enrichedFoods[0].realFoodItem != nil)

        releaseContinuation.finish()
        await firstRun?.value

        // The stale first run must not have overwritten the fresh result.
        #expect(viewModel.enrichedFoods[0].realFoodItem != nil)
        #expect(viewModel.enrichedFoods[0].isLoading == false)
    }

    @Test func cancelEnrichmentStopsUpdates() async {
        let (stream, continuation) = AsyncStream.makeStream(of: Void.self)
        let viewModel = loadedViewModel(search: { _ in
            for await _ in stream {}
            return [makeItem(name: "Late Result")]
        })

        viewModel.enrich()
        let run = viewModel.enrichmentTask
        viewModel.cancelEnrichment()
        continuation.finish()
        await run?.value

        #expect(viewModel.enrichedFoods.allSatisfy { $0.isLoading })
        #expect(viewModel.enrichmentTask == nil)
    }

    @Test func adjustGramsClampsAtTheMinimum() async {
        let viewModel = loadedViewModel(search: { _ in [] })
        viewModel.enrich()
        await viewModel.enrichmentTask?.value
        let id = viewModel.enrichedFoods[0].id

        viewModel.adjustGrams(id: id, by: 10)
        #expect(viewModel.enrichedFoods[0].editedGrams == 210)

        viewModel.adjustGrams(id: id, by: -1000)
        #expect(viewModel.enrichedFoods[0].editedGrams == 10)
    }

    @Test func removeFoodFlagsWithoutDeleting() async {
        let viewModel = loadedViewModel(
            foods: [
                SuggestedFood(name: "rice", grams: 100, unit: "g"),
                SuggestedFood(name: "beans", grams: 80, unit: "g"),
            ],
            search: { _ in [] }
        )
        viewModel.enrich()
        await viewModel.enrichmentTask?.value

        viewModel.removeFood(id: viewModel.enrichedFoods[0].id)
        #expect(viewModel.enrichedFoods.count == 2)
        #expect(viewModel.activeFoods.count == 1)
        #expect(viewModel.activeFoods[0].suggestedName == "beans")
    }

    @Test func hasEditsDetectsGramsAndRemovalAndReverts() async {
        let viewModel = loadedViewModel(search: { _ in [] })
        viewModel.enrich()
        await viewModel.enrichmentTask?.value
        let id = viewModel.enrichedFoods[0].id
        #expect(viewModel.hasEdits == false)

        viewModel.adjustGrams(id: id, by: 10)
        #expect(viewModel.hasEdits == true)

        viewModel.adjustGrams(id: id, by: -10)
        #expect(viewModel.hasEdits == false)

        viewModel.removeFood(id: id)
        #expect(viewModel.hasEdits == true)
    }

    @Test func mealTotalsSumOnlyActiveFoods() async {
        let viewModel = loadedViewModel(
            foods: [
                SuggestedFood(name: "rice", grams: 100, unit: "g"),
                SuggestedFood(name: "chicken breast", grams: 100, unit: "g"),
            ],
            search: { name in [makeItem(name: name.capitalized)] }
        )
        viewModel.enrich()
        await viewModel.enrichmentTask?.value

        // Both items resolve to 120 kcal / 22 g protein at 100 g.
        #expect(viewModel.mealTotals.calories == 240)
        #expect(viewModel.mealTotals.proteinG == 44)

        viewModel.removeFood(id: viewModel.enrichedFoods[0].id)
        #expect(viewModel.mealTotals.calories == 120)
        #expect(viewModel.mealTotals.proteinG == 22)
    }

    @Test func loadPathsNeverSearch() async {
        let defaults = makeDefaults()
        let viewModel = MealSuggestionViewModel(
            defaults: defaults,
            fetch: { _, _, _, _, _ in makeSuggestion(mealName: "Any") },
            search: { _ in
                Issue.record("load/loadCached must never trigger OpenFoodFacts lookups")
                return []
            },
            enrichmentStagger: .zero
        )
        await viewModel.load(
            remaining: RemainingMacros(calories: 700, proteinG: 50, carbsG: 70, fatG: 20),
            goal: .maintain
        )
        viewModel.loadCached()
        #expect(viewModel.enrichedFoods.isEmpty)
    }
}
