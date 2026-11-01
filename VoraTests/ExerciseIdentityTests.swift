//
//  ExerciseIdentityTests.swift
//  VoraTests
//
//  Created by Majd Arow on 2026-11-01.
//

import Foundation
import SwiftData
import Testing
@testable import Vora

// MARK: - Library IDs

struct ExerciseLibraryIDTests {
    /// Every shipped ID. Changing or removing one orphans users' history,
    /// so this list may only ever grow.
    private static let shippedIDs: Set<String> = [
        "barbell-bench-press", "incline-barbell-press", "dumbbell-bench-press",
        "incline-dumbbell-press", "dumbbell-fly", "cable-crossover", "machine-chest-press",
        "push-up", "dip", "deadlift", "barbell-row", "t-bar-row", "dumbbell-row", "pull-up",
        "chin-up", "lat-pulldown", "seated-cable-row", "face-pull", "machine-row",
        "overhead-press", "dumbbell-shoulder-press", "arnold-press", "lateral-raise",
        "front-raise", "rear-delt-fly", "cable-lateral-raise", "machine-shoulder-press",
        "barbell-curl", "preacher-curl", "dumbbell-curl", "hammer-curl",
        "incline-dumbbell-curl", "cable-curl", "close-grip-bench-press", "skull-crusher",
        "overhead-triceps-extension", "triceps-kickback", "triceps-pushdown", "bench-dip",
        "back-squat", "front-squat", "bulgarian-split-squat", "walking-lunge", "goblet-squat",
        "leg-press", "leg-extension", "hack-squat", "romanian-deadlift", "good-morning",
        "lying-leg-curl", "seated-leg-curl", "nordic-curl", "hip-thrust", "glute-bridge",
        "cable-kickback", "hip-abduction", "kettlebell-swing", "standing-calf-raise",
        "seated-calf-raise", "single-leg-calf-raise", "plank", "crunch", "hanging-leg-raise",
        "ab-wheel-rollout", "cable-crunch", "russian-twist", "cable-fly", "leg-curl",
    ]

    @Test func everyExerciseHasAUniqueID() {
        let ids = ExerciseLibrary.all.map(\.id)
        #expect(ids.count == 68)
        #expect(Set(ids).count == ids.count)
    }

    @Test func idsAreLowercaseSlugs() throws {
        let slug = try Regex("^[a-z0-9]+(-[a-z0-9]+)*$")
        for id in ExerciseLibrary.all.map(\.id) {
            #expect(id.wholeMatch(of: slug) != nil, "\(id) is not a slug")
        }
    }

    @Test func shippedIDsNeverChange() {
        #expect(Set(ExerciseLibrary.all.map(\.id)).isSuperset(of: Self.shippedIDs))
    }

    @Test func lookupByID() {
        #expect(ExerciseLibrary.definition(id: "barbell-bench-press")?.name == "Barbell Bench Press")
        #expect(ExerciseLibrary.definition(id: "Barbell Bench Press") == nil)
    }

    @Test func legacyLookupByLowercasedName() {
        #expect(ExerciseLibrary.legacyDefinition(lowercasedName: "t-bar row")?.id == "t-bar-row")
        #expect(ExerciseLibrary.legacyDefinition(lowercasedName: "sled push") == nil)
        #expect(ExerciseLibrary.definition(named: "PUSH-UP")?.id == "push-up")
    }
}

// MARK: - Identity keys

struct ExerciseIdentityKeyTests {
    @Test func storedIDWinsOverName() {
        #expect(ExerciseIdentity.key(exerciseId: "barbell-bench-press", name: "Flat Bench (old)")
                == "barbell-bench-press")
    }

    @Test func nilIDWithLibraryNameResolvesToLibraryID() {
        #expect(ExerciseIdentity.key(exerciseId: nil, name: "barbell BENCH press") == "barbell-bench-press")
    }

    @Test func customNamesMatchCaseInsensitivelyButNeverLibraryIDs() {
        let lower = ExerciseIdentity.key(exerciseId: nil, name: "sled push")
        let upper = ExerciseIdentity.key(exerciseId: nil, name: "Sled Push")
        #expect(lower == upper)
        #expect(lower == "custom:sled push")
        #expect(ExerciseLibrary.definition(id: lower) == nil)
    }

    @Test func displayNameUsesCurrentLibraryName() {
        #expect(ExerciseIdentity.displayName(exerciseId: "barbell-bench-press", name: "Flat Bench (old)")
                == "Barbell Bench Press")
        #expect(ExerciseIdentity.displayName(exerciseId: nil, name: "barbell bench press")
                == "Barbell Bench Press")
        #expect(ExerciseIdentity.displayName(exerciseId: nil, name: "Sled Push") == "Sled Push")
    }
}

// MARK: - Backfill

@MainActor
struct ExerciseIDBackfillTests {
    /// Callers must keep the container alive for as long as they use its
    /// context.
    private func makeContainer() throws -> ModelContainer {
        try PersistenceController.makeContainer(inMemory: true)
    }

    @Test func fillsKnownNamesCaseInsensitivelyAndSkipsCustom() throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(ExerciseLog(exerciseName: "BARBELL ROW", orderIndex: 0))
        context.insert(ExerciseLog(exerciseName: "Sled Push", orderIndex: 1))
        try context.save()

        #expect(try ExerciseIDBackfill.run(in: context) == 1)

        let byName = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<ExerciseLog>())
            .map { ($0.exerciseName, $0.exerciseId) })
        #expect(byName["BARBELL ROW"] == .some("barbell-row"))
        #expect(byName["Sled Push"] == .some(nil))
    }

    @Test func neverOverwritesAnExistingID() throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(ExerciseLog(exerciseName: "Deadlift", exerciseId: "romanian-deadlift", orderIndex: 0))
        try context.save()

        #expect(try ExerciseIDBackfill.run(in: context) == 0)
        #expect(try context.fetch(FetchDescriptor<ExerciseLog>()).first?.exerciseId == "romanian-deadlift")
    }

    @Test func isIdempotent() throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(ExerciseLog(exerciseName: "Pull-Up", orderIndex: 0))
        try context.save()

        #expect(try ExerciseIDBackfill.run(in: context) == 1)
        #expect(try ExerciseIDBackfill.run(in: context) == 0)
    }
}

// MARK: - Matching on IDs

@MainActor
struct ExerciseIDMatchingTests {
    /// Callers must keep the container alive for as long as they use its
    /// context.
    private func makeContainer() throws -> ModelContainer {
        try PersistenceController.makeContainer(inMemory: true)
    }

    private func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_790_000_000 + Double(offset) * 86_400)
    }

    @discardableResult
    private func insertSession(
        _ context: ModelContext,
        day offset: Int,
        name: String,
        exerciseId: String?,
        sets: [(Double, Int, Bool)]
    ) -> WorkoutSession {
        let log = ExerciseLog(
            exerciseName: name,
            exerciseId: exerciseId,
            orderIndex: 0,
            sets: sets.enumerated().map {
                SetEntry(setNumber: $0.offset + 1, weightKg: $0.element.0, reps: $0.element.1, isCompleted: $0.element.2)
            }
        )
        let session = WorkoutSession(date: day(offset), sessionName: "S", exercises: [log])
        context.insert(session)
        return session
    }

    // Rename safety

    @Test func renamedRowsDrivePrefillForTheCurrentName() throws {
        let container = try makeContainer()
        let context = container.mainContext
        insertSession(context, day: 0, name: "Flat Bench (old)", exerciseId: "barbell-bench-press",
                      sets: [(90, 6, true), (87.5, 6, true)])
        try context.save()

        let previous = ActiveSessionViewModel.previousSets(
            exerciseId: "barbell-bench-press", name: "Barbell Bench Press", context: context
        )
        #expect(previous.map(\.weightKg) == [90, 87.5])
    }

    @Test func renamedAndLegacyRowsMergeIntoOnePRWithCurrentName() throws {
        let container = try makeContainer()
        let context = container.mainContext
        insertSession(context, day: 0, name: "barbell bench press", exerciseId: nil, sets: [(80, 8, true)])
        insertSession(context, day: 1, name: "Flat Bench (old)", exerciseId: "barbell-bench-press", sets: [(85, 5, true)])
        try context.save()

        let records = WorkoutHomeViewModel.computePersonalRecords(from: context)
        #expect(records.count == 1)
        #expect(records.first?.exerciseName == "Barbell Bench Press")
        #expect(records.first?.exerciseId == "barbell-bench-press")
        #expect(records.first?.weightKg == 85)
    }

    @Test func sessionStatsByKeyIncludeRenamedAndLegacyRows() throws {
        let container = try makeContainer()
        let context = container.mainContext
        insertSession(context, day: 0, name: "Barbell Bench Press", exerciseId: nil, sets: [(80, 8, true)])
        insertSession(context, day: 1, name: "Flat Bench (old)", exerciseId: "barbell-bench-press", sets: [(85, 5, true)])
        try context.save()
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())

        let stats = StrengthProgression.sessionStats(forKey: "barbell-bench-press", sessions: sessions)
        #expect(stats.map(\.bestWeightKg) == [80, 85])
        #expect(StrengthProgression.distinctExerciseNames(in: sessions) == ["Barbell Bench Press"])
    }

    // Nil-ID fallback

    @Test func customExercisesMatchByNameOnly() throws {
        let container = try makeContainer()
        let context = container.mainContext
        insertSession(context, day: 0, name: "sled push", exerciseId: nil, sets: [(40, 10, true)])
        insertSession(context, day: 1, name: "Leg Press", exerciseId: "leg-press", sets: [(50, 10, true)])
        try context.save()

        let custom = ActiveSessionViewModel.previousSets(exerciseId: nil, name: "Sled Push", context: context)
        #expect(custom.map(\.weightKg) == [40])

        let records = WorkoutHomeViewModel.computePersonalRecords(from: context)
        #expect(Set(records.map(\.id)) == ["custom:sled push", "leg-press"])
    }

    // Predicate-based previousSets

    @Test func previousSetsReturnsNewestCompletedSession() throws {
        let container = try makeContainer()
        let context = container.mainContext
        insertSession(context, day: 0, name: "Back Squat", exerciseId: "back-squat", sets: [(100, 5, true)])
        insertSession(context, day: 2, name: "Back Squat", exerciseId: "back-squat", sets: [(110, 5, true), (110, 4, false)])
        insertSession(context, day: 3, name: "Leg Press", exerciseId: "leg-press", sets: [(200, 10, true)])
        try context.save()

        let previous = ActiveSessionViewModel.previousSets(exerciseId: "back-squat", name: "Back Squat", context: context)
        #expect(previous.map(\.weightKg) == [110])
    }

    @Test func previousSetsSkipsSessionsWithoutCompletedSets() throws {
        let container = try makeContainer()
        let context = container.mainContext
        insertSession(context, day: 0, name: "Back Squat", exerciseId: "back-squat", sets: [(100, 5, true)])
        insertSession(context, day: 1, name: "Back Squat", exerciseId: "back-squat", sets: [(120, 5, false)])
        try context.save()

        let previous = ActiveSessionViewModel.previousSets(exerciseId: "back-squat", name: "Back Squat", context: context)
        #expect(previous.map(\.weightKg) == [100])
    }

    @Test func previousSetsPagesPastTheFirstFetch() throws {
        let container = try makeContainer()
        let context = container.mainContext
        insertSession(context, day: 0, name: "Back Squat", exerciseId: "back-squat", sets: [(95, 5, true)])
        // Newer custom-exercise sessions match the nil-ID clause of the
        // predicate but not the key, filling more than one page.
        for offset in 1...(ActiveSessionViewModel.historyPageSize * 2 + 1) {
            insertSession(context, day: offset, name: "Sled Push", exerciseId: nil, sets: [(50, 10, true)])
        }
        try context.save()

        let previous = ActiveSessionViewModel.previousSets(exerciseId: "back-squat", name: "Back Squat", context: context)
        #expect(previous.map(\.weightKg) == [95])
    }

    @Test func previousSetsEmptyWithoutHistory() throws {
        let container = try makeContainer()
        let context = container.mainContext
        #expect(ActiveSessionViewModel.previousSets(exerciseId: "plank", name: "Plank", context: context).isEmpty)
    }

    // Writing IDs

    @Test func finishSavesLibraryIDsAndNilForUnknownNames() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let viewModel = ActiveSessionViewModel(sessionName: "Push")
        viewModel.addExercise(name: "Overhead Press", muscleGroups: ["shoulders"], context: context)
        viewModel.addExercise(name: "Sled Push", muscleGroups: [], context: context)
        for index in viewModel.exercises.indices {
            viewModel.exercises[index].sets[0].weightText = "40"
            viewModel.exercises[index].sets[0].repsText = "8"
            viewModel.exercises[index].sets[0].isCompleted = true
        }

        viewModel.finish(context: context)

        let logs = try context.fetch(FetchDescriptor<ExerciseLog>(sortBy: [SortDescriptor(\.orderIndex)]))
        #expect(logs.map(\.exerciseId) == ["overhead-press", nil])
        #expect(viewModel.summary?.newPRs.map(\.id) == ["overhead-press", "custom:sled push"])
    }
}

// MARK: - Legacy aliases

@MainActor
struct ExerciseLegacyAliasTests {
    @Test func everyAliasPointsAtARealLibraryExercise() {
        for (alias, id) in ExerciseLibrary.legacyAliases {
            #expect(ExerciseLibrary.definition(id: id) != nil, "\(alias) -> \(id) has no library entry")
            #expect(alias == alias.lowercased())
        }
    }

    /// An alias that equals a current name would be dead code; one that
    /// collides with a current name for a different exercise would be wrong.
    @Test func aliasesNeverShadowCurrentNames() {
        for alias in ExerciseLibrary.legacyAliases.keys {
            #expect(ExerciseLibrary.definition(named: alias) == nil, "\(alias) is already a library name")
        }
    }

    @Test func aliasesResolveThroughLegacyLookup() {
        #expect(ExerciseLibrary.legacyDefinition(lowercasedName: "bench press")?.id == "barbell-bench-press")
        #expect(ExerciseLibrary.legacyDefinition(lowercasedName: "pull up")?.id == "pull-up")
        #expect(ExerciseLibrary.legacyDefinition(lowercasedName: "push up")?.id == "push-up")
    }

    @Test func ambiguousNamesAreNotAliased() {
        for name in ["bench", "squat", "curl", "row", "fly", "press"] {
            #expect(ExerciseLibrary.legacyDefinition(lowercasedName: name) == nil, "\(name) must stay custom")
        }
    }

    /// Aliases only resolve stored legacy rows. A name picked today must
    /// match the library exactly to get an ID.
    @Test func aliasesAreNotUsedForNewlyChosenNames() {
        #expect(ExerciseIdentity.libraryID(forName: "Bench Press") == nil)
        #expect(ExerciseIdentity.libraryID(forName: "Barbell Bench Press") == "barbell-bench-press")
    }

    @Test func backfillResolvesAliasesCaseInsensitively() throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let context = container.mainContext
        context.insert(ExerciseLog(exerciseName: "Bench Press", orderIndex: 0))
        context.insert(ExerciseLog(exerciseName: "PULL UP", orderIndex: 1))
        context.insert(ExerciseLog(exerciseName: "push up", orderIndex: 2))
        try context.save()

        #expect(try ExerciseIDBackfill.run(in: context) == 3)
        let ids = try context.fetch(FetchDescriptor<ExerciseLog>(sortBy: [SortDescriptor(\.orderIndex)]))
            .map(\.exerciseId)
        #expect(ids == ["barbell-bench-press", "pull-up", "push-up"])
    }

    @Test func aliasedLegacyRowsShareHistoryWithCurrentRows() throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let context = container.mainContext
        let old = ExerciseLog(exerciseName: "Bench Press", orderIndex: 0,
                              sets: [SetEntry(setNumber: 1, weightKg: 80, reps: 8, isCompleted: true)])
        context.insert(WorkoutSession(date: Date(timeIntervalSince1970: 1_790_000_000), sessionName: "Old", exercises: [old]))
        try context.save()

        let previous = ActiveSessionViewModel.previousSets(
            exerciseId: "barbell-bench-press", name: "Barbell Bench Press", context: context
        )
        #expect(previous.map(\.weightKg) == [80])
        #expect(WorkoutHomeViewModel.computePersonalRecords(from: context).map(\.exerciseName) == ["Barbell Bench Press"])
    }

    /// Every exercise name the demo seeder logs is an exact library name,
    /// so seeded history never contains custom exercises.
    @Test func demoSeedLogsOnlyLibraryExercises() throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        DemoSeeder.seed(into: container.mainContext)

        let logs = try container.mainContext.fetch(FetchDescriptor<ExerciseLog>())
        #expect(!logs.isEmpty)
        #expect(logs.allSatisfy { $0.exerciseId != nil }, "\(Set(logs.filter { $0.exerciseId == nil }.map(\.exerciseName)))")
    }
}
