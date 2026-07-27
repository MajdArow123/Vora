//
//  MealSuggestionTests.swift
//  VoraTests
//
//  Created by Majd Arow on 2026-07-26.
//

import Foundation
import Testing
@testable import Vora

struct MealSuggestionParsingTests {
    @Test func mealNameAndDetailSplitOnFirstLine() {
        let suggestion = MealSuggestion(
            rawText: "Chicken & Rice Bowl\n200g chicken breast + 1 cup rice + salad",
            generatedAt: .now
        )
        #expect(suggestion.mealName == "Chicken & Rice Bowl")
        #expect(suggestion.detail == "200g chicken breast + 1 cup rice + salad")
    }

    @Test func singleLineHasEmptyDetail() {
        let suggestion = MealSuggestion(rawText: "Greek yogurt with berries", generatedAt: .now)
        #expect(suggestion.mealName == "Greek yogurt with berries")
        #expect(suggestion.detail.isEmpty)
    }

    @Test func mealNameStripsMarkdownAsterisksAndWhitespace() {
        let suggestion = MealSuggestion(
            rawText: "  **Salmon Plate**  \n150g salmon + potatoes",
            generatedAt: .now
        )
        #expect(suggestion.mealName == "Salmon Plate")
    }

    @Test func blankLinesBetweenNameAndDetailAreSkipped() {
        let suggestion = MealSuggestion(
            rawText: "Omelette\n\n3 eggs + spinach",
            generatedAt: .now
        )
        #expect(suggestion.mealName == "Omelette")
        #expect(suggestion.detail == "3 eggs + spinach")
    }

    // MARK: - firstFoodName

    @Test func firstFoodNameDropsQuantityWords() {
        let text = "Chicken Bowl\n200g chicken breast + 1 cup rice + salad"
        #expect(MealSuggestion.firstFoodName(in: text) == "chicken breast")
    }

    @Test func firstFoodNameDropsCupPrefix() {
        let text = "Snack\n1 cup Greek yogurt"
        #expect(MealSuggestion.firstFoodName(in: text) == "Greek yogurt")
    }

    @Test func firstFoodNameTruncatesAtComma() {
        let text = "Breakfast\n2 large eggs, scrambled"
        #expect(MealSuggestion.firstFoodName(in: text) == "eggs")
    }

    @Test func firstFoodNameFallsBackToMealNameLine() {
        #expect(MealSuggestion.firstFoodName(in: "Salmon fillet") == "Salmon fillet")
    }

    @Test func firstFoodNameEmptyTextReturnsNil() {
        #expect(MealSuggestion.firstFoodName(in: "") == nil)
        #expect(MealSuggestion.firstFoodName(in: "   \n  ") == nil)
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
}

struct MealSuggestionServiceTests {
    @Test func parseDateAcceptsISO8601WithAndWithoutFractionalSeconds() {
        #expect(MealSuggestionService.parseDate("2026-07-27T12:34:56Z") != nil)
        #expect(MealSuggestionService.parseDate("2026-07-27T12:34:56.789Z") != nil)
        #expect(MealSuggestionService.parseDate("not a date") == nil)
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

    private let remaining = RemainingMacros(calories: 700, proteinG: 50, carbsG: 70, fatG: 20)

    /// Stands in for the ProTracker endpoint: returns a parsed suggestion
    /// the way the live service does after decoding the backend response.
    private func backendMock(
        mealName: String,
        detail: String
    ) -> (RemainingMacros, GoalType, Int) async throws -> MealSuggestion {
        { _, _, _ in
            MealSuggestion(rawText: "\(mealName)\n\(detail)", generatedAt: .now)
        }
    }

    @Test func loadFetchesFromBackendAndCaches() async {
        let defaults = makeDefaults()
        let viewModel = MealSuggestionViewModel(
            defaults: defaults,
            fetch: backendMock(mealName: "Chicken Bowl", detail: "200g chicken + rice")
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
    }

    @Test func sameDayCacheSkipsFetch() async {
        let defaults = makeDefaults()
        let cached = MealSuggestion(rawText: "Cached Meal\n100g something", generatedAt: .now)
        defaults.set(
            MealSuggestionViewModel.dayKey(for: .now, calendar: .current),
            forKey: "vora.mealSuggestion.date"
        )
        defaults.set(try? JSONEncoder().encode(cached), forKey: "vora.mealSuggestion.payload")

        let viewModel = MealSuggestionViewModel(defaults: defaults) { _, _, _ in
            Issue.record("fetch should not run on a same-day cache hit")
            return MealSuggestion(rawText: "", generatedAt: .now)
        }
        await viewModel.load(remaining: remaining, goal: .fatLoss)
        #expect(viewModel.state == .loaded(cached))
    }

    @Test func forceRefreshBypassesCacheAndRewritesIt() async {
        let defaults = makeDefaults()
        let stale = MealSuggestion(rawText: "Stale Meal", generatedAt: .now)
        defaults.set(
            MealSuggestionViewModel.dayKey(for: .now, calendar: .current),
            forKey: "vora.mealSuggestion.date"
        )
        defaults.set(try? JSONEncoder().encode(stale), forKey: "vora.mealSuggestion.payload")

        let viewModel = MealSuggestionViewModel(
            defaults: defaults,
            fetch: backendMock(mealName: "Fresh Meal", detail: "150g tuna + crackers")
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

    @Test func fetchFailureShowsConnectionCopy() async {
        let defaults = makeDefaults()
        let viewModel = MealSuggestionViewModel(defaults: defaults) { _, _, _ in
            throw URLError(.notConnectedToInternet)
        }
        await viewModel.load(remaining: remaining, goal: .maintain)
        #expect(viewModel.state == MealSuggestionViewModel.SuggestionState.failed("Couldn't generate suggestion. Check your connection."))
    }

    @Test func backendErrorShowsConnectionCopy() async {
        let defaults = makeDefaults()
        let viewModel = MealSuggestionViewModel(defaults: defaults) { _, _, _ in
            throw MealSuggestionError.badResponse
        }
        await viewModel.load(remaining: remaining, goal: .maintain)
        #expect(viewModel.state == MealSuggestionViewModel.SuggestionState.failed("Couldn't generate suggestion. Check your connection."))
    }
}
