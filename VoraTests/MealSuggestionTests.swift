//
//  MealSuggestionTests.swift
//  VoraTests
//
//  Created by Majd Arow on 2026-07-26.
//

import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import Vora

private func writeCache(_ suggestions: [String: MealSuggestion], to defaults: UserDefaults) throws {
    defaults.set(
        MealSuggestionViewModel.dayKey(for: .now, calendar: .current),
        forKey: MealSuggestionViewModel.cacheDateKey
    )
    defaults.set(try JSONEncoder().encode(suggestions), forKey: MealSuggestionViewModel.cachePayloadKey)
}

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

    @Test func aStatedStateDecodesAndAnUnknownOneIsIgnored() throws {
        func decode(_ json: String) throws -> SuggestedFood {
            try JSONDecoder().decode(SuggestedFood.self, from: Data(json.utf8))
        }
        #expect(try decode(#"{"name":"rice","grams":80,"unit":"g","state":"dry"}"#).state == .dry)
        #expect(try decode(#"{"name":"rice","grams":80,"unit":"g","state":"parboiled"}"#).state == nil)
        #expect(try decode(#"{"name":"rice","grams":80,"unit":"g"}"#).state == nil)
    }

    @Test func aStateSurvivesTheCache() throws {
        let food = SuggestedFood(name: "rice", grams: 80, unit: "g", state: .dry)
        let decoded = try JSONDecoder().decode(SuggestedFood.self, from: try JSONEncoder().encode(food))
        #expect(decoded == food)
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
        #expect(MealAllocation.share(for: .postWorkout) == 0.15)
        #expect(MealAllocation.share(for: .lunch) == 0.25)
        #expect(MealAllocation.share(for: .dinner) == 0.25)
        #expect(MealAllocation.share(for: .snack) == 0.10)
    }

    @Test func targetsScaleDailyPerSlot() {
        let dinner = MealAllocation.targets(for: .dinner, daily: daily)
        #expect(dinner == MacroTargets(calories: 650, proteinG: 45, carbsG: 70, fatG: 20))

        let postWorkout = MealAllocation.targets(for: .postWorkout, daily: daily)
        #expect(postWorkout == MacroTargets(calories: 390, proteinG: 27, carbsG: 42, fatG: 12))

        let snack = MealAllocation.targets(for: .snack, daily: daily)
        #expect(snack == MacroTargets(calories: 260, proteinG: 18, carbsG: 28, fatG: 8))
    }

    private func remaining(
        for slot: MealSlot = .dinner,
        slot slotConsumed: [MealAllocation.Consumed] = [],
        day dayConsumed: [MealAllocation.Consumed]? = nil,
        isTrainingDay: Bool = true,
        hour: Int = 12
    ) -> RemainingMacros {
        MealAllocation.remaining(
            for: slot,
            daily: daily,
            slotConsumed: slotConsumed,
            dayConsumed: dayConsumed ?? slotConsumed,
            isTrainingDay: isTrainingDay,
            hour: hour
        )
    }

    @Test func emptySlotConsumedEqualsFullShare() {
        #expect(remaining() == RemainingMacros(calories: 650, proteinG: 45, carbsG: 70, fatG: 20))
    }

    @Test func remainingSubtractsSlotConsumed() {
        let result = remaining(slot: [
            (calories: 250, proteinG: 20, carbsG: 30, fatG: 5),
            (calories: 150, proteinG: 10, carbsG: 10, fatG: 5),
        ])
        #expect(result == RemainingMacros(calories: 250, proteinG: 15, carbsG: 30, fatG: 10))
    }

    @Test func remainingClampsAtZeroWhenSlotOvereaten() {
        let result = remaining(for: .snack, slot: [(calories: 900, proteinG: 60, carbsG: 100, fatG: 40)])
        #expect(result == RemainingMacros(calories: 0, proteinG: 0, carbsG: 0, fatG: 0))
    }

    // MARK: - The day caps the meal

    @Test func aMealNeverAsksForMoreThanTheDayHasLeft() {
        // 2,350 of 2,600 eaten elsewhere: dinner's 650 would end 400 over.
        let result = remaining(day: [(calories: 2350, proteinG: 170, carbsG: 250, fatG: 75)])
        #expect(result == RemainingMacros(calories: 250, proteinG: 10, carbsG: 30, fatG: 5))
    }

    @Test func aDayAlreadyOverLeavesNothing() {
        let result = remaining(day: [(calories: 3000, proteinG: 200, carbsG: 300, fatG: 100)])
        #expect(result == RemainingMacros(calories: 0, proteinG: 0, carbsG: 0, fatG: 0))
    }

    // MARK: - Rest days

    @Test func withoutTrainingThePostWorkoutShareGoesToTheOtherMeals() {
        let total = MealSlot.allCases
            .filter { $0 != .postWorkout }
            .reduce(0) { $0 + MealAllocation.share(for: $1, isTrainingDay: false) }
        #expect(abs(total - 1.0) < 0.0001)
        #expect(remaining(isTrainingDay: false).calories == Int((2600 * 0.25 / 0.85).rounded()))
    }

    @Test func choosingPostWorkoutOnARestDayKeepsItsShare() {
        #expect(MealAllocation.share(for: .postWorkout, isTrainingDay: false) == 0.15)
    }

    @Test func aSnackIsWorthSuggestingOnALowTarget() {
        let low = MacroTargets(calories: 1200, proteinG: 90, carbsG: 120, fatG: 40)
        let result = MealAllocation.remaining(for: .snack, daily: low, slotConsumed: [], dayConsumed: [], isTrainingDay: true, hour: 12)
        #expect(!MealAllocation.isSlotHit(result))
    }

    // MARK: - Closing the day

    @Test(arguments: [MealSlot.dinner, .snack])
    func theEveningsMealsCanCloseABiggerGap(slot: MealSlot) {
        #expect(remaining(for: slot, hour: 18) == RemainingMacros(calories: 1040, proteinG: 72, carbsG: 112, fatG: 32))
    }

    @Test func beforeTheEveningMealsKeepTheirShare() {
        #expect(remaining(for: .snack, hour: 17).calories == 260)
        #expect(remaining(for: .dinner, hour: 17).calories == 650)
    }

    @Test func aLunchChosenInTheEveningKeepsItsShare() {
        #expect(remaining(for: .lunch, hour: 20).calories == 650)
    }

    @Test func aClosingMealStillStopsAtWhatsLeft() {
        let result = remaining(for: .snack, day: [(calories: 2000, proteinG: 125, carbsG: 200, fatG: 60)], hour: 22)
        #expect(result == RemainingMacros(calories: 600, proteinG: 55, carbsG: 80, fatG: 20))
    }

    @Test func theProteinTipsGapFitsTheEveningBudget() {
        // The tip fires above 40 g left after 6 pm; 55 g left must all be asked for.
        let result = remaining(for: .snack, day: [(calories: 1500, proteinG: 125, carbsG: 150, fatG: 40)], hour: 21)
        #expect(result.proteinG == 55)
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

    @Test func aLoggedMealMovesOnToTheNextOne() {
        #expect(MealSuggestionContext.mealType(hour: 9, hasTrainedToday: false, loggedSlots: [.breakfast]) == .lunch)
        #expect(MealSuggestionContext.mealType(hour: 12, hasTrainedToday: false, loggedSlots: [.lunch]) == .snack)
        #expect(MealSuggestionContext.mealType(hour: 18, hasTrainedToday: false, loggedSlots: [.dinner]) == .snack)
        #expect(MealSuggestionContext.mealType(hour: 15, hasTrainedToday: false, loggedSlots: [.lunch, .snack]) == .dinner)
    }

    @Test func trainingInTheAfternoonOffersAPostWorkoutMeal() {
        #expect(MealSuggestionContext.mealType(hour: 15, hasTrainedToday: true, loggedSlots: [.lunch]) == .postWorkout)
        #expect(MealSuggestionContext.mealType(hour: 15, hasTrainedToday: true, loggedSlots: [.lunch, .postWorkout]) == .snack)
        #expect(MealSuggestionContext.mealType(hour: 9, hasTrainedToday: true, loggedSlots: [.breakfast]) == .postWorkout)
    }

    @Test func withEverythingLoggedItStaysOnTheLastOption() {
        #expect(MealSuggestionContext.mealType(hour: 22, hasTrainedToday: false, loggedSlots: [.snack]) == .snack)
        #expect(MealSuggestionContext.mealType(hour: 18, hasTrainedToday: false, loggedSlots: [.dinner, .snack]) == .snack)
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

    private static let macros = RemainingMacros(calories: 625, proteinG: 40, carbsG: 70, fatG: 18)
    private static let url = URL(fileURLWithPath: "/stub")

    private func service(status: Int, body: String) -> MealSuggestionService {
        MealSuggestionService(token: "test-token") { _ in
            (Data(body.utf8), try #require(HTTPURLResponse(url: Self.url, statusCode: status, httpVersion: nil, headerFields: nil)))
        }
    }

    private func fetchError(_ service: MealSuggestionService) async -> MealSuggestionError? {
        do {
            _ = try await service.fetchSuggestion(remaining: Self.macros, goal: .fatLoss, hour: 19)
            return nil
        } catch {
            return error as? MealSuggestionError
        }
    }

    @Test func aGoodResponseBecomesASuggestion() async throws {
        let body = #"{"mealName":" Bowl ","mealType":"dinner","description":"d","foods":[{"name":"rice","grams":150,"unit":"g"}],"cookingTip":"t","generatedAt":"2026-07-27T12:34:56Z"}"#
        let suggestion = try await service(status: 200, body: body).fetchSuggestion(remaining: Self.macros, goal: .fatLoss, hour: 19)
        #expect(suggestion.mealName == "Bowl")
        #expect(suggestion.foods.count == 1)
    }

    @Test func theRequestCarriesTheMealsNumbers() async throws {
        var sent: URLRequest?
        let service = MealSuggestionService(token: "test-token") { request in
            sent = request
            return (Data(), try #require(HTTPURLResponse(url: Self.url, statusCode: 500, httpVersion: nil, headerFields: nil)))
        }
        await #expect(throws: MealSuggestionError.unavailable) {
            _ = try await service.fetchSuggestion(remaining: Self.macros, goal: .fatLoss, hour: 19, mealType: .postWorkout, userPreference: "Fish")
        }
        let body = try #require(sent?.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(sent?.httpMethod == "POST")
        #expect(sent?.value(forHTTPHeaderField: "X-App-Token") == "test-token")
        #expect(json["caloriesRemaining"] as? Int == 625)
        #expect(json["goalType"] as? String == "fatLoss")
        #expect(json["mealType"] as? String == "postWorkout")
        #expect(json["timeOfDay"] as? String == "evening")
        #expect(json["userPreference"] as? String == "Fish")
    }

    @Test(arguments: [401, 403, 404, 429, 500, 503])
    func aRefusalOrServerFailureIsUnavailable(status: Int) async {
        #expect(await fetchError(service(status: status, body: "{}")) == .unavailable)
    }

    @Test func aBadRequestOrUnreadableBodyIsABadResponse() async {
        #expect(await fetchError(service(status: 400, body: "{}")) == .badResponse)
        #expect(await fetchError(service(status: 200, body: "not json")) == .badResponse)
    }

    @Test func aMealWithoutFoodsIsEmpty() async {
        let body = #"{"mealName":"Bowl","mealType":"dinner","description":"","foods":[],"cookingTip":"","generatedAt":""}"#
        #expect(await fetchError(service(status: 200, body: body)) == .emptyContent)
    }

    @Test func withoutATokenItSaysNotConfiguredAndSendsNothing() async {
        let service = MealSuggestionService(token: nil) { _ in
            Issue.record("must not send a request")
            throw URLError(.badURL)
        }
        #expect(await fetchError(service) == .notConfigured)
        #expect(MealSuggestionError.notConfigured.errorDescription?.contains("configured") == true)
    }

    @Test func theTokenComesFromInfoPlistOnlyWhenSet() {
        func token(_ value: Any?) -> String? {
            MealSuggestionService.configuredToken(in: value.map { ["MealSuggestionAppToken": $0] } ?? [:])
        }
        #expect(token("abc123") == "abc123")
        #expect(token(" abc123\n") == "abc123")
        #expect(token(nil) == nil)
        #expect(token("") == nil)
        #expect(token("   ") == nil)
        #expect(token("$(VORA_MEAL_SUGGESTION_TOKEN)") == nil)
        #expect(MealSuggestionService.configuredToken(in: nil) == nil)
    }

    @Test func nothingLeftToEatNeverReachesTheBackend() async {
        let service = MealSuggestionService(token: "test-token") { _ in
            Issue.record("must not send a request")
            throw URLError(.badURL)
        }
        await #expect(throws: MealSuggestionError.badResponse) {
            _ = try await service.fetchSuggestion(remaining: RemainingMacros(calories: 0, proteinG: 0, carbsG: 0, fatG: 0), goal: .fatLoss, hour: 19)
        }
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

    private func cache(_ suggestion: MealSuggestion, for mealType: MealSlot? = nil, in defaults: UserDefaults) throws {
        try writeCache([MealSuggestionViewModel.cacheKey(for: mealType): suggestion], to: defaults)
    }

    private func stored(_ mealType: MealSlot? = nil, in defaults: UserDefaults) throws -> MealSuggestion? {
        let data = try #require(defaults.data(forKey: MealSuggestionViewModel.cachePayloadKey))
        return try JSONDecoder().decode([String: MealSuggestion].self, from: data)[MealSuggestionViewModel.cacheKey(for: mealType)]
    }

    private let remaining = RemainingMacros(calories: 700, proteinG: 50, carbsG: 70, fatG: 20)

    /// Stands in for the ProTracker endpoint: returns a structured
    /// suggestion the way the live service does after decoding.
    private func backendMock(
        mealName: String
    ) -> (RemainingMacros, GoalType, Int, MealSlot?, String?) async throws -> MealSuggestion {
        { _, _, _, _, _ in makeSuggestion(mealName: mealName) }
    }

    @Test func loadFetchesFromBackendAndCaches() async throws {
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

        let stored = try stored(in: defaults)
        #expect(stored?.mealName == "Chicken Bowl")
        #expect(stored?.foods.count == 1)
    }

    @Test func sameDayCacheSkipsFetch() async throws {
        let defaults = makeDefaults()
        let cached = makeSuggestion(mealName: "Cached Meal")
        try cache(cached, in: defaults)

        let viewModel = MealSuggestionViewModel(defaults: defaults) { _, _, _, _, _ in
            Issue.record("fetch should not run on a same-day cache hit")
            return makeSuggestion(mealName: "Wrong")
        }
        await viewModel.load(remaining: remaining, goal: .fatLoss)
        #expect(viewModel.state == .loaded(cached))
    }

    @Test func forceRefreshBypassesCacheAndRewritesIt() async throws {
        let defaults = makeDefaults()
        try cache(makeSuggestion(mealName: "Stale Meal"), in: defaults)

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

        #expect(try stored(in: defaults)?.mealName == "Fresh Meal")
    }

    @Test func oldCacheFormatFallsThroughToFetchAndIsRemoved() async throws {
        let defaults = makeDefaults()
        defaults.set(
            MealSuggestionViewModel.dayKey(for: .now, calendar: .current),
            forKey: MealSuggestionViewModel.cacheDateKey
        )
        defaults.set(
            try JSONEncoder().encode(makeSuggestion(mealName: "Old Format")),
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
        #expect(defaults.data(forKey: "vora.mealSuggestion.payload") == nil)
    }

    @Test func anUnreadableCacheFallsThroughToFetch() async {
        let defaults = makeDefaults()
        defaults.set(
            MealSuggestionViewModel.dayKey(for: .now, calendar: .current),
            forKey: MealSuggestionViewModel.cacheDateKey
        )
        defaults.set(Data("not json".utf8), forKey: MealSuggestionViewModel.cachePayloadKey)
        let viewModel = MealSuggestionViewModel(defaults: defaults, fetch: backendMock(mealName: "Fresh"))
        await viewModel.load(remaining: remaining, goal: .maintain)
        guard case .loaded(let suggestion) = viewModel.state else {
            Issue.record("expected loaded state, got \(viewModel.state)")
            return
        }
        #expect(suggestion.mealName == "Fresh")
    }

    // MARK: - One suggestion per meal

    @Test func eachMealKeepsItsOwnSuggestion() async throws {
        let defaults = makeDefaults()
        let lunch = makeSuggestion(mealName: "Lunch Bowl", mealType: "lunch")
        try cache(lunch, for: .lunch, in: defaults)

        var fetched: [MealSlot?] = []
        let viewModel = MealSuggestionViewModel(defaults: defaults) { _, _, _, mealType, _ in
            fetched.append(mealType)
            return makeSuggestion(mealName: "Dinner Bowl", mealType: "dinner")
        }
        // Dinner mustn't be handed the lunch from earlier today.
        await viewModel.load(remaining: remaining, goal: .maintain, mealType: .dinner)
        #expect(fetched == [.dinner])
        #expect(try stored(.dinner, in: defaults)?.mealName == "Dinner Bowl")

        await viewModel.load(remaining: remaining, goal: .maintain, mealType: .lunch)
        #expect(viewModel.state == .loaded(lunch))
        #expect(fetched == [.dinner])
    }

    @Test func switchingToAMealWithNoSuggestionClearsTheScreen() async throws {
        let defaults = makeDefaults()
        try cache(makeSuggestion(mealName: "Lunch Bowl"), for: .lunch, in: defaults)
        let viewModel = MealSuggestionViewModel(
            defaults: defaults,
            search: { _ in [] },
            enrichmentStagger: .zero,
            enrichmentRetryDelay: .zero
        )
        viewModel.loadCached(mealType: .lunch)
        viewModel.enrich()
        await viewModel.enrichmentTask?.value
        #expect(!viewModel.enrichedFoods.isEmpty)

        viewModel.loadCached(mealType: .dinner)
        #expect(viewModel.state == .idle)
        #expect(viewModel.enrichedFoods.isEmpty)
    }

    @Test func aLoggedMealIsntOfferedAgain() async throws {
        let defaults = makeDefaults()
        try cache(makeSuggestion(mealName: "Dinner"), for: .dinner, in: defaults)
        try cache(makeSuggestion(mealName: "Lunch"), for: .lunch, in: defaults)
        let viewModel = MealSuggestionViewModel(defaults: defaults) { _, _, _, _, _ in makeSuggestion() }
        viewModel.clearCached(mealType: .dinner)
        viewModel.loadCached(mealType: .dinner)
        #expect(viewModel.state == .idle)
    }

    @Test func anotherDaysSuggestionStaysOnItsDay() async throws {
        let defaults = makeDefaults()
        let tomorrow = try #require(Calendar.current.date(byAdding: .day, value: 1, to: .now))
        let viewModel = MealSuggestionViewModel(defaults: defaults) { _, _, _, _, _ in makeSuggestion(mealName: "Tomorrow") }
        await viewModel.load(remaining: remaining, goal: .maintain, mealType: .lunch, force: true, now: tomorrow)
        viewModel.loadCached(mealType: .lunch)
        #expect(viewModel.state == .idle)
    }

    @Test func aSlowOlderLoadCantReplaceANewerOne() async throws {
        let (gate, open) = AsyncStream.makeStream(of: Void.self)
        var calls = 0
        let defaults = makeDefaults()
        let viewModel = MealSuggestionViewModel(defaults: defaults) { _, _, _, mealType, _ in
            calls += 1
            if calls == 1 {
                for await _ in gate {}
                return makeSuggestion(mealName: "Old")
            }
            return makeSuggestion(mealName: "New")
        }
        let older = Task { await viewModel.load(remaining: remaining, goal: .maintain, mealType: .lunch) }
        while calls == 0 { await Task.yield() }
        await viewModel.load(remaining: remaining, goal: .maintain, mealType: .dinner)
        open.finish()
        await older.value

        guard case .loaded(let suggestion) = viewModel.state else {
            Issue.record("expected loaded state, got \(viewModel.state)")
            return
        }
        #expect(suggestion.mealName == "New")
        // The older result is still good for its own meal.
        #expect(try stored(.lunch, in: defaults)?.mealName == "Old")
    }

    @Test func aCancelledLoadPutsThingsBack() async throws {
        let defaults = makeDefaults()
        let viewModel = MealSuggestionViewModel(defaults: defaults) { _, _, _, _, _ in throw URLError(.cancelled) }
        await viewModel.load(remaining: remaining, goal: .maintain)
        #expect(viewModel.state == .idle)

        let cached = makeSuggestion(mealName: "Shown")
        try cache(cached, for: .lunch, in: defaults)
        viewModel.loadCached(mealType: .lunch)
        await viewModel.load(remaining: remaining, goal: .maintain, mealType: .lunch, force: true)
        #expect(viewModel.state == .loaded(cached))

        let task = MealSuggestionViewModel(defaults: defaults) { _, _, _, _, _ in throw CancellationError() }
        await task.load(remaining: remaining, goal: .maintain, mealType: .dinner)
        #expect(task.state == .idle)
    }

    @Test func loadCachedHitLoadsWithoutFetching() throws {
        let defaults = makeDefaults()
        let cached = makeSuggestion(mealName: "Cached Meal")
        try cache(cached, in: defaults)

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

    @Test(arguments: [MealSuggestionError.notConfigured, .unavailable, .badResponse, .emptyContent])
    func eachFailureSaysWhatHappened(error: MealSuggestionError) async throws {
        let viewModel = MealSuggestionViewModel(defaults: makeDefaults()) { _, _, _, _, _ in throw error }
        await viewModel.load(remaining: remaining, goal: .maintain)
        #expect(viewModel.state == .failed(try #require(error.errorDescription)))
    }

    @Test func aRefusalDoesntBlameTheConnection() {
        #expect(MealSuggestionError.message(for: MealSuggestionError.unavailable) != MealSuggestionError.connectionMessage)
        #expect(MealSuggestionError.message(for: URLError(.timedOut)) == MealSuggestionError.connectionMessage)
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
    ) throws -> MealSuggestionViewModel {
        let defaults = makeDefaults()
        try writeCache([MealSuggestionViewModel.cacheKey(for: nil): makeSuggestion(foods: foods)], to: defaults)

        let viewModel = MealSuggestionViewModel(
            defaults: defaults,
            search: search,
            enrichmentStagger: .zero,
            enrichmentRetryDelay: .zero
        )
        viewModel.loadCached()
        return viewModel
    }

    @Test func enrichSeedsPlaceholdersImmediately() throws {
        let viewModel = try loadedViewModel(search: { _ in [] })
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

    @Test func enrichResolvesRealItemsPerFood() async throws {
        let viewModel = try loadedViewModel(
            foods: [
                SuggestedFood(name: "rice", grams: 100, unit: "g"),
                SuggestedFood(name: "chicken breast", grams: 200, unit: "g"),
            ],
            search: { name in [await makeItem(name: name.capitalized)] }
        )
        viewModel.enrich()
        await viewModel.enrichmentTask?.value

        #expect(viewModel.enrichedFoods.count == 2)
        #expect(viewModel.enrichedFoods.allSatisfy { !$0.isLoading && !$0.isApproximate })
        #expect(viewModel.enrichedFoods[0].realFoodItem?.name == "Rice")
        #expect(viewModel.enrichedFoods[1].realFoodItem?.name == "Chicken Breast")
        #expect(!viewModel.isEnriching)
    }

    @Test func searchFailureLeavesTheFoodApproximate() async throws {
        let viewModel = try loadedViewModel(search: { _ in throw URLError(.notConnectedToInternet) })
        viewModel.enrich()
        await viewModel.enrichmentTask?.value

        let food = viewModel.enrichedFoods[0]
        #expect(food.isLoading == false)
        #expect(food.isApproximate == true)
    }

    @Test func aFailedSearchIsTriedOnceMore() async throws {
        let counter = CallCounter()
        let viewModel = try loadedViewModel(search: { name in
            if await counter.increment() == 1 { throw OpenFoodFactsError.badResponse }
            return [await makeItem(name: name.capitalized)]
        })
        viewModel.enrich()
        await viewModel.enrichmentTask?.value
        #expect(await counter.count == 2)
        #expect(viewModel.enrichedFoods[0].isApproximate == false)
    }

    @Test func aDryProductFallsBackToACookedEstimate() async throws {
        let viewModel = try loadedViewModel(
            foods: [SuggestedFood(name: "basmati rice", grams: 100, unit: "g")],
            search: { _ in
                [FoodItem(
                    id: "dry", name: "Basmati Rice", brand: nil,
                    caloriesPer100g: 351, proteinPer100g: 9, carbsPer100g: 77, fatPer100g: 1,
                    fibrePer100g: 0, sugarPer100g: 0, sodiumMgPer100g: 0, defaultServingGrams: 100
                )]
            }
        )
        viewModel.enrich()
        await viewModel.enrichmentTask?.value

        let food = viewModel.enrichedFoods[0]
        #expect(food.realFoodItem == nil)
        #expect(food.displayName == "Basmati Rice, cooked")
        #expect(food.nutrition.calories < 150)
    }

    @Test func aSuggestionSayingDryKeepsTheDryProduct() async throws {
        let viewModel = try loadedViewModel(
            foods: [SuggestedFood(name: "basmati rice", grams: 100, unit: "g", state: .dry)],
            search: { _ in
                [FoodItem(
                    id: "dry", name: "Basmati Rice", brand: nil,
                    caloriesPer100g: 351, proteinPer100g: 9, carbsPer100g: 77, fatPer100g: 1,
                    fibrePer100g: 0, sugarPer100g: 0, sodiumMgPer100g: 0, defaultServingGrams: 100
                )]
            }
        )
        viewModel.enrich()
        await viewModel.enrichmentTask?.value

        let food = viewModel.enrichedFoods[0]
        #expect(food.realFoodItem != nil)
        #expect(food.displayName == "Basmati Rice, dry")
        #expect(SuggestedFoodsLogger.draft(for: food).foodName == "Basmati Rice, dry")
    }

    @Test func anUnrelatedFirstResultIsPassedOver() async throws {
        let viewModel = try loadedViewModel(
            foods: [SuggestedFood(name: "broccoli", grams: 100, unit: "g")],
            search: { _ in
                [await makeItem(name: "Marinated Tomato, Broccoli & Spinach Vegan Quiche"),
                 await makeItem(name: "Broccoli Florets")]
            }
        )
        viewModel.enrich()
        await viewModel.enrichmentTask?.value
        #expect(viewModel.enrichedFoods[0].realFoodItem?.name == "Broccoli Florets")
    }

    @Test func emptyResultsLeaveTheFoodApproximate() async throws {
        let viewModel = try loadedViewModel(search: { _ in [] })
        viewModel.enrich()
        await viewModel.enrichmentTask?.value

        let food = viewModel.enrichedFoods[0]
        #expect(food.isLoading == false)
        #expect(food.isApproximate == true)
    }

    @Test func duplicateNamesResolveIndependently() async throws {
        let counter = CallCounter()
        let viewModel = try loadedViewModel(
            foods: [
                SuggestedFood(name: "rice", grams: 100, unit: "g"),
                SuggestedFood(name: "rice", grams: 50, unit: "g"),
            ],
            search: { name in
                _ = await counter.increment()
                return [await makeItem(name: name.capitalized)]
            }
        )
        viewModel.enrich()
        await viewModel.enrichmentTask?.value

        #expect(await counter.count == 2)
        #expect(viewModel.enrichedFoods.allSatisfy { !$0.isLoading && !$0.isApproximate })
        #expect(viewModel.enrichedFoods[0].editedGrams == 100)
        #expect(viewModel.enrichedFoods[1].editedGrams == 50)
    }

    @Test func reEnrichCancelsTheInFlightRun() async throws {
        let counter = CallCounter()
        let (entered, enteredContinuation) = AsyncStream.makeStream(of: Void.self)
        let (release, releaseContinuation) = AsyncStream.makeStream(of: Void.self)
        let viewModel = try loadedViewModel(search: { name in
            if await counter.increment() == 1 {
                // First run signals it's in flight, then blocks until the
                // test releases it (or the run is cancelled) and reports
                // "nothing found".
                enteredContinuation.yield()
                for await _ in release {}
                return []
            }
            return [await makeItem(name: name.capitalized)]
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

    @Test func cancelEnrichmentStopsUpdates() async throws {
        let (stream, continuation) = AsyncStream.makeStream(of: Void.self)
        let viewModel = try loadedViewModel(search: { _ in
            for await _ in stream {}
            return [await makeItem(name: "Late Result")]
        })

        viewModel.enrich()
        let run = viewModel.enrichmentTask
        viewModel.cancelEnrichment()
        continuation.finish()
        await run?.value

        #expect(viewModel.enrichedFoods.allSatisfy { $0.isLoading })
        #expect(viewModel.enrichmentTask == nil)
    }

    @Test func adjustGramsClampsAtTheMinimum() async throws {
        let viewModel = try loadedViewModel(search: { _ in [] })
        viewModel.enrich()
        await viewModel.enrichmentTask?.value
        let id = viewModel.enrichedFoods[0].id

        viewModel.adjustGrams(id: id, by: 10)
        #expect(viewModel.enrichedFoods[0].editedGrams == 210)

        viewModel.adjustGrams(id: id, by: -1000)
        #expect(viewModel.enrichedFoods[0].editedGrams == 10)
    }

    @Test func removeFoodFlagsWithoutDeleting() async throws {
        let viewModel = try loadedViewModel(
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

    @Test func hasEditsDetectsGramsAndRemovalAndReverts() async throws {
        let viewModel = try loadedViewModel(search: { _ in [] })
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

    @Test func mealTotalsSumOnlyActiveFoods() async throws {
        let viewModel = try loadedViewModel(
            foods: [
                SuggestedFood(name: "rice", grams: 100, unit: "g"),
                SuggestedFood(name: "chicken breast", grams: 100, unit: "g"),
            ],
            search: { name in [await makeItem(name: name.capitalized)] }
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

struct FoodMatcherTests {
    private func item(_ name: String, kcal: Double = 119, protein: Double = 22, carbs: Double = 1, fat: Double = 3) -> FoodItem {
        FoodItem(
            id: name, name: name, brand: nil,
            caloriesPer100g: kcal, proteinPer100g: protein, carbsPer100g: carbs, fatPer100g: fat,
            fibrePer100g: 0, sugarPer100g: 0, sodiumMgPer100g: 0, defaultServingGrams: 100
        )
    }

    // MARK: - Cooked or dry

    private func grain(_ name: String, kcal: Double, protein: Double = 7, carbs: Double, fat: Double = 1) -> FoodItem {
        item(name, kcal: kcal, protein: protein, carbs: carbs, fat: fat)
    }

    @Test func aDryBasmatiCantBeLoggedForACookedWeight() {
        let product = grain("Rice Basmati", kcal: 351, carbs: 77)
        #expect(FoodMatcher.bestMatch(for: "basmati rice", state: .cooked, in: [product]) == nil)
        #expect(FoodMatcher.bestMatch(for: "basmati rice", state: .dry, in: [product]) != nil)
    }

    @Test func aCookedBasmatiCantBeLoggedForADryWeight() {
        let product = grain("Basmati Rice", kcal: 130, protein: 3, carbs: 28, fat: 0.3)
        #expect(FoodMatcher.bestMatch(for: "basmati rice", state: .cooked, in: [product]) != nil)
        #expect(FoodMatcher.bestMatch(for: "basmati rice", state: .dry, in: [product]) == nil)
    }

    @Test func dryPastaKeepsItsDryProduct() {
        let product = grain("Dry Pasta", kcal: 355, protein: 13, carbs: 72, fat: 1.5)
        let state = GenericFoods.state(for: "dry pasta", stated: nil)
        #expect(state == .dry)
        #expect(FoodMatcher.bestMatch(for: "dry pasta", state: state, in: [product]) != nil)
    }

    @Test func quinoaIsJudgedByItsState() {
        let dry = grain("Organic Quinoa", kcal: 368, protein: 14, carbs: 64, fat: 6)
        let cooked = grain("Quinoa", kcal: 120, protein: 4.4, carbs: 21, fat: 1.9)
        #expect(FoodMatcher.bestMatch(for: "quinoa", state: .cooked, in: [dry]) == nil)
        #expect(FoodMatcher.bestMatch(for: "quinoa", state: .cooked, in: [cooked]) != nil)
        #expect(FoodMatcher.bestMatch(for: "quinoa", state: .dry, in: [dry]) != nil)
        #expect(FoodMatcher.bestMatch(for: "quinoa", state: .dry, in: [cooked]) == nil)
    }

    @Test func theCalorieRatioHasBothEdges() {
        // Cooked rice is typically 125.5 kcal per 100 g.
        let typical = 125.5
        for (ratio, passes) in [(0.66, false), (0.68, true), (1.49, true), (1.51, false)] {
            #expect(GenericFoods.isPlausible(caloriesPer100g: typical * ratio, for: "rice", state: .cooked) == passes)
        }
    }

    @Test func otherFoodsArentJudgedByCalories() {
        #expect(GenericFoods.isPlausible(caloriesPer100g: 900, for: "chicken breast", state: nil))
    }

    @Test func theClosestNameWins() {
        let items = [item("Chicken Breast Fillets With Herbs"), item("Chicken Breast"), item("Chicken")]
        #expect(FoodMatcher.bestMatch(for: "chicken breast", in: items)?.name == "Chicken Breast")
    }

    @Test func aDishContainingTheFoodIsntTheFood() {
        let items = [item("Marinated Tomato, Broccoli & Spinach Vegan Quiche"), item("Pasta 'N' Sauce Cheese & Broccoli")]
        #expect(FoodMatcher.bestMatch(for: "broccoli", in: items) == nil)
    }

    @Test func coverageHasAThreshold() {
        // 2 of 4 words passes; 2 of 6 doesn't.
        #expect(FoodMatcher.bestMatch(for: "olive oil", in: [item("Extra Virgin Olive Oil")]) != nil)
        #expect(FoodMatcher.bestMatch(for: "olive oil", in: [item("Sun Dried Tomatoes In Olive Oil")]) == nil)
    }

    @Test func pluralsAndPunctuationDontMatter() {
        #expect(FoodMatcher.bestMatch(for: "eggs", in: [item("Large Egg")]) != nil)
        #expect(FoodMatcher.bestMatch(for: "olive oil", in: [item("Olive-Oil")]) != nil)
        #expect(FoodMatcher.words(in: "Hummus") == ["hummu"])
        #expect(FoodMatcher.words(in: "Rice") == ["rice"])
    }

    @Test func aDifferentLanguageOrFoodIsNoMatch() {
        #expect(FoodMatcher.bestMatch(for: "chicken breast", in: [item("Poulet Fermier")]) == nil)
        #expect(FoodMatcher.bestMatch(for: "  ", in: [item("Rice")]) == nil)
    }

    @Test func dataThatDoesntAddUpIsSkipped() {
        #expect(FoodMatcher.bestMatch(for: "rice", in: [item("Rice", kcal: 0, protein: 0, carbs: 0, fat: 0)]) == nil)
        // 28 g carbs can't be 900 kcal.
        #expect(FoodMatcher.bestMatch(for: "rice", in: [item("Rice", kcal: 900, protein: 3, carbs: 28, fat: 0)]) == nil)
        #expect(FoodMatcher.bestMatch(for: "rice", in: [item("Rice", kcal: 130, protein: 3, carbs: 28, fat: 0.3)]) != nil)
    }
}

struct GenericFoodsTests {
    @Test func broccoliIsntACalorieBomb() {
        let n = GenericFoods.nutrition(for: "broccoli", grams: 200)
        #expect(n.calories < 100)
    }

    @Test func oilIsAllFat() {
        let n = GenericFoods.nutrition(for: "olive oil", grams: 10)
        #expect(n.fatG == 10)
        #expect(n.calories == 90)
    }

    @Test func theLongestNameWins() {
        #expect(GenericFoods.macros(for: "sweet potato") != GenericFoods.macros(for: "potato"))
        #expect(GenericFoods.macros(for: "Grilled Chicken Breast") == GenericFoods.macros(for: "chicken breast"))
        #expect(GenericFoods.macros(for: "green beans") != GenericFoods.macros(for: "beans"))
        #expect(GenericFoods.macros(for: "peanut butter") != GenericFoods.macros(for: "butter"))
        #expect(GenericFoods.macros(for: "egg noodles") == GenericFoods.macros(for: "noodles"))
    }

    @Test func wholeWordsOnly() {
        // "ham" is not in "hamburger bun"; "nut" is not in "coconut".
        #expect(GenericFoods.macros(for: "shampoo") == GenericFoods.unknown)
        #expect(GenericFoods.macros(for: "coconut") == GenericFoods.unknown)
    }

    // MARK: - Cooked or dry

    @Test(arguments: ["rice", "basmati rice", "pasta", "whole wheat spaghetti", "egg noodles", "quinoa", "couscous"])
    func aGrainDefaultsToCookedAndSaysSo(name: String) {
        let food = EnrichedFood(from: SuggestedFood(name: name, grams: 100, unit: "g"))
        #expect(food.state == .cooked)
        #expect(food.displayName == name.capitalized + ", cooked")
    }

    @Test(arguments: ["rice", "pasta", "egg noodles", "quinoa", "couscous"])
    func aDryGrainSaysDryAndUsesDryValues(name: String) {
        let dry = EnrichedFood(from: SuggestedFood(name: name, grams: 100, unit: "g", state: .dry))
        let cooked = EnrichedFood(from: SuggestedFood(name: name, grams: 100, unit: "g"))
        #expect(dry.displayName == name.capitalized + ", dry")
        #expect(dry.nutrition.calories > cooked.nutrition.calories * 2)
    }

    @Test(arguments: [
        ("cooked rice", GrainState.cooked), ("boiled pasta", .cooked), ("steamed couscous", .cooked),
        ("dry pasta", .dry), ("uncooked rice", .dry), ("raw noodles", .dry), ("dried quinoa", .dry),
    ])
    func aNameStatingItsStateIsLeftAlone(name: String, state: GrainState) {
        let food = EnrichedFood(from: SuggestedFood(name: name, grams: 100, unit: "g"))
        #expect(food.state == state)
        #expect(food.displayName == name.capitalized)
    }

    @Test func aNameOutranksTheSuggestion() {
        #expect(GenericFoods.state(for: "dry pasta", stated: .cooked) == .dry)
        #expect(GenericFoods.state(for: "cooked rice", stated: .dry) == .cooked)
        #expect(GenericFoods.state(for: "pasta", stated: .dry) == .dry)
    }

    @Test(arguments: ["chicken breast", "broccoli", "mystery stew", "oats"])
    func otherFoodsHaveNoState(name: String) {
        let food = EnrichedFood(from: SuggestedFood(name: name, grams: 100, unit: "g", state: .dry))
        #expect(food.state == nil)
        #expect(food.displayName == name.capitalized)
    }

    @Test func anUnknownFoodGetsAModestAverage() {
        let n = GenericFoods.nutrition(for: "mystery stew", grams: 100)
        #expect(n.calories == 145)
    }

    @Test func caloriesFollowTheMacros() {
        let n = GenericFoods.nutrition(for: "rice", grams: 150)
        #expect(abs(n.calories - (n.proteinG * 4 + n.carbsG * 4 + n.fatG * 9)) < 0.001)
    }
}

@MainActor
struct SuggestedFoodsLoggingTests {
    private struct SaveFailure: Error {}

    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    init() throws {
        container = try PersistenceController.makeContainer(inMemory: true)
    }

    private var entries: [FoodEntry] {
        get throws { try context.fetch(FetchDescriptor<FoodEntry>()) }
    }

    private func draft(_ name: String) -> LoggedFoodDraft {
        var food = EnrichedFood(from: SuggestedFood(name: name, grams: 100, unit: "g"))
        food.isLoading = false
        return SuggestedFoodsLogger.draft(for: food)
    }

    @Test func foodsReachTheDiaryAndSlot() throws {
        let date = Date.now
        try SuggestedFoodsLogger.log([draft("rice"), draft("beans")], to: .dinner, on: date, context: context)
        let logged = try entries
        #expect(logged.count == 2)
        #expect(logged.allSatisfy { $0.mealSlot == .dinner && $0.date == date })
    }

    @Test func aFailedSaveLeavesNothingBehindAndThrows() throws {
        #expect(throws: SaveFailure.self) {
            try SuggestedFoodsLogger.log([draft("rice"), draft("beans")], to: .dinner, on: .now, context: context) { _ in
                throw SaveFailure()
            }
        }
        try context.save()
        #expect(try entries.isEmpty)
    }

    @Test func riceIsLoggedWithItsStateEitherWay() {
        #expect(draft("basmati rice").foodName == "Basmati Rice, cooked (estimated)")

        var real = EnrichedFood(from: SuggestedFood(name: "basmati rice", grams: 100, unit: "g"))
        real.realFoodItem = makeItem(name: "Basmati Rice")
        #expect(SuggestedFoodsLogger.draft(for: real).foodName == "Basmati Rice, cooked")
    }

    @Test func anEstimateSaysSoInTheDiary() {
        #expect(draft("broccoli").foodName == "Broccoli (estimated)")
        #expect(draft("broccoli").isEstimated)

        var real = EnrichedFood(from: SuggestedFood(name: "broccoli", grams: 100, unit: "g"))
        real.realFoodItem = makeItem(name: "Broccoli Florets")
        #expect(SuggestedFoodsLogger.draft(for: real).foodName == "Broccoli Florets")
    }
}

struct LoadingSpinnerTests {
    /// The Progress tab used to be called `ProgressView`, which replaced
    /// SwiftUI's spinner across the app: the suggestion sheet drew the whole
    /// Progress screen inside its button while loading.
    @MainActor
    @Test func progressViewIsSwiftUIsSpinner() {
        let spinner = ProgressView()
        #expect(type(of: spinner) == SwiftUI.ProgressView<EmptyView, EmptyView>.self)
    }
}
