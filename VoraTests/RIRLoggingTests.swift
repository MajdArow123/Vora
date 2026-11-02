//
//  RIRLoggingTests.swift
//  VoraTests
//
//  Created by Majd Arow on 2026-11-02.
//

import Foundation
import SwiftData
import Testing
@testable import Vora

@MainActor
struct RIRScaleTests {
    @Test func rangeMatchesTemplateTargets() {
        #expect(RIRScale.range == TemplateExerciseSpec.Limits.rir)
        #expect(RIRScale.range == 0...5)
    }

    @Test func topOfTheScaleReadsAsOrMore() {
        #expect(RIRScale.text(0) == "0")
        #expect(RIRScale.text(4) == "4")
        #expect(RIRScale.text(5) == "5+")
    }

    @Test func spokenTextCoversEveryKind() {
        #expect(RIRScale.spokenText(0) == "failure")
        #expect(RIRScale.spokenText(1) == "1 rep in reserve")
        #expect(RIRScale.spokenText(3) == "3 reps in reserve")
        #expect(RIRScale.spokenText(5) == "5 or more reps in reserve")
    }

    @Test func validationKeepsOnlyValuesOnTheScale() {
        #expect(RIRScale.validated(0) == 0)
        #expect(RIRScale.validated(5) == 5)
        #expect(RIRScale.validated(nil) == nil)
        #expect(RIRScale.validated(-1) == nil)
        #expect(RIRScale.validated(6) == nil)
    }
}

@MainActor
struct RIRSavePathTests {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    init() throws {
        container = try PersistenceController.makeContainer(inMemory: true)
    }

    private func makeViewModel(targetRIR: Int? = 2, sets: Int = 3) -> ActiveSessionViewModel {
        let viewModel = ActiveSessionViewModel(sessionName: "Push", health: NoHealthWrites())
        viewModel.prefill(
            with: [TemplateExerciseSpec(exerciseId: "back-squat", targetSets: sets, targetRIR: targetRIR)],
            context: context
        )
        for index in viewModel.exercises[0].sets.indices {
            viewModel.exercises[0].sets[index].weightText = "100"
            viewModel.exercises[0].sets[index].repsText = "5"
        }
        return viewModel
    }

    private func complete(_ viewModel: ActiveSessionViewModel, set: Int) {
        let exercise = viewModel.exercises[0]
        #expect(viewModel.toggleCompletion(setID: exercise.sets[set].id, in: exercise.id))
    }

    private func setRIR(_ viewModel: ActiveSessionViewModel, set: Int, _ rir: Int?) {
        let exercise = viewModel.exercises[0]
        viewModel.setRIR(rir, setID: exercise.sets[set].id, in: exercise.id)
    }

    private func savedRIRs() throws -> [Int?] {
        try context.fetch(FetchDescriptor<SetEntry>(sortBy: [SortDescriptor(\.setNumber)])).map(\.rir)
    }

    @Test func pickedValuesSaveIncludingFailureAndTopOfScale() throws {
        let viewModel = makeViewModel()
        for (set, rir) in [0, 3, 5].enumerated() {
            setRIR(viewModel, set: set, rir)
            complete(viewModel, set: set)
        }

        viewModel.finish(context: context)

        #expect(try savedRIRs() == [0, 3, 5])
    }

    /// The target is a placeholder, not a logged value.
    @Test func untouchedPickerSavesNilEvenWithATarget() throws {
        let viewModel = makeViewModel(targetRIR: 2, sets: 1)
        complete(viewModel, set: 0)
        #expect(viewModel.exercises[0].targets?.targetRIR == 2)
        #expect(viewModel.exercises[0].sets[0].rir == nil)

        viewModel.finish(context: context)

        #expect(try savedRIRs() == [nil])
    }

    @Test func rirCanBeSetAfterCompleting() throws {
        let viewModel = makeViewModel(sets: 1)
        complete(viewModel, set: 0)
        setRIR(viewModel, set: 0, 1)

        viewModel.finish(context: context)

        #expect(try savedRIRs() == [1])
    }

    @Test func rirCanBeCleared() throws {
        let viewModel = makeViewModel(sets: 1)
        setRIR(viewModel, set: 0, 1)
        setRIR(viewModel, set: 0, nil)
        complete(viewModel, set: 0)

        viewModel.finish(context: context)

        #expect(try savedRIRs() == [nil])
    }

    @Test func incompleteSetsAreNotSavedWithTheirRIR() throws {
        let viewModel = makeViewModel(sets: 2)
        setRIR(viewModel, set: 0, 1)
        setRIR(viewModel, set: 1, 4)
        complete(viewModel, set: 0)

        viewModel.finish(context: context)

        #expect(try savedRIRs() == [1])
    }

    @Test func addSetDoesNotCopyRIR() {
        let viewModel = makeViewModel(sets: 1)
        setRIR(viewModel, set: 0, 1)

        viewModel.addSet(to: viewModel.exercises[0].id)

        #expect(viewModel.exercises[0].sets[1].rir == nil)
        #expect(viewModel.exercises[0].sets[1].repsText == "5")
    }

    @Test func offScaleValuesAreIgnored() {
        let viewModel = makeViewModel(sets: 1)
        setRIR(viewModel, set: 0, 2)
        setRIR(viewModel, set: 0, 6)
        #expect(viewModel.exercises[0].sets[0].rir == 2)
        setRIR(viewModel, set: 0, -1)
        #expect(viewModel.exercises[0].sets[0].rir == 2)
    }

    @Test func uncompletingKeepsTheRIR() {
        let viewModel = makeViewModel(sets: 1)
        setRIR(viewModel, set: 0, 2)
        complete(viewModel, set: 0)
        let exercise = viewModel.exercises[0]
        #expect(!viewModel.toggleCompletion(setID: exercise.sets[0].id, in: exercise.id))
        #expect(viewModel.exercises[0].sets[0].rir == 2)
    }

    @Test func historyCarriesRIR() throws {
        let viewModel = makeViewModel(sets: 2)
        setRIR(viewModel, set: 0, 2)
        complete(viewModel, set: 0)
        complete(viewModel, set: 1)
        viewModel.finish(context: context)

        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let key = ExerciseIdentity.key(exerciseId: "back-squat", name: "Back Squat")
        let stats = StrengthProgression.sessionStats(forKey: key, sessions: sessions)

        let sets = try #require(stats.first?.sets)
        #expect(sets.map(\.rir) == [2, nil])
    }
}

// MARK: - Draft

@MainActor
struct RIRDraftTests {
    private final class Clock {
        var now: Date
        init(_ now: Date) { self.now = now }
    }

    private final class BundleToken {}

    private let container: ModelContainer
    private let directory: URL
    private var context: ModelContext { container.mainContext }

    /// When `Fixtures/v1-session-draft.json` says it was saved.
    private let fixtureSavedAt = Date(timeIntervalSinceReferenceDate: 815_693_400)

    init() throws {
        container = try PersistenceController.makeContainer(inMemory: true)
        directory = FileManager.default.temporaryDirectory
            .appending(path: "RIRDraftTests-\(UUID().uuidString)")
    }

    private func installV1Fixture() throws {
        let bundle = Bundle(for: BundleToken.self)
        let source = try #require(bundle.url(forResource: "v1-session-draft", withExtension: "json"))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: source,
            to: directory.appending(path: SessionDraftStore.fileName)
        )
    }

    private func setAsideCount() throws -> Int {
        try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix("ActiveSessionDraft.corrupt-") }
            .count
    }

    /// `Fixtures/v1-session-draft.json` was written by the shipped code
    /// (commit 07190d1): a template bench press with one completed set and
    /// two empty ones, then a custom Sled Push.
    @Test func realV1DraftLoadsWithoutBeingSetAside() throws {
        defer { removeTestItem(at: directory) }
        try installV1Fixture()
        let store = SessionDraftStore(directory: directory, now: { [fixtureSavedAt] in fixtureSavedAt.addingTimeInterval(60) })

        let draft = try #require(store.loadResumable())

        #expect(draft.version == 1)
        #expect(try setAsideCount() == 0)
        #expect(draft.sessionName == "Push")
        #expect(draft.exercises.map(\.exerciseId) == ["barbell-bench-press", nil])
        #expect(draft.exercises[1].customName == "Sled Push")
        #expect(draft.exercises[0].targets == TemplateTargets(targetSets: 3, repRangeMin: 6, repRangeMax: 10, targetRIR: 2))
        #expect(draft.exercises[0].sets == [
            ActiveSessionDraft.Set(weightKg: 102.25, reps: 8, isCompleted: true, rir: nil),
            ActiveSessionDraft.Set(weightKg: nil, reps: nil, isCompleted: false, rir: nil),
            ActiveSessionDraft.Set(weightKg: nil, reps: nil, isCompleted: false, rir: nil),
        ])
    }

    /// A workout in progress at upgrade resumes, finishes, and comes back
    /// from the next autosave as a current-version draft.
    @Test func realV1DraftResumesAndIsRewrittenAsCurrentVersion() throws {
        defer { removeTestItem(at: directory) }
        try installV1Fixture()
        let clock = Clock(fixtureSavedAt.addingTimeInterval(60))
        let store = SessionDraftStore(directory: directory, now: { clock.now })
        let draft = try #require(store.loadResumable())

        let viewModel = ActiveSessionViewModel(
            sessionName: draft.sessionName,
            draftStore: store,
            draftDebounce: .seconds(3600),
            health: NoHealthWrites(),
            now: { clock.now }
        )
        viewModel.restore(from: draft, context: context)
        #expect(viewModel.exercises[0].sets[0].weightKg == 102.25)
        #expect(viewModel.exercises[0].sets[0].isCompleted)
        #expect(viewModel.exercises[0].sets.allSatisfy { $0.rir == nil })

        let bench = viewModel.exercises[0]
        viewModel.setRIR(1, setID: bench.sets[0].id, in: bench.id)
        viewModel.flushDraft()

        let rewritten = try #require(store.loadResumable())
        #expect(rewritten.version == ActiveSessionDraft.currentVersion)
        #expect(rewritten.exercises[0].sets[0].rir == 1)

        viewModel.finish(context: context)
        let saved = try context.fetch(FetchDescriptor<SetEntry>())
        #expect(saved.map(\.rir) == [1])
    }

    @Test func versionsOutsideTheReadableRangeAreSetAside() throws {
        defer { removeTestItem(at: directory) }
        for version in [0, ActiveSessionDraft.currentVersion + 1] {
            let store = SessionDraftStore(directory: directory, now: { [fixtureSavedAt] in fixtureSavedAt })
            var draft = ActiveSessionDraft(
                sessionName: "Push",
                startDate: fixtureSavedAt,
                savedAt: fixtureSavedAt,
                restEndDate: nil,
                excludedSeconds: 0,
                exercises: [ActiveSessionDraft.Exercise(
                    exerciseId: nil, customName: "Sled Push", muscleGroups: [], restSeconds: 90, targets: nil,
                    sets: [ActiveSessionDraft.Set(weightKg: 40, reps: 20, isCompleted: false)]
                )]
            )
            draft.version = version
            try store.save(draft)
            #expect(store.loadResumable() == nil)
        }
        #expect(try setAsideCount() == 2)
    }

    @Test func snapshotAndRestoreRoundTripRIRIncludingZero() throws {
        defer { removeTestItem(at: directory) }
        let clock = Clock(fixtureSavedAt)
        let store = SessionDraftStore(directory: directory, now: { clock.now })
        let viewModel = ActiveSessionViewModel(
            sessionName: "Push", draftStore: store, draftDebounce: .seconds(3600),
            health: NoHealthWrites(), now: { clock.now }
        )
        viewModel.prefill(with: [TemplateExerciseSpec(exerciseId: "back-squat", targetSets: 3)], context: context)
        let exercise = viewModel.exercises[0]
        viewModel.setRIR(0, setID: exercise.sets[0].id, in: exercise.id)
        viewModel.setRIR(5, setID: exercise.sets[1].id, in: exercise.id)
        viewModel.flushDraft()

        let loaded = try #require(store.loadResumable())
        #expect(loaded.version == ActiveSessionDraft.currentVersion)
        #expect(loaded.exercises[0].sets.map(\.rir) == [0, 5, nil])

        let restored = ActiveSessionViewModel(sessionName: "Push", health: NoHealthWrites(), now: { clock.now })
        restored.restore(from: loaded, context: context)
        #expect(restored.exercises[0].sets.map(\.rir) == [0, 5, nil])
    }

    @Test func offScaleRIRInADraftRestoresAsNil() {
        let draft = ActiveSessionDraft(
            sessionName: "Push",
            startDate: fixtureSavedAt,
            savedAt: fixtureSavedAt,
            restEndDate: nil,
            excludedSeconds: 0,
            exercises: [ActiveSessionDraft.Exercise(
                exerciseId: nil, customName: "Sled Push", muscleGroups: [], restSeconds: 90, targets: nil,
                sets: [
                    ActiveSessionDraft.Set(weightKg: 40, reps: 20, isCompleted: false, rir: 9),
                    ActiveSessionDraft.Set(weightKg: 40, reps: 20, isCompleted: false, rir: -1),
                ]
            )]
        )
        let viewModel = ActiveSessionViewModel(
            sessionName: "Push", health: NoHealthWrites(), now: { [fixtureSavedAt] in fixtureSavedAt }
        )
        viewModel.restore(from: draft, context: context)

        #expect(viewModel.exercises[0].sets.map(\.rir) == [nil, nil])
    }
}
