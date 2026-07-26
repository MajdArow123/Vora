//
//  MeasurementLogViewModelTests.swift
//  VoraTests
//
//  Created by Majd Arow on 2026-07-26.
//

import Foundation
import SwiftData
import Testing
@testable import Vora

struct MeasurementLogViewModelTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            UserProfile.self, FoodEntry.self, CustomFood.self,
            WorkoutSession.self, ExerciseLog.self, SetEntry.self,
            WeightEntry.self, BodyMeasurement.self, WaterEntry.self,
            CardioEntry.self, SplitDay.self,
            SavedMeal.self, SavedMealItem.self, Recipe.self, RecipeIngredient.self,
        ])
        return try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
    }

    // MARK: - Parsing

    @Test func metricInputParsesAsCm() {
        let viewModel = MeasurementLogViewModel()
        viewModel.texts[.waist] = "82.5"
        #expect(viewModel.parsedValue(for: .waist) == 82.5)
    }

    @Test func commaDecimalSeparatorParses() {
        let viewModel = MeasurementLogViewModel()
        viewModel.texts[.chest] = "101,2"
        #expect(viewModel.parsedValue(for: .chest) == 101.2)
    }

    @Test func emptyFieldParsesAsNilAndIsNotInvalid() {
        let viewModel = MeasurementLogViewModel()
        #expect(viewModel.parsedValue(for: .hips) == nil)
        #expect(!viewModel.fieldIsInvalid(.hips))
    }

    @Test func garbageInputIsInvalid() {
        let viewModel = MeasurementLogViewModel()
        viewModel.texts[.neck] = "abc"
        #expect(viewModel.parsedValue(for: .neck) == nil)
        #expect(viewModel.fieldIsInvalid(.neck))
    }

    @Test func outOfRangeLengthIsInvalid() {
        let viewModel = MeasurementLogViewModel()
        viewModel.texts[.waist] = "400"
        #expect(viewModel.parsedValue(for: .waist) == nil)
        #expect(viewModel.fieldIsInvalid(.waist))
    }

    @Test func bodyFatValidatesPercentRange() {
        let viewModel = MeasurementLogViewModel()
        viewModel.texts[.bodyFat] = "12.4"
        #expect(viewModel.parsedValue(for: .bodyFat) == 12.4)
        viewModel.texts[.bodyFat] = "95"
        #expect(viewModel.parsedValue(for: .bodyFat) == nil)
    }

    // MARK: - Imperial conversion

    private func makeImperialProfile() -> UserProfile {
        UserProfile(
            name: "Imperial User",
            dateOfBirth: .now,
            heightCm: 175,
            biologicalSex: .male,
            goalType: .fatLoss,
            activityLevel: .moderatelyActive,
            trainingSplit: .upperLower,
            dailyCalorieTarget: 2200,
            proteinTargetG: 150,
            carbsTargetG: 220,
            fatTargetG: 70,
            preferredUnits: .imperial
        )
    }

    @Test func imperialLengthInputConvertsInchesToCm() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        context.insert(makeImperialProfile())
        try context.save()

        let viewModel = MeasurementLogViewModel()
        viewModel.load(from: context)
        viewModel.texts[.waist] = "32"
        let parsed = try #require(viewModel.parsedValue(for: .waist))
        #expect(abs(parsed - 81.28) < 0.001)
    }

    @Test func imperialBodyFatIsNotConverted() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        context.insert(makeImperialProfile())
        try context.save()

        let viewModel = MeasurementLogViewModel()
        viewModel.load(from: context)
        viewModel.texts[.bodyFat] = "15"
        #expect(viewModel.parsedValue(for: .bodyFat) == 15)
    }

    // MARK: - Save gating

    @Test func canSaveRequiresAtLeastOneValidField() {
        let viewModel = MeasurementLogViewModel()
        #expect(!viewModel.canSave)
        viewModel.texts[.waist] = "82.5"
        #expect(viewModel.canSave)
        viewModel.texts[.neck] = "abc"
        #expect(!viewModel.canSave)
    }

    // MARK: - Saving

    @Test func saveWritesOnlyFilledFieldsAndTrimsNotes() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let viewModel = MeasurementLogViewModel()
        viewModel.load(from: context)
        viewModel.texts[.waist] = "82.5"
        viewModel.texts[.bodyFat] = "12.4"
        viewModel.notes = "  Morning  "
        viewModel.save(in: context)

        let saved = try #require(try context.fetch(FetchDescriptor<BodyMeasurement>()).first)
        #expect(saved.waistCm == 82.5)
        #expect(saved.bodyFatPercent == 12.4)
        #expect(saved.hipsCm == nil)
        #expect(saved.chestCm == nil)
        #expect(saved.notes == "Morning")
    }

    @Test func saveWithEmptyNotesStoresNil() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let viewModel = MeasurementLogViewModel()
        viewModel.texts[.chest] = "101.2"
        viewModel.notes = "   "
        viewModel.save(in: context)

        let saved = try #require(try context.fetch(FetchDescriptor<BodyMeasurement>()).first)
        #expect(saved.notes == nil)
    }

    // MARK: - Field metadata

    @Test func summaryListsOnlyRecordedFieldsInOrder() {
        let measurement = BodyMeasurement(date: .now, waistCm: 82.5, chestCm: 101.2, bodyFatPercent: 12.4)
        let summary = MeasurementField.summary(for: measurement, units: .metric)
        #expect(summary == "Waist 82.5 cm · Chest 101.2 cm · Body fat 12.4%")
    }

    @Test func summaryLimitAppendsMoreCount() {
        let measurement = BodyMeasurement(
            date: .now, waistCm: 82, hipsCm: 96, chestCm: 101, leftArmCm: 36, rightArmCm: 36.5
        )
        let summary = MeasurementField.summary(for: measurement, units: .metric, limit: 3)
        #expect(summary.hasSuffix("+2 more"))
    }

    @Test func legacyZeroBodyFatIsNotRecorded() {
        let measurement = BodyMeasurement(date: .now, waistCm: 80, bodyFatPercent: 0)
        let recorded = MeasurementField.recordedValues(measurement)
        #expect(recorded.map(\.field) == [.waist])
    }

    @Test func imperialSummaryDisplaysInches() {
        let measurement = BodyMeasurement(date: .now, waistCm: 81.28)
        let summary = MeasurementField.summary(for: measurement, units: .imperial)
        #expect(summary == "Waist 32.0 in")
    }
}
