//
//  TemplateDefaultsMigrationTests.swift
//  VoraTests
//
//  Created by Majd Arow on 2026-11-01.
//

import Foundation
import SwiftData
import Testing
@testable import Vora

@MainActor
struct TemplateDefaultsMigrationTests {
    private struct SaveFailure: Error {}

    private let key = TemplateDefaultsMigration.storageKey

    /// Held for the test's lifetime; a context outlives its container
    /// only as a dangling reference.
    private let container: ModelContainer

    init() throws {
        container = try PersistenceController.makeContainer(inMemory: true)
    }

    private func makeContext() -> ModelContext {
        container.mainContext
    }

    private func templates(in context: ModelContext) throws -> [WorkoutTemplate] {
        try context.fetch(FetchDescriptor<WorkoutTemplate>(
            sortBy: [SortDescriptor(\.splitRawValue), SortDescriptor(\.dayIndex)]
        ))
    }

    // MARK: - Nothing to migrate

    @Test func missingKeyIsANoOp() throws {
        let context = makeContext()
        let defaults = try makeTestDefaults()

        let outcome = try TemplateDefaultsMigration.run(in: context, defaults: defaults)

        #expect(outcome == TemplateDefaultsMigration.Outcome())
        #expect(try templates(in: context).isEmpty)
    }

    @Test func emptyDictionaryRemovesTheKey() throws {
        let context = makeContext()
        let defaults = try makeTestDefaults()
        defaults.set([String: [String]](), forKey: key)

        let outcome = try TemplateDefaultsMigration.run(in: context, defaults: defaults)

        #expect(outcome.migrated == 0)
        #expect(outcome.removedKey)
        #expect(defaults.object(forKey: key) == nil)
    }

    @Test func nonDictionaryValueIsLeftInPlace() throws {
        let context = makeContext()
        let defaults = try makeTestDefaults()
        defaults.set(["Back Squat", "Leg Press"], forKey: key)

        let outcome = try TemplateDefaultsMigration.run(in: context, defaults: defaults)

        #expect(outcome.invalid == 1)
        #expect(!outcome.removedKey)
        #expect(defaults.stringArray(forKey: key) == ["Back Squat", "Leg Press"])
        #expect(try templates(in: context).isEmpty)
    }

    // MARK: - Malformed entries

    @Test func malformedEntriesAreSkippedAndValidOnesMigrate() throws {
        let context = makeContext()
        let defaults = try makeTestDefaults()
        let stored: [String: Any] = [
            "ppl.0": ["Back Squat"],
            "ppl": ["Dip"],
            "ppl.0.1": ["Dip"],
            "ppl.x": ["Dip"],
            "ppl.7": ["Dip"],
            "ppl.-1": ["Dip"],
            "broSplit.0": ["Dip"],
            "fullBody.2": "Deadlift",
            "fullBody.4": [1, 2],
        ]
        defaults.set(stored, forKey: key)

        let outcome = try TemplateDefaultsMigration.run(in: context, defaults: defaults)

        #expect(outcome.migrated == 1)
        #expect(outcome.invalid == 8)
        #expect(outcome.removedKey)
        let saved = try templates(in: context)
        #expect(saved.map(\.splitRawValue) == ["ppl"])
        #expect(saved.first?.orderedExercises.map(\.exerciseId) == ["back-squat"])
    }

    @Test func slotKeysParseOnlyKnownSplitsAndWeekdays() {
        #expect(TemplateDefaultsMigration.slot(fromKey: "upperLower.6")?.0 == .upperLower)
        #expect(TemplateDefaultsMigration.slot(fromKey: "custom.0")?.1 == 0)
        #expect(TemplateDefaultsMigration.slot(fromKey: "custom.7") == nil)
        #expect(TemplateDefaultsMigration.slot(fromKey: ".0") == nil)
        #expect(TemplateDefaultsMigration.slot(fromKey: "ppl.") == nil)
        #expect(TemplateDefaultsMigration.slot(fromKey: "") == nil)
    }

    // MARK: - Name resolution

    @Test func namesResolveThroughLegacyLookupOrBecomeCustom() throws {
        let context = makeContext()
        let defaults = try makeTestDefaults()
        defaults.set(
            ["ppl.1": ["Pull-Up", "BENCH PRESS", "Leg Curl", "  Sled Push  ", "", "   "]],
            forKey: key
        )

        _ = try TemplateDefaultsMigration.run(in: context, defaults: defaults)

        let template = try #require(try templates(in: context).first)
        #expect(template.name == "Pull")
        let exercises = template.orderedExercises
        #expect(exercises.map(\.exerciseId) == ["pull-up", "barbell-bench-press", "leg-curl", nil])
        #expect(exercises.map(\.customName) == [nil, nil, nil, "Sled Push"])
        #expect(exercises.map(\.orderIndex) == [0, 1, 2, 3])
    }

    @Test func migratedExercisesGetDefaultTargets() throws {
        let context = makeContext()
        let defaults = try makeTestDefaults()
        defaults.set(["upperLower.0": ["Barbell Bench Press", "Lateral Raise", "Sled Push"]], forKey: key)

        _ = try TemplateDefaultsMigration.run(in: context, defaults: defaults)

        let exercises = try #require(try templates(in: context).first).orderedExercises
        #expect(exercises.map(\.restSeconds) == [120, 90, 90])
        #expect(exercises.allSatisfy {
            $0.targetSets == 3 && $0.repRangeMin == 8 && $0.repRangeMax == 12 && $0.targetRIR == 2
        })
    }

    @Test func emptyListBecomesAnEmptyCustomizedTemplate() throws {
        let context = makeContext()
        let defaults = try makeTestDefaults()
        defaults.set(["ppl.2": [String]()], forKey: key)

        _ = try TemplateDefaultsMigration.run(in: context, defaults: defaults)

        #expect(try WorkoutTemplateService.isCustomized(for: .ppl, dayIndex: 2, context: context))
        #expect(try WorkoutTemplateService.plan(for: .ppl, dayIndex: 2, context: context).isEmpty)
    }

    @Test func restAndCustomSlotsGetNumberedNames() throws {
        let context = makeContext()
        let defaults = try makeTestDefaults()
        defaults.set(["custom.3": ["Dip"]], forKey: key)

        _ = try TemplateDefaultsMigration.run(in: context, defaults: defaults)

        #expect(try templates(in: context).first?.name == "Day 4")
    }

    // MARK: - Idempotency and failure

    @Test func existingSlotsAreKeptAndNotDuplicated() throws {
        let context = makeContext()
        let defaults = try makeTestDefaults()
        try WorkoutTemplateService.save(
            [TemplateExerciseSpec(exerciseId: "dip")], for: .ppl, dayIndex: 0, context: context
        )
        defaults.set(["ppl.0": ["Back Squat"], "ppl.1": ["Pull-Up"]], forKey: key)

        let first = try TemplateDefaultsMigration.run(in: context, defaults: defaults)
        #expect(first.migrated == 1)
        #expect(first.skippedExisting == 1)

        defaults.set(["ppl.0": ["Back Squat"], "ppl.1": ["Pull-Up"]], forKey: key)
        let second = try TemplateDefaultsMigration.run(in: context, defaults: defaults)
        #expect(second.migrated == 0)
        #expect(second.skippedExisting == 2)

        #expect(try templates(in: context).count == 2)
        #expect(try WorkoutTemplateService.plan(for: .ppl, dayIndex: 0, context: context)
            .map(\.exerciseId) == ["dip"])
    }

    @Test func failedSaveKeepsTheKeyAndInsertsNothing() throws {
        let context = makeContext()
        let defaults = try makeTestDefaults()
        let stored = ["ppl.0": ["Back Squat"]]
        defaults.set(stored, forKey: key)

        #expect(throws: SaveFailure.self) {
            try TemplateDefaultsMigration.run(in: context, defaults: defaults, save: { _ in throw SaveFailure() })
        }

        #expect(defaults.dictionary(forKey: key) as? [String: [String]] == stored)
        #expect(try templates(in: context).isEmpty)

        let retry = try TemplateDefaultsMigration.run(in: context, defaults: defaults)
        #expect(retry.migrated == 1)
        #expect(retry.removedKey)
    }
}
