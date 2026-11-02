//
//  ActiveSessionDraftTests.swift
//  VoraTests
//
//  Created by Majd Arow on 2026-11-01.
//

import Foundation
import SwiftData
import Testing
@testable import Vora

/// A clock the test moves by hand.
private final class TestClock {
    var now: Date
    init(_ now: Date) { self.now = now }
    func advance(by seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

@MainActor
struct ActiveSessionDraftTests {
    private let container: ModelContainer
    private let directory: URL
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    init() throws {
        container = try PersistenceController.makeContainer(inMemory: true)
        directory = FileManager.default.temporaryDirectory
            .appending(path: "ActiveSessionDraftTests-\(UUID().uuidString)")
    }

    private var context: ModelContext { container.mainContext }

    private func makeStore(_ clock: TestClock) -> SessionDraftStore {
        SessionDraftStore(directory: directory, now: { clock.now })
    }

    private func makeViewModel(
        _ clock: TestClock,
        units: UnitSystem = .metric,
        store: SessionDraftStore? = nil,
        debounce: Duration = .seconds(60)
    ) -> ActiveSessionViewModel {
        ActiveSessionViewModel(
            sessionName: "Push",
            units: units,
            draftStore: store,
            draftDebounce: debounce,
            health: NoHealthWrites(),
            now: { clock.now }
        )
    }

    private func enter(_ viewModel: ActiveSessionViewModel, exercise: Int, set: Int, weight: String, reps: String) {
        viewModel.exercises[exercise].sets[set].weightText = weight
        viewModel.exercises[exercise].sets[set].repsText = reps
    }

    private func complete(_ viewModel: ActiveSessionViewModel, exercise: Int, set: Int) {
        let draft = viewModel.exercises[exercise]
        _ = viewModel.toggleCompletion(setID: draft.sets[set].id, in: draft.id)
    }

    /// One template exercise with a completed set plus a custom exercise.
    private func populatedViewModel(_ clock: TestClock, units: UnitSystem = .metric) -> ActiveSessionViewModel {
        let viewModel = makeViewModel(clock, units: units)
        viewModel.prefill(
            with: [TemplateExerciseSpec(exerciseId: "back-squat", targetSets: 2, repRangeMin: 5, repRangeMax: 8, targetRIR: 1, restSeconds: 180)],
            context: context
        )
        viewModel.addExercise(name: "Sled Push", muscleGroups: ["legs"], context: context)
        enter(viewModel, exercise: 0, set: 0, weight: "102.25", reps: "5")
        complete(viewModel, exercise: 0, set: 0)
        enter(viewModel, exercise: 1, set: 0, weight: "40", reps: "")
        return viewModel
    }

    // MARK: - Snapshot and restore

    @Test func snapshotRestoreReproducesTheSession() throws {
        let clock = TestClock(start)
        let original = populatedViewModel(clock)
        clock.advance(by: 60)
        let draft = original.snapshot()

        let restored = makeViewModel(clock)
        restored.restore(from: draft, context: context)

        #expect(restored.startDate == start)
        #expect(restored.exercises.count == 2)
        let squat = restored.exercises[0]
        #expect(squat.exerciseId == "back-squat")
        #expect(squat.name == original.exercises[0].name)
        #expect(squat.restSeconds == 180)
        #expect(squat.targets == TemplateTargets(targetSets: 2, repRangeMin: 5, repRangeMax: 8, targetRIR: 1))
        #expect(squat.repRange == 5...8)
        #expect(squat.sets.count == 2)
        #expect(squat.sets[0].weightKg == 102.25)
        #expect(squat.sets[0].reps == 5)
        #expect(squat.sets[0].isCompleted)
        #expect(!squat.sets[1].isCompleted)

        let sled = restored.exercises[1]
        #expect(sled.exerciseId == nil)
        #expect(sled.name == "Sled Push")
        #expect(sled.muscleGroups == ["legs"])
        #expect(sled.targets == nil)
        #expect(sled.sets[0].weightText == "40")
        #expect(sled.sets[0].repsText.isEmpty)
        #expect(restored.totalVolumeKg == original.totalVolumeKg)
    }

    @Test func snapshotStoresCustomNameOnlyForCustomExercises() {
        let draft = populatedViewModel(TestClock(start)).snapshot()
        #expect(draft.exercises[0].customName == nil)
        #expect(draft.exercises[1].customName == "Sled Push")
    }

    @Test func restoreShowsKilogramsInTheCurrentUnits() throws {
        let clock = TestClock(start)
        let original = makeViewModel(clock, units: .imperial)
        original.addExercise(name: "Bench Press", muscleGroups: ["chest"], context: context)
        enter(original, exercise: 0, set: 0, weight: "225", reps: "5")
        let draft = original.snapshot()
        let savedKg = try #require(draft.exercises[0].sets[0].weightKg)
        #expect(abs(savedKg - UnitConversion.kg(fromPounds: 225)) < 1e-9)

        let imperial = makeViewModel(clock, units: .imperial)
        imperial.restore(from: draft, context: context)
        #expect(imperial.exercises[0].sets[0].weightText == "225")
        #expect(imperial.exercises[0].sets[0].weightKg == savedKg)

        let metric = makeViewModel(clock, units: .metric)
        metric.restore(from: draft, context: context)
        #expect(metric.exercises[0].sets[0].weightText == "102.06")
        #expect(metric.exercises[0].sets[0].weightKg == savedKg)
    }

    // MARK: - Rest timer

    @Test func restoreDropsARestThatAlreadyEnded() {
        let clock = TestClock(start)
        let original = populatedViewModel(clock)
        original.startRest(duration: 90)
        let draft = original.snapshot()

        clock.advance(by: 91)
        let restored = makeViewModel(clock)
        restored.restore(from: draft, context: context)
        #expect(restored.restEndDate == nil)
    }

    @Test func restoreResumesARestStillRunning() {
        let clock = TestClock(start)
        let original = populatedViewModel(clock)
        original.startRest(duration: 90)
        let draft = original.snapshot()

        clock.advance(by: 30)
        let restored = makeViewModel(clock)
        restored.restore(from: draft, context: context)
        #expect(restored.restEndDate == start.addingTimeInterval(90))
    }

    // MARK: - Interruption gap

    @Test func longInterruptionIsExcludedFromDuration() throws {
        let clock = TestClock(start)
        let original = populatedViewModel(clock)
        clock.advance(by: 600)
        let draft = original.snapshot()

        clock.advance(by: 2 * 60 * 60)
        let restored = makeViewModel(clock)
        restored.restore(from: draft, context: context)
        #expect(restored.elapsedSeconds == 600)

        clock.advance(by: 300)
        #expect(restored.elapsedSeconds == 900)
        restored.finish(context: context)

        #expect(restored.summary?.durationSeconds == 900)
        let interval = try #require(restored.workoutInterval)
        #expect(interval.start == start)
        #expect(interval.end == start.addingTimeInterval(900))
        let saved = try #require(try context.fetch(FetchDescriptor<WorkoutSession>()).first)
        #expect(saved.durationSeconds == 900)
        #expect(saved.date == start)
    }

    @Test func shortInterruptionCountsAsContinuous() throws {
        let clock = TestClock(start)
        let original = populatedViewModel(clock)
        clock.advance(by: 600)
        let draft = original.snapshot()

        clock.advance(by: 120)
        let restored = makeViewModel(clock)
        restored.restore(from: draft, context: context)
        #expect(restored.elapsedSeconds == 720)

        restored.finish(context: context)
        let interval = try #require(restored.workoutInterval)
        #expect(restored.summary?.durationSeconds == 720)
        #expect(interval.end == start.addingTimeInterval(720))
    }

    @Test func repeatedInterruptionsAccumulate() {
        let clock = TestClock(start)
        let first = populatedViewModel(clock)
        clock.advance(by: 600)
        let firstDraft = first.snapshot()

        clock.advance(by: 3600)
        let second = makeViewModel(clock)
        second.restore(from: firstDraft, context: context)
        clock.advance(by: 300)
        let secondDraft = second.snapshot()

        clock.advance(by: 1800)
        let third = makeViewModel(clock)
        third.restore(from: secondDraft, context: context)
        #expect(third.elapsedSeconds == 900)
    }

    // MARK: - Autosave

    @Test func flushDraftWritesImmediately() throws {
        defer { removeTestItem(at: directory) }
        let clock = TestClock(start)
        let store = makeStore(clock)
        let viewModel = makeViewModel(clock, store: store)
        viewModel.addExercise(name: "Bench Press", muscleGroups: ["chest"], context: context)
        #expect(!FileManager.default.fileExists(atPath: store.fileURL.path))

        viewModel.flushDraft()
        let draft = try #require(store.loadResumable())
        #expect(draft.exercises.count == 1)
    }

    @Test func autosaveIsDebouncedAndWritesTheLatestState() async throws {
        defer { removeTestItem(at: directory) }
        let clock = TestClock(start)
        let store = makeStore(clock)
        let viewModel = makeViewModel(clock, store: store, debounce: .milliseconds(50))
        viewModel.addExercise(name: "Bench Press", muscleGroups: ["chest"], context: context)
        let superseded = try #require(viewModel.pendingDraftSave)
        for reps in 1...5 {
            viewModel.exercises[0].sets[0].repsText = String(reps)
        }
        // The save tasks share this test's main actor, so none can have run yet.
        #expect(!FileManager.default.fileExists(atPath: store.fileURL.path))
        #expect(superseded.isCancelled)

        let latest = try #require(viewModel.pendingDraftSave)
        #expect(!latest.isCancelled)
        await latest.value

        #expect(viewModel.pendingDraftSave == nil)
        let draft = try #require(store.loadResumable())
        #expect(draft.exercises[0].sets[0].reps == 5)
    }

    @Test func finishClearsTheDraft() throws {
        defer { removeTestItem(at: directory) }
        let clock = TestClock(start)
        let store = makeStore(clock)
        let viewModel = makeViewModel(clock, store: store)
        viewModel.addExercise(name: "Bench Press", muscleGroups: ["chest"], context: context)
        enter(viewModel, exercise: 0, set: 0, weight: "100", reps: "5")
        complete(viewModel, exercise: 0, set: 0)
        viewModel.flushDraft()
        #expect(FileManager.default.fileExists(atPath: store.fileURL.path))

        viewModel.finish(context: context)
        #expect(!FileManager.default.fileExists(atPath: store.fileURL.path))
        // Later writes (e.g. a background flush) must not recreate it.
        viewModel.flushDraft()
        #expect(!FileManager.default.fileExists(atPath: store.fileURL.path))
    }

    @Test func failedSaveKeepsTheDraft() throws {
        struct SaveFailure: Error {}
        defer { removeTestItem(at: directory) }
        let clock = TestClock(start)
        let store = makeStore(clock)
        let viewModel = makeViewModel(clock, store: store)
        viewModel.addExercise(name: "Bench Press", muscleGroups: ["chest"], context: context)
        enter(viewModel, exercise: 0, set: 0, weight: "100", reps: "5")
        complete(viewModel, exercise: 0, set: 0)
        viewModel.flushDraft()

        viewModel.finish(context: context, save: { _ in throw SaveFailure() })

        let draft = try #require(store.loadResumable())
        #expect(draft.exercises[0].sets[0].isCompleted)
    }

    @Test func discardClearsTheDraftAndStopsAutosave() async throws {
        defer { removeTestItem(at: directory) }
        let clock = TestClock(start)
        let store = makeStore(clock)
        let viewModel = makeViewModel(clock, store: store, debounce: .milliseconds(50))
        viewModel.addExercise(name: "Bench Press", muscleGroups: ["chest"], context: context)
        viewModel.flushDraft()
        #expect(FileManager.default.fileExists(atPath: store.fileURL.path))

        viewModel.discardDraft()
        viewModel.exercises[0].sets[0].repsText = "8"
        try await Task.sleep(for: .milliseconds(300))
        #expect(!FileManager.default.fileExists(atPath: store.fileURL.path))
    }
}
