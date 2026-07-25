//
//  FoodSearchViewModel.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import Foundation
import Observation
import SwiftData

enum SearchFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case myFoods = "My Foods"
    case recipes = "Recipes"
    case meals = "Meals"

    var id: String { rawValue }
}

enum SearchState {
    case idle
    case loading
    case loaded([FoodItem])
    case failed(String)
}

@Observable
final class FoodSearchViewModel {
    var query = ""
    var filter: SearchFilter = .all
    private(set) var state: SearchState = .idle
    private(set) var recents: [FoodItem] = []
    private(set) var myFoods: [CustomFood] = []
    private(set) var savedMeals: [SavedMeal] = []
    private(set) var recipes: [Recipe] = []

    private let client = OpenFoodFactsClient()

    // MARK: - Local data

    func loadLocal(from context: ModelContext) {
        loadRecents(from: context)
        loadMyFoods(from: context)
        loadSavedMeals(from: context)
        loadRecipes(from: context)
    }

    /// Last 20 unique foods logged, newest first.
    private func loadRecents(from context: ModelContext) {
        var descriptor = FetchDescriptor<FoodEntry>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 200
        let entries = (try? context.fetch(descriptor)) ?? []

        var seen = Set<String>()
        var items: [FoodItem] = []
        for entry in entries {
            let key = entry.foodName.lowercased()
            guard !seen.contains(key), let item = FoodItem(entry: entry) else { continue }
            seen.insert(key)
            items.append(item)
            if items.count == 20 { break }
        }
        recents = items
    }

    private func loadMyFoods(from context: ModelContext) {
        let descriptor = FetchDescriptor<CustomFood>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        myFoods = (try? context.fetch(descriptor)) ?? []
    }

    private func loadSavedMeals(from context: ModelContext) {
        let descriptor = FetchDescriptor<SavedMeal>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        savedMeals = (try? context.fetch(descriptor)) ?? []
    }

    private func loadRecipes(from context: ModelContext) {
        let descriptor = FetchDescriptor<Recipe>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        recipes = (try? context.fetch(descriptor)) ?? []
    }

    var filteredMyFoods: [CustomFood] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return myFoods }
        return myFoods.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed)
                || $0.brand.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var filteredSavedMeals: [SavedMeal] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return savedMeals }
        return savedMeals.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }

    var filteredRecipes: [Recipe] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return recipes }
        return recipes.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }

    // MARK: - Meals & recipes

    func deleteMeal(_ meal: SavedMeal, context: ModelContext) {
        context.delete(meal)
        do {
            try context.save()
        } catch {
            assertionFailure("Failed to delete saved meal: \(error)")
        }
        loadSavedMeals(from: context)
    }

    func deleteRecipe(_ recipe: Recipe, context: ModelContext) {
        context.delete(recipe)
        do {
            try context.save()
        } catch {
            assertionFailure("Failed to delete recipe: \(error)")
        }
        loadRecipes(from: context)
    }

    /// FoodEntry rows logged on the calendar day containing `date`,
    /// in the order they were logged.
    func entries(onDayOf date: Date, context: ModelContext) -> [FoodEntry] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        let descriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate { $0.date >= start && $0.date < end },
            sortBy: [SortDescriptor(\.date)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Snapshots the day's logged foods into a SavedMeal template.
    /// Returns false (inserting nothing) for a blank name or an empty day.
    @discardableResult
    func saveDayAsMeal(named name: String, dayOf date: Date, context: ModelContext) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let dayEntries = entries(onDayOf: date, context: context)
        guard !trimmed.isEmpty, !dayEntries.isEmpty else { return false }

        let items = dayEntries.enumerated().map { index, entry in
            SavedMealItem(
                foodName: entry.foodName,
                servingGrams: entry.servingGrams,
                calories: entry.calories,
                proteinG: entry.proteinG,
                carbsG: entry.carbsG,
                fatG: entry.fatG,
                orderIndex: index
            )
        }
        context.insert(SavedMeal(name: trimmed, items: items))
        do {
            try context.save()
        } catch {
            assertionFailure("Failed to save meal: \(error)")
        }
        loadSavedMeals(from: context)
        return true
    }

    // MARK: - Remote search

    /// Debounced search; call from `.task(id:)` so a changed query
    /// cancels the in-flight request.
    func search() async {
        guard filter == .all else { return }

        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            state = .idle
            return
        }

        state = .loading
        do {
            try await Task.sleep(for: .milliseconds(400))
            let items = try await client.search(trimmed)
            guard !Task.isCancelled else { return }
            state = .loaded(items)
        } catch is CancellationError {
            // Superseded by a newer query.
        } catch {
            guard !Task.isCancelled else { return }
            state = .failed(Self.userMessage(for: error))
        }
    }

    /// Friendlier copy for the common connectivity failures; falls back
    /// to the error's own description (OpenFoodFactsError is already
    /// user-readable).
    static func userMessage(for error: Error) -> String {
        switch (error as? URLError)?.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
            "You are offline. Check your connection and try again."
        case .timedOut:
            "The search timed out. Try again in a moment."
        default:
            error.localizedDescription
        }
    }

    func lookUpBarcode(_ code: String) async throws -> FoodItem {
        try await client.product(barcode: code)
    }
}
