//
//  SupplementHomeViewModelTests.swift
//  VoraTests
//
//  Created by Majd Arow on 2026-07-26.
//

import Foundation
import SwiftData
import Testing
@testable import Vora

@MainActor
struct SupplementHomeViewModelTests {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            UserProfile.self, FoodEntry.self, CustomFood.self,
            WorkoutSession.self, ExerciseLog.self, SetEntry.self,
            WeightEntry.self, BodyMeasurement.self, WaterEntry.self,
            CardioEntry.self, SplitDay.self, SavedMeal.self,
            SavedMealItem.self, Recipe.self, RecipeIngredient.self,
            Supplement.self, SupplementLog.self,
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    private func makeViewModel() throws -> (HomeViewModel, ModelContext) {
        let defaults = try #require(UserDefaults(suiteName: "vora.tests.supplements"))
        defaults.removePersistentDomain(forName: "vora.tests.supplements")
        return (HomeViewModel(defaults: defaults), try makeContext())
    }

    @Test func toggleInsertsLogWithSnapshotsAndStartOfDayDate() throws {
        let (viewModel, context) = try makeViewModel()
        let creatine = Supplement(name: "Creatine", dose: "5g", timing: .morning, orderIndex: 0)
        context.insert(creatine)
        try context.save()
        viewModel.load(from: context)

        let markedTaken = viewModel.toggleSupplement(creatine, context: context)
        #expect(markedTaken)

        let logs = try context.fetch(FetchDescriptor<SupplementLog>())
        let log = try #require(logs.first)
        #expect(log.supplementID == creatine.id)
        #expect(log.supplementName == "Creatine")
        #expect(log.dose == "5g")
        #expect(log.date == Calendar.current.startOfDay(for: .now))
        #expect(viewModel.takenSupplementIDs.contains(creatine.id))
        #expect(viewModel.supplementsTakenCount == 1)
    }

    @Test func toggleTwiceRemovesTodaysLog() throws {
        let (viewModel, context) = try makeViewModel()
        let creatine = Supplement(name: "Creatine", dose: "5g", orderIndex: 0)
        context.insert(creatine)
        try context.save()
        viewModel.load(from: context)

        viewModel.toggleSupplement(creatine, context: context)
        let markedTaken = viewModel.toggleSupplement(creatine, context: context)

        #expect(!markedTaken)
        #expect(try context.fetch(FetchDescriptor<SupplementLog>()).isEmpty)
        #expect(!viewModel.takenSupplementIDs.contains(creatine.id))
    }

    @Test func activeSupplementsFilterInactiveAndSortByOrderIndex() throws {
        let (viewModel, context) = try makeViewModel()
        context.insert(Supplement(name: "Second", dose: "1g", orderIndex: 1))
        context.insert(Supplement(name: "First", dose: "1g", orderIndex: 0))
        context.insert(Supplement(name: "Deleted", dose: "1g", isActive: false, orderIndex: 2))
        try context.save()

        viewModel.load(from: context)

        #expect(viewModel.activeSupplements.map(\.name) == ["First", "Second"])
    }

    @Test func yesterdaysLogDoesNotCountAsTakenToday() throws {
        let (viewModel, context) = try makeViewModel()
        let cal = Calendar.current
        let yesterday = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: .now))!
        // Created before yesterday so yesterday counts toward the streak.
        let creatine = Supplement(name: "Creatine", dose: "5g", orderIndex: 0, createdAt: yesterday)
        context.insert(creatine)
        context.insert(SupplementLog(
            supplementID: creatine.id,
            supplementName: "Creatine",
            dose: "5g",
            date: yesterday
        ))
        try context.save()

        viewModel.load(from: context)

        #expect(viewModel.takenSupplementIDs.isEmpty)
        #expect(viewModel.supplementStreakDays == 1) // yesterday qualified, today is a grace day
    }

    @Test func untakenEarlyNamesOnlyIncludeMorningAndPreWorkout() throws {
        let (viewModel, context) = try makeViewModel()
        let creatine = Supplement(name: "Creatine", dose: "5g", timing: .morning, orderIndex: 0)
        context.insert(creatine)
        context.insert(Supplement(name: "Pre", dose: "1 scoop", timing: .preWorkout, orderIndex: 1))
        context.insert(Supplement(name: "Magnesium", dose: "400mg", timing: .evening, orderIndex: 2))
        try context.save()

        viewModel.load(from: context)
        #expect(viewModel.untakenEarlySupplementNames == ["Creatine", "Pre"])

        viewModel.toggleSupplement(creatine, context: context)
        #expect(viewModel.untakenEarlySupplementNames == ["Pre"])
    }
}
