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
            SavedMeal.self, SavedMealItem.self, Recipe.self, RecipeIngredient.self,
        ])
        return try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
    }

    // MARK: - Calorie estimation

    @Test func defaultEstimateUses75kgBodyWeight() {
        // Treadmill 8 km/h flat = 8.3 MET × 75 kg × 0.5 h = 311.25 kcal.
        let viewModel = CardioLogViewModel()
        #expect(abs(viewModel.estimatedCalories - 311.25) < 0.001)
    }

    // Same order as CardioType.loggableCases (inlined: the static property is
    // main-actor-isolated and @Test argument expansion is nonisolated).
    @Test(arguments: zip(
        [CardioType.treadmill, .stairClimber, .elliptical, .stationaryBike,
         .row, .run, .cycle, .walk, .swim, .other],
        // With each type's default inputs at 75 kg for one hour:
        // treadmill 8.3, stairs 7.0, elliptical 6.0, bike 6.8 (8 × 80 = 640),
        // row 7.0, run 10.5, cycle 8.0, walk 3.5, swim 8.0, other 6.0 MET.
        [622.5, 525.0, 450.0, 510.0, 525.0, 787.5, 600.0, 262.5, 600.0, 450.0]
    ))
    func estimateMatchesMETForEveryType(type: CardioType, expected: Double) {
        let viewModel = CardioLogViewModel()
        viewModel.select(type)
        viewModel.durationMinutes = 60
        #expect(abs(viewModel.estimatedCalories - expected) < 0.001)
    }

    @Test func estimateRespondsToMachineInputs() {
        // Treadmill 8.5 km/h interpolates to 8.85 MET; +2% incline adds 1.0.
        let viewModel = CardioLogViewModel()
        viewModel.select(.treadmill)
        viewModel.speedKmh = 8.5
        viewModel.inclinePercent = 2
        viewModel.durationMinutes = 30
        // 9.85 × 75 × 0.5 = 369.375.
        #expect(abs(viewModel.estimatedCalories - 369.375) < 0.001)
    }

    @Test func zeroDurationEstimatesZeroCalories() {
        let viewModel = CardioLogViewModel()
        viewModel.durationMinutes = 0
        #expect(viewModel.estimatedCalories == 0)
    }

    // MARK: - Type selection

    @Test(arguments: zip(
        [CardioType.treadmill, .run, .cycle, .walk, .stairClimber],
        [8.0, 10.0, 20.0, 5.0, 8.0]
    ))
    func selectResetsSpeedDefaultPerType(type: CardioType, expectedSpeed: Double) {
        let viewModel = CardioLogViewModel()
        viewModel.select(type)
        #expect(abs(viewModel.speedKmh - expectedSpeed) < 0.001)
    }

    @Test func selectResetsIncline() {
        let viewModel = CardioLogViewModel()
        viewModel.inclinePercent = 5
        viewModel.select(.walk)
        #expect(viewModel.inclinePercent == 0)
    }

    // MARK: - Pace and distance

    @Test func paceBridgesToSpeed() {
        let viewModel = CardioLogViewModel()
        viewModel.select(.run)
        #expect(abs(viewModel.paceMinPerKm - 6.0) < 0.001)

        viewModel.paceMinPerKm = 5.0
        #expect(abs(viewModel.speedKmh - 12.0) < 0.001)
    }

    @Test func distanceDerivesFromSpeedForSpeedTypesOnly() throws {
        let viewModel = CardioLogViewModel()
        viewModel.select(.run)
        viewModel.durationMinutes = 30
        // 10 km/h × 0.5 h = 5 km.
        #expect(abs(try #require(viewModel.distanceKm) - 5.0) < 0.001)

        viewModel.select(.stairClimber)
        #expect(viewModel.distanceKm == nil)
    }

    // MARK: - Body weight loading

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

        // Treadmill 8 km/h = 8.3 MET × 80 kg × 1 h = 664 kcal.
        #expect(abs(viewModel.estimatedCalories - 664) < 0.001)
    }

    @Test func loadWithoutWeightEntriesKeepsDefaultBodyWeight() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let viewModel = CardioLogViewModel()
        viewModel.load(from: context)

        #expect(abs(viewModel.estimatedCalories - 311.25) < 0.001)
    }

    // MARK: - Save

    @Test func saveTreadmillPersistsMachineFields() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        context.insert(WeightEntry(date: .now, weightKg: 80))
        try context.save()

        let viewModel = CardioLogViewModel()
        viewModel.load(from: context)
        viewModel.select(.treadmill)
        viewModel.speedKmh = 8.5
        viewModel.inclinePercent = 2
        viewModel.durationMinutes = 30

        viewModel.save(in: context)

        let entries = try context.fetch(FetchDescriptor<CardioEntry>())
        #expect(entries.count == 1)
        let entry = try #require(entries.first)
        #expect(entry.type == .treadmill)
        #expect(entry.durationSeconds == 1800)
        // 8.85 MET + 1.0 incline = 9.85 × 80 kg × 0.5 h = 394 kcal.
        #expect(abs(entry.estimatedCalories - 394) < 0.001)
        #expect(abs(entry.date.timeIntervalSinceNow) < 5)
        #expect(entry.speedKmh == 8.5)
        #expect(entry.inclinePercent == 2)
        #expect(abs(try #require(entry.distanceKm) - 4.25) < 0.001)
        #expect(entry.pace == nil)
        #expect(entry.stepsPerMinute == nil)
        #expect(entry.strokesPerMinute == nil)
        #expect(entry.resistanceLevel == nil)
        #expect(entry.rpm == nil)
    }

    @Test func saveRunningPersistsPaceAndDistance() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let viewModel = CardioLogViewModel()
        viewModel.select(.run)
        viewModel.durationMinutes = 30

        viewModel.save(in: context)

        let entry = try #require(try context.fetch(FetchDescriptor<CardioEntry>()).first)
        #expect(entry.speedKmh == 10)
        #expect(abs(try #require(entry.distanceKm) - 5.0) < 0.001)
        #expect(abs(try #require(entry.pace) - 6.0) < 0.001)
        #expect(entry.inclinePercent == nil)
    }

    @Test func saveStairClimberPersistsOnlyStepRate() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let viewModel = CardioLogViewModel()
        viewModel.select(.stairClimber)
        viewModel.stepsPerMinute = 85

        viewModel.save(in: context)

        let entry = try #require(try context.fetch(FetchDescriptor<CardioEntry>()).first)
        #expect(entry.stepsPerMinute == 85)
        #expect(entry.speedKmh == nil)
        #expect(entry.distanceKm == nil)
        #expect(entry.resistanceLevel == nil)
    }

    @Test func saveTwiceCreatesTwoEntries() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let viewModel = CardioLogViewModel()
        viewModel.save(in: context)
        viewModel.select(.row)
        viewModel.save(in: context)

        let entries = try context.fetch(FetchDescriptor<CardioEntry>())
        #expect(entries.count == 2)
        #expect(entries.contains { $0.type == .treadmill })
        #expect(entries.contains { $0.type == .row })
    }
}
