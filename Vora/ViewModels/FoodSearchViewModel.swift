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

    private let client = OpenFoodFactsClient()

    // MARK: - Local data

    func loadLocal(from context: ModelContext) {
        loadRecents(from: context)
        loadMyFoods(from: context)
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

    var filteredMyFoods: [CustomFood] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return myFoods }
        return myFoods.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed)
                || $0.brand.localizedCaseInsensitiveContains(trimmed)
        }
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
            state = .failed(error.localizedDescription)
        }
    }

    func lookUpBarcode(_ code: String) async throws -> FoodItem {
        try await client.product(barcode: code)
    }
}
