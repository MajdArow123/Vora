//
//  FoodSearchViewModelTests.swift
//  VoraTests
//
//  Created by Majd Arow on 2026-07-21.
//

import Foundation
import SwiftData
import Testing
@testable import Vora

struct FoodSearchViewModelTests {
    // MARK: - Fixtures

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            UserProfile.self, FoodEntry.self, CustomFood.self,
            WorkoutSession.self, ExerciseLog.self, SetEntry.self,
            WeightEntry.self, WaterEntry.self, CardioEntry.self, SplitDay.self,
        ])
        return try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
    }

    /// A fixed anchor so relative seeding never depends on wall-clock time
    /// within a day.
    private var anchor: Date { Calendar.current.startOfDay(for: .now) }

    private func foodEntry(name: String, minutesAgo: Int, grams: Double = 100) -> FoodEntry {
        FoodEntry(
            date: anchor.addingTimeInterval(-Double(minutesAgo) * 60),
            mealSlot: .lunch,
            foodName: name,
            servingGrams: grams,
            calories: 200,
            proteinG: 10,
            carbsG: 20,
            fatG: 5
        )
    }

    private func isIdle(_ state: SearchState) -> Bool {
        if case .idle = state { return true }
        return false
    }

    private func isLoading(_ state: SearchState) -> Bool {
        if case .loading = state { return true }
        return false
    }

    // MARK: - Recents

    @Test func recentsDeduplicateCaseInsensitivelyKeepingNewest() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        context.insert(foodEntry(name: "Oats", minutesAgo: 10))
        context.insert(foodEntry(name: "OATS", minutesAgo: 60))
        context.insert(foodEntry(name: "oats", minutesAgo: 120))
        context.insert(foodEntry(name: "Eggs", minutesAgo: 30))
        try context.save()

        let viewModel = FoodSearchViewModel()
        viewModel.loadLocal(from: context)

        #expect(viewModel.recents.count == 2)
        // Newest first: "Oats" (10 min ago) before "Eggs" (30 min ago), and
        // the newest casing wins the dedupe.
        #expect(viewModel.recents.map(\.name) == ["Oats", "Eggs"])
    }

    @Test func recentsAreCappedAtTwentyNewestFirst() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        for index in 0..<25 {
            // Food0 is newest, Food24 is oldest.
            context.insert(foodEntry(name: "Food\(index)", minutesAgo: index + 1))
        }
        try context.save()

        let viewModel = FoodSearchViewModel()
        viewModel.loadLocal(from: context)

        #expect(viewModel.recents.count == 20)
        #expect(viewModel.recents.first?.name == "Food0")
        #expect(viewModel.recents.last?.name == "Food19")
        #expect(!viewModel.recents.contains { $0.name == "Food20" })
    }

    @Test func recentsSkipZeroGramEntries() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        context.insert(foodEntry(name: "Unmeasured", minutesAgo: 5, grams: 0))
        context.insert(foodEntry(name: "Rice", minutesAgo: 10))
        try context.save()

        let viewModel = FoodSearchViewModel()
        viewModel.loadLocal(from: context)

        #expect(viewModel.recents.map(\.name) == ["Rice"])
    }

    // MARK: - My Foods filtering

    @Test func filteredMyFoodsReturnsAllForBlankOrWhitespaceQuery() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        context.insert(CustomFood(name: "Greek Yogurt", brand: "Fage", caloriesPer100g: 97, createdAt: anchor.addingTimeInterval(-60)))
        context.insert(CustomFood(name: "Chicken Breast", brand: "Costco", caloriesPer100g: 165, createdAt: anchor.addingTimeInterval(-120)))
        try context.save()

        let viewModel = FoodSearchViewModel()
        viewModel.loadLocal(from: context)

        viewModel.query = ""
        #expect(viewModel.filteredMyFoods.count == 2)

        viewModel.query = "   "
        #expect(viewModel.filteredMyFoods.count == 2)

        // Newest createdAt first.
        #expect(viewModel.filteredMyFoods.map(\.name) == ["Greek Yogurt", "Chicken Breast"])
    }

    @Test func filteredMyFoodsMatchesNameOrBrandCaseInsensitively() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        context.insert(CustomFood(name: "Greek Yogurt", brand: "Fage", caloriesPer100g: 97))
        context.insert(CustomFood(name: "Chicken Breast", brand: "Costco", caloriesPer100g: 165))
        try context.save()

        let viewModel = FoodSearchViewModel()
        viewModel.loadLocal(from: context)

        viewModel.query = "GREEK"
        #expect(viewModel.filteredMyFoods.map(\.name) == ["Greek Yogurt"])

        viewModel.query = "fage"
        #expect(viewModel.filteredMyFoods.map(\.name) == ["Greek Yogurt"])

        viewModel.query = "  costco  "
        #expect(viewModel.filteredMyFoods.map(\.name) == ["Chicken Breast"])

        viewModel.query = "zzz"
        #expect(viewModel.filteredMyFoods.isEmpty)
    }

    // MARK: - Search state (no network)

    @Test func searchSetsIdleForQueriesUnderTwoCharacters() async throws {
        let viewModel = FoodSearchViewModel()

        // Park the state in .loading first so the idle reset is observable.
        // The debounce sleep is cancelled long before any network call.
        viewModel.query = "chicken"
        let inFlight = Task { await viewModel.search() }
        try await Task.sleep(for: .milliseconds(50))
        inFlight.cancel()
        await inFlight.value
        #expect(isLoading(viewModel.state))

        viewModel.query = "c"
        await viewModel.search()
        #expect(isIdle(viewModel.state))
    }

    @Test func searchTreatsWhitespacePaddedShortQueryAsShort() async throws {
        let viewModel = FoodSearchViewModel()
        viewModel.query = "  a  "
        await viewModel.search()
        #expect(isIdle(viewModel.state))

        viewModel.query = ""
        await viewModel.search()
        #expect(isIdle(viewModel.state))
    }

    @Test func searchDoesNothingForNonAllFilters() async throws {
        let viewModel = FoodSearchViewModel()
        viewModel.filter = .myFoods
        viewModel.query = "chicken breast"
        await viewModel.search()
        // The guard bails before touching state or the network.
        #expect(isIdle(viewModel.state))
    }

    // MARK: - Error copy

    @Test func userMessageMapsOfflineErrorsToOfflineCopy() {
        let offlineCodes: [URLError.Code] = [.notConnectedToInternet, .networkConnectionLost, .dataNotAllowed]
        for code in offlineCodes {
            let message = FoodSearchViewModel.userMessage(for: URLError(code))
            #expect(message == "You are offline. Check your connection and try again.", "code \(code)")
        }
    }

    @Test func userMessageMapsTimeoutToTimeoutCopy() {
        let message = FoodSearchViewModel.userMessage(for: URLError(.timedOut))
        #expect(message == "The search timed out. Try again in a moment.")
    }

    @Test func userMessageFallsBackToLocalizedDescription() {
        let error = NSError(
            domain: "vora.test",
            code: 42,
            userInfo: [NSLocalizedDescriptionKey: "Something specific went wrong."]
        )
        #expect(FoodSearchViewModel.userMessage(for: error) == "Something specific went wrong.")

        // Non-connectivity URLErrors also fall through to their own description.
        let badURL = URLError(.badURL)
        #expect(FoodSearchViewModel.userMessage(for: badURL) == badURL.localizedDescription)
    }
}
