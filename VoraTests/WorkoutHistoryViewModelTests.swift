//
//  WorkoutHistoryViewModelTests.swift
//  VoraTests
//
//  Created by Majd Arow on 2026-07-21.
//

import Foundation
import SwiftData
import Testing
@testable import Vora

struct WorkoutHistoryViewModelTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            UserProfile.self, FoodEntry.self, CustomFood.self,
            WorkoutSession.self, ExerciseLog.self, SetEntry.self,
            WeightEntry.self, WaterEntry.self, CardioEntry.self, SplitDay.self,
            SavedMeal.self, SavedMealItem.self, Recipe.self, RecipeIngredient.self,
        ])
        return try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
    }

    private func date(hoursAgo: Double) -> Date {
        Date.now.addingTimeInterval(-hoursAgo * 3600)
    }

    // MARK: - Loading

    @Test func loadWithEmptyStoreYieldsNoItems() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let viewModel = WorkoutHistoryViewModel()
        viewModel.load(from: context)

        #expect(viewModel.items.isEmpty)
    }

    @Test func loadMergesLiftingAndCardioNewestFirst() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        context.insert(WorkoutSession(date: date(hoursAgo: 3), sessionName: "Push"))
        context.insert(CardioEntry(
            date: date(hoursAgo: 1),
            type: .run,
            durationSeconds: 1800,
            estimatedCalories: 300
        ))
        context.insert(WorkoutSession(date: date(hoursAgo: 2), sessionName: "Pull"))
        context.insert(CardioEntry(
            date: date(hoursAgo: 4),
            type: .walk,
            durationSeconds: 3600,
            estimatedCalories: 250
        ))
        try context.save()

        let viewModel = WorkoutHistoryViewModel()
        viewModel.load(from: context)

        #expect(viewModel.items.count == 4)
        let dates = viewModel.items.map(\.date)
        #expect(dates == dates.sorted(by: >))

        // Interleaving: cardio, lifting, lifting, cardio.
        let kinds = viewModel.items.map { item -> String in
            switch item {
            case .lifting: "lifting"
            case .cardio: "cardio"
            }
        }
        #expect(kinds == ["cardio", "lifting", "lifting", "cardio"])
    }

    @Test func loadReplacesPreviousItems() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        context.insert(WorkoutSession(date: date(hoursAgo: 2), sessionName: "Push"))
        try context.save()

        let viewModel = WorkoutHistoryViewModel()
        viewModel.load(from: context)
        #expect(viewModel.items.count == 1)

        context.insert(CardioEntry(
            date: date(hoursAgo: 1),
            type: .cycle,
            durationSeconds: 900,
            estimatedCalories: 120
        ))
        try context.save()
        viewModel.load(from: context)

        #expect(viewModel.items.count == 2)
    }

    // MARK: - Deleting

    private struct SaveFailure: Error {}

    private struct NoHealthWorkouts: HealthWorkoutDeleting {
        func deleteWorkout(id: UUID) async throws -> HealthWorkoutDeletionResult {
            .noMatch
        }

        func deleteWorkout(matching match: HealthWorkoutMatch) async throws -> HealthWorkoutDeletionResult {
            .noMatch
        }
    }

    private func makeViewModel() -> WorkoutHistoryViewModel {
        WorkoutHistoryViewModel(deletionService: WorkoutDeletionService(health: NoHealthWorkouts()))
    }

    @Test func deleteRemovesTheRowAndTheModel() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let session = WorkoutSession(date: date(hoursAgo: 2), sessionName: "Push", durationSeconds: 600)
        context.insert(session)
        context.insert(CardioEntry(date: date(hoursAgo: 1), type: .run, durationSeconds: 900, estimatedCalories: 90))
        try context.save()
        let viewModel = makeViewModel()
        viewModel.load(from: context)

        let task = try viewModel.delete(.lifting(session), context: context)
        await task.value

        #expect(viewModel.items.count == 1)
        #expect(try context.fetchCount(FetchDescriptor<WorkoutSession>()) == 0)
        viewModel.load(from: context)
        #expect(viewModel.items.count == 1)
    }

    @Test func deleteCardioRemovesTheRowAndTheModel() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let entry = CardioEntry(date: date(hoursAgo: 1), type: .run, durationSeconds: 900, estimatedCalories: 90)
        context.insert(entry)
        try context.save()
        let viewModel = makeViewModel()
        viewModel.load(from: context)

        let task = try viewModel.delete(.cardio(entry), context: context)
        await task.value

        #expect(viewModel.items.isEmpty)
        #expect(try context.fetchCount(FetchDescriptor<CardioEntry>()) == 0)
    }

    @Test func failedDeleteRestoresTheRowInPlace() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let session = WorkoutSession(date: date(hoursAgo: 2), sessionName: "Push", durationSeconds: 600)
        context.insert(session)
        context.insert(CardioEntry(date: date(hoursAgo: 1), type: .run, durationSeconds: 900, estimatedCalories: 90))
        try context.save()
        let viewModel = makeViewModel()
        viewModel.load(from: context)
        let idsBefore = viewModel.items.map(\.id)

        #expect(throws: SaveFailure.self) {
            try viewModel.delete(.lifting(session), context: context, save: { _ in throw SaveFailure() })
        }

        #expect(viewModel.items.map(\.id) == idsBefore)
        #expect(try context.fetchCount(FetchDescriptor<WorkoutSession>()) == 1)
    }

    @Test func deletionPromptNamesWhatIsBeingDeleted() {
        let session = WorkoutSession(date: date(hoursAgo: 2), sessionName: "Push")
        let entry = CardioEntry(date: date(hoursAgo: 1), type: .swim, durationSeconds: 900, estimatedCalories: 90)

        let sessionPrompt = HistoryDeletionPrompt(item: .lifting(session))
        let cardioPrompt = HistoryDeletionPrompt(item: .cardio(entry))

        #expect(sessionPrompt.title == "Delete Workout?")
        #expect(sessionPrompt.message.hasPrefix("Push on "))
        #expect(cardioPrompt.title == "Delete Cardio?")
        #expect(cardioPrompt.message.hasPrefix("Swim on "))
        #expect(sessionPrompt.message.contains("PRs"))
        #expect(!cardioPrompt.message.contains("PRs"))
    }

    // MARK: - HistoryItem mapping

    @Test func historyItemForwardsSessionIdentityAndDate() {
        let session = WorkoutSession(date: date(hoursAgo: 5), sessionName: "Legs")
        let item = HistoryItem.lifting(session)
        #expect(item.id == session.id)
        #expect(item.date == session.date)
    }

    @Test func historyItemForwardsCardioIdentityAndDate() {
        let entry = CardioEntry(
            date: date(hoursAgo: 6),
            type: .swim,
            durationSeconds: 1200,
            estimatedCalories: 200
        )
        let item = HistoryItem.cardio(entry)
        #expect(item.id == entry.id)
        #expect(item.date == entry.date)
    }
}
