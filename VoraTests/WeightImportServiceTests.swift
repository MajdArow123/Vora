//
//  WeightImportServiceTests.swift
//  VoraTests
//
//  Created by Majd Arow on 2026-11-02.
//

import Foundation
import SwiftData
import Testing
@testable import Vora

@Suite(.serialized)
struct WeightImportServiceTests {
    private struct ReadFailed: Error {}

    private let container: ModelContainer
    private let context: ModelContext
    private let defaults: UserDefaults
    private let cal = Calendar.current
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    init() throws {
        let schema = Schema([WeightEntry.self])
        container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        context = container.mainContext
        let suite = "vora.tests.weight-import"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defaults.set(true, forKey: WeightImportService.enabledKey)
        self.defaults = defaults
    }

    private func sample(_ kg: Double, dayOffset: Int = 0, id: UUID = UUID()) throws -> HealthBodyMassSample {
        HealthBodyMassSample(id: id, date: try #require(cal.date(byAdding: .day, value: dayOffset, to: now)), kg: kg)
    }

    private func storedEntries() throws -> [WeightEntry] {
        try context.fetch(FetchDescriptor<WeightEntry>(sortBy: [SortDescriptor(\.date)]))
    }

    private func sync(_ reader: StubBodyMassReader) async -> Int {
        await WeightImportService(reader: reader, defaults: defaults).sync(context: context, now: now, calendar: cal)
    }

    @Test func importsSamplesUnderTheirOwnIDs() async throws {
        let scale = try sample(80.4)
        let count = await sync(StubBodyMassReader(result: .success([scale])))

        #expect(count == 1)
        let stored = try storedEntries()
        #expect(stored.map(\.id) == [scale.id])
        #expect(stored.map(\.weightKg) == [80.4])
        #expect(stored.map(\.date) == [scale.date])
    }

    @Test func reimportingIsANoOp() async throws {
        let reader = StubBodyMassReader(result: .success([try sample(80.4), try sample(80.1, dayOffset: -1)]))
        #expect(await sync(reader) == 2)
        #expect(await sync(reader) == 0)
        #expect(try storedEntries().count == 2)
    }

    @Test func sameDayManualEntryIsNotDuplicated() async throws {
        context.insert(WeightEntry(date: now, weightKg: 80.4))
        try context.save()

        #expect(await sync(StubBodyMassReader(result: .success([try sample(80.35)]))) == 0)
        #expect(try storedEntries().count == 1)
    }

    @Test func toleranceBoundaryDecidesTheSameWeighIn() throws {
        let existing = [try sample(80)]
        let imported = WeightImportService.samplesToImport(
            [try sample(80.25), try sample(80.3)],
            existing: existing,
            calendar: cal
        )
        #expect(imported.map(\.kg) == [80.3])
    }

    @Test func differentDayOrDifferentWeightStillImports() async throws {
        context.insert(WeightEntry(date: now, weightKg: 80.4))
        try context.save()

        let count = await sync(StubBodyMassReader(result: .success([
            try sample(80.4, dayOffset: -1),
            try sample(79.5),
        ])))
        #expect(count == 2)
        #expect(try storedEntries().count == 3)
    }

    @Test func twoSourcesReportingOneWeighInImportOnce() throws {
        let imported = WeightImportService.samplesToImport(
            [try sample(80.40), try sample(80.42)],
            existing: [],
            calendar: cal
        )
        #expect(imported.map(\.kg) == [80.40])
    }

    @Test func implausibleWeightsAreSkipped() throws {
        let imported = WeightImportService.samplesToImport(
            [try sample(5), try sample(500, dayOffset: -1), try sample(80, dayOffset: -2)],
            existing: [],
            calendar: cal
        )
        #expect(imported.map(\.kg) == [80])
    }

    @Test func readerErrorLeavesTheStoreUnchanged() async throws {
        context.insert(WeightEntry(date: now, weightKg: 80))
        try context.save()

        #expect(await sync(StubBodyMassReader(result: .failure(ReadFailed()))) == 0)
        #expect(try storedEntries().map(\.weightKg) == [80])
    }

    @Test func offMeansTheReaderIsNeverCalled() async throws {
        defaults.set(false, forKey: WeightImportService.enabledKey)
        let reader = StubBodyMassReader(result: .success([try sample(80)]))

        #expect(await sync(reader) == 0)
        #expect(reader.requestedSince.isEmpty)
        #expect(try storedEntries().isEmpty)
    }

    @Test func offByDefault() async throws {
        defaults.removeObject(forKey: WeightImportService.enabledKey)
        let reader = StubBodyMassReader(result: .success([try sample(80)]))

        #expect(await sync(reader) == 0)
        #expect(reader.requestedSince.isEmpty)
    }

    @Test func firstRunReadsFullHistoryThenTheTrailingWindow() async throws {
        let reader = StubBodyMassReader(result: .success([try sample(80)]))
        _ = await sync(reader)
        _ = await sync(reader)

        let window = cal.date(byAdding: .day, value: -WeightImportService.trailingDays, to: cal.startOfDay(for: now))
        #expect(reader.requestedSince == [nil, window])
    }

    @Test func anEmptyReadStaysEligibleForFullHistory() async throws {
        // A denied read looks like this, and access may be granted later.
        let reader = StubBodyMassReader()
        _ = await sync(reader)
        _ = await sync(reader)
        #expect(reader.requestedSince == [nil, nil])
    }

    @Test func turningItOffAndOnReadsFullHistoryAgain() async throws {
        let reader = StubBodyMassReader(result: .success([try sample(80)]))
        _ = await sync(reader)

        defaults.set(false, forKey: WeightImportService.enabledKey)
        _ = await sync(reader)
        defaults.set(true, forKey: WeightImportService.enabledKey)
        _ = await sync(reader)

        #expect(reader.requestedSince == [nil, nil])
    }
}
