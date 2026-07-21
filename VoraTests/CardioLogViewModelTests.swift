//
//  CardioLogViewModelTests.swift
//  VoraTests
//
//  Created by Majd Arow on 2026-07-21.
//

import Foundation
import SwiftData
import Testing
@testable import Vora

struct CardioLogViewModelTests {
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

    // MARK: - Calorie estimation

    @Test func defaultEstimateUses75kgBodyWeight() {
        // Run MET 9.8 x 75 kg x 0.5 h = 367.5 kcal.
        let viewModel = CardioLogViewModel()
        #expect(abs(viewModel.estimatedCalories - 367.5) < 0.001)
    }

    @Test func estimateScalesWithTypeAndDuration() {
        let viewModel = CardioLogViewModel()
        viewModel.type = .walk
        viewModel.durationMinutes = 60
        // Walk MET 3.5 x 75 kg x 1 h = 262.5 kcal.
        #expect(abs(viewModel.estimatedCalories - 262.5) < 0.001)
    }

    @Test(arguments: zip(
        [CardioType.run, .walk, .cycle, .row, .swim, .other],
        [9.8, 3.5, 7.5, 7.0, 8.0, 6.0]
    ))
    func estimateMatchesMETForEveryType(type: CardioType, met: Double) {
        let viewModel = CardioLogViewModel()
        viewModel.type = type
        viewModel.durationMinutes = 60
        #expect(abs(viewModel.estimatedCalories - met * 75) < 0.001)
    }

    @Test func zeroDurationEstimatesZeroCalories() {
        let viewModel = CardioLogViewModel()
        viewModel.durationMinutes = 0
        #expect(viewModel.estimatedCalories == 0)
    }

    @Test func loadUsesLatestWeightEntry() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let cal = Calendar.current
        context.insert(WeightEntry(
            date: cal.date(byAdding: .day, value: -5, to: .now)!,
            weightKg: 70
        ))
        context.insert(WeightEntry(
            date: cal.date(byAdding: .day, value: -1, to: .now)!,
            weightKg: 80
        ))
        try context.save()

        let viewModel = CardioLogViewModel()
        viewModel.load(from: context)
        viewModel.durationMinutes = 60

        // Run MET 9.8 x 80 kg x 1 h = 784 kcal.
        #expect(abs(viewModel.estimatedCalories - 784) < 0.001)
    }

    @Test func loadWithoutWeightEntriesKeepsDefaultBodyWeight() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let viewModel = CardioLogViewModel()
        viewModel.load(from: context)

        #expect(abs(viewModel.estimatedCalories - 367.5) < 0.001)
    }

    // MARK: - Save

    @Test func savePersistsEntryWithDurationTypeAndCalories() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        context.insert(WeightEntry(date: .now, weightKg: 80))
        try context.save()

        let viewModel = CardioLogViewModel()
        viewModel.load(from: context)
        viewModel.type = .row
        viewModel.durationMinutes = 45

        viewModel.save(in: context)

        let entries = try context.fetch(FetchDescriptor<CardioEntry>())
        #expect(entries.count == 1)
        let entry = try #require(entries.first)
        #expect(entry.type == .row)
        #expect(entry.durationSeconds == 2700)
        // Row MET 7.0 x 80 kg x 0.75 h = 420 kcal.
        #expect(abs(entry.estimatedCalories - 420) < 0.001)
        #expect(abs(entry.date.timeIntervalSinceNow) < 5)
    }

    @Test func saveTwiceCreatesTwoEntries() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let viewModel = CardioLogViewModel()
        viewModel.save(in: context)
        viewModel.type = .swim
        viewModel.save(in: context)

        let entries = try context.fetch(FetchDescriptor<CardioEntry>())
        #expect(entries.count == 2)
        #expect(entries.contains { $0.type == .run })
        #expect(entries.contains { $0.type == .swim })
    }
}
