//
//  SmartPrefillTests.swift
//  VoraTests
//
//  Created by Majd Arow on 2026-11-02.
//

import Foundation
import SwiftData
import Testing
@testable import Vora

@MainActor
struct SmartPrefillTests {
    private static let now = Date(timeIntervalSinceReferenceDate: 815_780_000)
    private static let smart = ProgressionContext(mode: .repsFirst, inventory: .standard(units: .metric))

    private let container: ModelContainer
    private let directory: URL
    private var context: ModelContext { container.mainContext }

    init() throws {
        container = try PersistenceController.makeContainer(inMemory: true)
        directory = FileManager.default.temporaryDirectory
            .appending(path: "SmartPrefillTests-\(UUID().uuidString)")
    }

    private func date(daysAgo: Int) throws -> Date {
        try #require(Calendar.current.date(byAdding: .day, value: -daysAgo, to: Self.now))
    }

    private func seed(
        exerciseId: String? = "barbell-bench-press",
        name: String = "Barbell Bench Press",
        weight: Double,
        reps: [Int],
        rir: Int? = 2,
        daysAgo: Int = 3,
        targets: TemplateTargets? = nil
    ) throws {
        let session = WorkoutSession(date: try date(daysAgo: daysAgo), sessionName: "Seeded")
        context.insert(session)
        let log = ExerciseLog(exerciseName: name, exerciseId: exerciseId, orderIndex: 0, targets: targets)
        session.exercises.append(log)
        for (index, count) in reps.enumerated() {
            log.sets.append(SetEntry(setNumber: index + 1, weightKg: weight, reps: count, isCompleted: true, rir: rir))
        }
        try context.save()
    }

    private func viewModel(slot: TemplateSlot? = nil, draftStore: SessionDraftStore? = nil) -> ActiveSessionViewModel {
        ActiveSessionViewModel(
            sessionName: "Push",
            templateSlot: slot,
            draftStore: draftStore,
            draftDebounce: .seconds(3600),
            health: NoHealthWrites(),
            now: { Self.now }
        )
    }

    private func bench(sets: Int = 3, repRangeMin: Int = 8, repRangeMax: Int = 12) -> TemplateExerciseSpec {
        TemplateExerciseSpec(exerciseId: "barbell-bench-press", targetSets: sets, repRangeMin: repRangeMin, repRangeMax: repRangeMax, targetRIR: 2)
    }

    private func complete(_ vm: ActiveSessionViewModel, set index: Int, reps: Int, rir: Int? = 2) {
        let exercise = vm.exercises[0]
        vm.exercises[0].sets[index].repsText = String(reps)
        _ = vm.toggleCompletion(setID: exercise.sets[index].id, in: exercise.id)
        if let rir { vm.setRIR(rir, setID: exercise.sets[index].id, in: exercise.id) }
    }

    // MARK: - Prefill

    @Test func smartPrefillTakesTheEngineWeightAndLeavesRepsEmpty() throws {
        try seed(weight: 100, reps: [12, 12, 12])
        let vm = viewModel()
        vm.prefill(with: [bench()], context: context, progression: Self.smart)

        let sets = vm.exercises[0].sets
        #expect(sets.map(\.weightKg) == [102.5, 102.5, 102.5])
        #expect(sets.allSatisfy { $0.repsText.isEmpty })
        #expect(sets.first?.activeRecommendation?.targetReps == 8)
        #expect(sets.first?.activeRecommendation?.reason == .raiseLoad(fromKg: 100, toKg: 102.5, topReps: 12))
        #expect(vm.exercises[0].previousSets.map(\.weightKg) == [100, 100, 100])
    }

    @Test func previousValuesModeCopiesLastWeights() throws {
        try seed(weight: 100, reps: [12, 12, 12])
        let vm = viewModel()
        vm.prefill(with: [bench()], context: context)

        #expect(vm.exercises[0].sets.map(\.weightKg) == [100, 100, 100])
        #expect(vm.exercises[0].sets.allSatisfy { $0.recommendation == nil })
    }

    @Test func noHistoryKeepsThePlainPrefill() throws {
        let vm = viewModel()
        vm.prefill(with: [bench()], context: context, progression: Self.smart)

        #expect(vm.exercises[0].sets.count == 3)
        #expect(vm.exercises[0].sets.allSatisfy { $0.weightKg == nil && $0.recommendation == nil })
        #expect(vm.exercises[0].predictedE1RMKg == nil)
    }

    @Test func customExercisesProgressRepsFromTheirOwnHistory() throws {
        try seed(exerciseId: nil, name: "Sled Push", weight: 55, reps: [10, 10, 10])
        let vm = viewModel()
        vm.prefill(with: [TemplateExerciseSpec(exerciseId: nil, customName: "Sled Push")], context: context, progression: Self.smart)

        #expect(vm.exercises[0].sets.first?.weightKg == 55)
        #expect(vm.exercises[0].sets.first?.activeRecommendation?.targetReps == 11)
    }

    @Test func aLongGapComesFromTheSessionDate() throws {
        try seed(weight: 100, reps: [12, 12, 12], daysAgo: 22)
        let vm = viewModel()
        vm.prefill(with: [bench()], context: context, progression: Self.smart)

        #expect(vm.exercises[0].sets.first?.weightKg == 100)
        #expect(vm.exercises[0].sets.first?.recommendation?.reason == .welcomeBack(days: 22))
    }

    @Test func exactly21DaysAgoStillProgresses() throws {
        try seed(weight: 100, reps: [12, 12, 12], daysAgo: 21)
        let vm = viewModel()
        vm.prefill(with: [bench()], context: context, progression: Self.smart)

        #expect(vm.exercises[0].sets.first?.weightKg == 102.5)
    }

    @Test func usesTheSessionsOwnSnapshot() throws {
        let heavy = TemplateTargets(targetSets: 3, repRangeMin: 3, repRangeMax: 5, targetRIR: 2)
        try seed(weight: 100, reps: [5, 5, 5], targets: heavy)
        let vm = viewModel()
        vm.prefill(with: [bench()], context: context, progression: Self.smart)

        #expect(vm.exercises[0].sets.first?.weightKg == 92.5)
        #expect(vm.exercises[0].sets.first?.recommendation?.targetReps == 8)
    }

    @Test func fetchesOnlyTheRecentSessionsNewestFirst() throws {
        for daysAgo in 1...7 {
            try seed(weight: Double(100 + daysAgo), reps: [10], daysAgo: daysAgo)
        }
        let history = ActiveSessionViewModel.recentHistory(
            exerciseId: "barbell-bench-press",
            name: "Barbell Bench Press",
            limit: 3,
            context: context
        )
        #expect(history.map { $0.sets.first?.weightKg } == [101, 102, 103])
    }

    // MARK: - Editing

    @Test func aTypedWeightHidesTheRecommendation() throws {
        try seed(weight: 100, reps: [12, 12, 12])
        let vm = viewModel()
        vm.prefill(with: [bench()], context: context, progression: Self.smart)

        vm.exercises[0].sets[0].weightText = "90"
        #expect(vm.exercises[0].sets[0].activeRecommendation == nil)
        #expect(vm.exercises[0].sets[1].activeRecommendation != nil)
    }

    @Test func addedSetCopiesTheWeightWithoutTheRecommendation() throws {
        try seed(weight: 100, reps: [12, 12, 12])
        let vm = viewModel()
        vm.prefill(with: [bench()], context: context, progression: Self.smart)
        vm.addSet(to: vm.exercises[0].id)

        #expect(vm.exercises[0].sets.last?.weightKg == 102.5)
        #expect(vm.exercises[0].sets.last?.recommendation == nil)
    }

    // MARK: - Retarget

    @Test func aWeakFirstSetRetargetsTheRest() throws {
        try seed(weight: 100, reps: [10, 10, 10])
        let vm = viewModel()
        vm.prefill(with: [bench()], context: context, progression: Self.smart)

        complete(vm, set: 0, reps: 5)

        let sets = vm.exercises[0].sets
        #expect(sets[1].weightKg.map { $0 < 100 } == true)
        #expect(sets[2].weightKg == sets[1].weightKg)
        if case .retargeted = sets[1].recommendation?.reason {} else {
            Issue.record("Expected a retarget reason")
        }
    }

    @Test func undoingTheFirstSetRestoresThePlan() throws {
        try seed(weight: 100, reps: [10, 10, 10])
        let vm = viewModel()
        vm.prefill(with: [bench()], context: context, progression: Self.smart)
        let planned = vm.exercises[0].sets[1].recommendation

        complete(vm, set: 0, reps: 5)
        #expect(vm.exercises[0].sets[1].recommendation != planned)
        _ = vm.toggleCompletion(setID: vm.exercises[0].sets[0].id, in: vm.exercises[0].id)

        #expect(vm.exercises[0].sets[1].recommendation == planned)
        #expect(vm.exercises[0].sets[1].weightKg == 100)
    }

    @Test func aTypedWeightIsNotRetargeted() throws {
        try seed(weight: 100, reps: [10, 10, 10])
        let vm = viewModel()
        vm.prefill(with: [bench()], context: context, progression: Self.smart)
        vm.exercises[0].sets[1].weightText = "95"

        complete(vm, set: 0, reps: 5)

        #expect(vm.exercises[0].sets[1].weightKg == 95)
        #expect(vm.exercises[0].sets[2].weightKg != 100)
    }

    @Test func rirOnTheFirstSetCanTriggerARetarget() throws {
        try seed(weight: 100, reps: [10, 10, 10])
        let vm = viewModel()
        vm.prefill(with: [bench()], context: context, progression: Self.smart)

        // 8 reps assuming 2 RIR is within the threshold; at failure it isn't.
        complete(vm, set: 0, reps: 8, rir: nil)
        #expect(vm.exercises[0].sets[1].weightKg == 100)
        let exercise = vm.exercises[0]
        vm.setRIR(0, setID: exercise.sets[0].id, in: exercise.id)
        #expect(vm.exercises[0].sets[1].weightKg.map { $0 < 100 } == true)
    }

    @Test func noRetargetInPreviousValuesMode() throws {
        try seed(weight: 100, reps: [10, 10, 10])
        let vm = viewModel()
        vm.prefill(with: [bench()], context: context)

        complete(vm, set: 0, reps: 2)
        #expect(vm.exercises[0].sets[1].weightKg == 100)
    }

    // MARK: - Fixes

    private func dumbbellSpec() -> TemplateExerciseSpec {
        TemplateExerciseSpec(exerciseId: "lateral-raise", targetSets: 2, repRangeMin: 8, repRangeMax: 12, targetRIR: 2)
    }

    private func warnedDumbbellSession(slot: TemplateSlot? = nil) throws -> ActiveSessionViewModel {
        try seed(exerciseId: "lateral-raise", name: "Lateral Raise", weight: 10, reps: [12, 12])
        let vm = viewModel(slot: slot)
        vm.prefill(with: [dumbbellSpec()], context: context, progression: Self.smart)
        return vm
    }

    @Test func aBigJumpWarnsOnTheNextSet() throws {
        let vm = try warnedDumbbellSession()
        let warned = try #require(vm.exercises[0].activeWarningRecommendation)
        #expect(warned.fixes.contains(.extendReps(toReps: 13)))
    }

    @Test func extendRepsLastsTheSessionAndClearsTheWarning() throws {
        let vm = try warnedDumbbellSession()
        vm.applyFix(.extendReps(toReps: 13), exerciseID: vm.exercises[0].id, context: context)

        #expect(vm.exercises[0].activeWarningRecommendation == nil)
        #expect(vm.exercises[0].sets.first?.activeRecommendation?.targetReps == 13)
        #expect(vm.exercises[0].targets?.repRangeMax == 12)
    }

    @Test func widenRangeUpdatesTheSessionWithoutRebaselining() throws {
        let vm = try warnedDumbbellSession()
        vm.applyFix(.widenRange(min: 8, max: 18), exerciseID: vm.exercises[0].id, context: context)

        #expect(vm.exercises[0].targets?.repRange == 8...18)
        #expect(vm.exercises[0].sets.first?.weightKg == 10)
        #expect(vm.exercises[0].sets.first?.activeRecommendation?.targetReps == 13)
        #expect(vm.exercises[0].activeWarningRecommendation == nil)
    }

    @Test func widenRangeSavesToASavedTemplate() throws {
        try WorkoutTemplateService.save([dumbbellSpec()], for: .ppl, dayIndex: 0, context: context)
        let vm = try warnedDumbbellSession(slot: TemplateSlot(split: .ppl, dayIndex: 0))
        vm.applyFix(.widenRange(min: 8, max: 18), exerciseID: vm.exercises[0].id, context: context)

        let plan = try WorkoutTemplateService.plan(for: .ppl, dayIndex: 0, context: context)
        #expect(plan.first?.repRangeMax == 18)
        #expect(vm.templateSaveFailed == false)
    }

    @Test func widenRangeSavesADefaultDayAsATemplate() throws {
        // Monday's default PPL day has lateral-raise in it.
        #expect(try WorkoutTemplateService.isCustomized(for: .ppl, dayIndex: 0, context: context) == false)
        let vm = try warnedDumbbellSession(slot: TemplateSlot(split: .ppl, dayIndex: 0))
        vm.applyFix(.widenRange(min: 8, max: 18), exerciseID: vm.exercises[0].id, context: context)

        let plan = try WorkoutTemplateService.plan(for: .ppl, dayIndex: 0, context: context)
        #expect(plan.first { $0.exerciseId == "lateral-raise" }?.repRangeMax == 18)
        #expect(plan.first { $0.exerciseId == "barbell-bench-press" }?.repRangeMax == TemplateExerciseSpec.defaultRepRange.upperBound)
    }

    @Test func widenRangeWithoutASlotOnlyChangesTheSession() throws {
        let vm = try warnedDumbbellSession()
        vm.applyFix(.widenRange(min: 8, max: 18), exerciseID: vm.exercises[0].id, context: context)
        #expect(try WorkoutTemplateService.isCustomized(for: .ppl, dayIndex: 0, context: context) == false)
    }

    @Test func aFailedTemplateSaveIsReportedAndTheSessionKeepsTheRange() throws {
        struct SaveFailed: Error {}
        let vm = try warnedDumbbellSession(slot: TemplateSlot(split: .ppl, dayIndex: 0))
        vm.applyFix(
            .widenRange(min: 8, max: 18),
            exerciseID: vm.exercises[0].id,
            context: context,
            saveTemplate: { _, _, _, _ in throw SaveFailed() }
        )
        #expect(vm.templateSaveFailed)
        #expect(vm.exercises[0].targets?.repRange == 8...18)
    }

    // MARK: - Logged weights

    private func pushdown() -> TemplateExerciseSpec {
        TemplateExerciseSpec(exerciseId: "triceps-pushdown", targetSets: 3, repRangeMin: 8, repRangeMax: 12, targetRIR: 2)
    }

    private func seedPushdown(weight: Double, reps: [Int], daysAgo: Int) throws {
        try seed(exerciseId: "triceps-pushdown", name: "Triceps Pushdown", weight: weight, reps: reps, daysAgo: daysAgo)
    }

    @Test func anOffGridWeightFromHistoryIsNotSnapped() throws {
        try seedPushdown(weight: 27.5, reps: [10, 10, 10], daysAgo: 3)
        let vm = viewModel()
        vm.prefill(with: [pushdown()], context: context, progression: Self.smart)

        #expect(vm.exercises[0].sets.map(\.weightKg) == [27.5, 27.5, 27.5])
        #expect(vm.exercises[0].activeWarningRecommendation == nil)
    }

    @Test func loggedWeightsReachBeyondTheRecentSessions() throws {
        // 28.75 is older than the three sessions the rules read.
        try seedPushdown(weight: 28.75, reps: [8, 8, 8], daysAgo: 20)
        for daysAgo in 1...4 {
            try seedPushdown(weight: 27.5, reps: [12, 12, 12], daysAgo: daysAgo)
        }
        let vm = viewModel()
        vm.prefill(with: [pushdown()], context: context, progression: Self.smart)

        #expect(vm.exercises[0].sets.first?.weightKg == 28.75)
    }

    @Test func plateLoadedExercisesDoNotReadLoggedWeights() throws {
        try seed(weight: 100, reps: [12, 12, 12])
        let vm = viewModel()
        vm.prefill(with: [bench()], context: context, progression: Self.smart)
        #expect(vm.exercises[0].loggedLoadsKg.isEmpty)
    }

    @Test func loggedWeightsComeBackAfterAKill() throws {
        defer { removeTestItem(at: directory) }
        try seedPushdown(weight: 27.5, reps: [10, 10, 10], daysAgo: 3)
        let store = SessionDraftStore(directory: directory, now: { Self.now })
        let vm = viewModel(draftStore: store)
        vm.prefill(with: [pushdown()], context: context, progression: Self.smart)
        vm.flushDraft()

        let draft = try #require(store.loadResumable())
        let resumed = viewModel()
        resumed.restore(from: draft, context: context, progression: Self.smart)
        #expect(resumed.exercises[0].loggedLoadsKg == [27.5, 27.5, 27.5])
    }

    // MARK: - Finish

    @Test func finishWritesTheTargetSnapshot() throws {
        let vm = viewModel()
        vm.prefill(with: [bench(repRangeMin: 6, repRangeMax: 10)], context: context)
        vm.exercises[0].sets[0].weightText = "100"
        complete(vm, set: 0, reps: 8)
        vm.finish(context: context)

        let log = try #require(try context.fetch(FetchDescriptor<ExerciseLog>()).first)
        #expect(log.targetSnapshot == TemplateTargets(targetSets: 3, repRangeMin: 6, repRangeMax: 10, targetRIR: 2))
    }

    @Test func aWidenedRangeIsWhatGetsSnapshotted() throws {
        let vm = try warnedDumbbellSession()
        let id = vm.exercises[0].id
        vm.applyFix(.widenRange(min: 8, max: 18), exerciseID: id, context: context)
        complete(vm, set: 0, reps: 13)
        vm.finish(context: context)

        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>(sortBy: [SortDescriptor(\.date, order: .reverse)]))
        #expect(sessions.first?.exercises.first?.repRangeMax == 18)
    }

    @Test func exercisesAddedMidSessionHaveNoSnapshot() throws {
        let vm = viewModel()
        vm.addExercise(name: "Barbell Bench Press", muscleGroups: [], context: context)
        vm.exercises[0].sets[0].weightText = "100"
        complete(vm, set: 0, reps: 8)
        vm.finish(context: context)

        let log = try #require(try context.fetch(FetchDescriptor<ExerciseLog>()).first)
        #expect(log.targetSnapshot == nil)
        #expect(log.repRangeMin == nil)
    }

    @Test func aSnapshotWithoutTargetRIRStillReads() {
        let log = ExerciseLog(
            exerciseName: "x",
            orderIndex: 0,
            targets: TemplateTargets(targetSets: 3, repRangeMin: 8, repRangeMax: 12, targetRIR: nil)
        )
        #expect(log.targetSnapshot?.targetRIR == nil)
        #expect(log.targetSnapshot?.repRangeMin == 8)
    }

    // MARK: - Draft

    @Test func recommendationsSurviveAKill() throws {
        defer { removeTestItem(at: directory) }
        try seed(weight: 100, reps: [10, 10, 10])
        let store = SessionDraftStore(directory: directory, now: { Self.now })
        let vm = viewModel(slot: TemplateSlot(split: .ppl, dayIndex: 0), draftStore: store)
        vm.prefill(with: [bench()], context: context, progression: Self.smart)
        complete(vm, set: 0, reps: 5)
        vm.flushDraft()

        let draft = try #require(store.loadResumable())
        #expect(draft.version == 3)
        #expect(draft.templateSlot == TemplateSlot(split: .ppl, dayIndex: 0))

        let resumed = viewModel()
        resumed.restore(from: draft, context: context, progression: Self.smart)
        #expect(resumed.exercises[0].sets[1].recommendation == vm.exercises[0].sets[1].recommendation)
        #expect(resumed.exercises[0].sets[1].plannedRecommendation == vm.exercises[0].sets[1].plannedRecommendation)
        #expect(resumed.exercises[0].sets[1].activeRecommendation != nil)
        #expect(resumed.exercises[0].predictedE1RMKg == vm.exercises[0].predictedE1RMKg)
        #expect(resumed.snapshot().templateSlot == draft.templateSlot)

        // Undoing set 1 after the resume still goes back to the plan.
        _ = resumed.toggleCompletion(setID: resumed.exercises[0].sets[0].id, in: resumed.exercises[0].id)
        #expect(resumed.exercises[0].sets[1].weightKg == 100)
    }

    /// `Fixtures/v2-session-draft.json` was written by the shipped code
    /// (commit ec4b816): a template bench press with one completed set at
    /// RIR 1 and two empty ones, then a custom Sled Push. `savedAt` and
    /// `startDate` are both 815,780,000.
    @Test func realV2DraftResumesWithoutRecommendations() throws {
        defer { removeTestItem(at: directory) }
        let bundle = Bundle(for: BundleToken.self)
        let source = try #require(bundle.url(forResource: "v2-session-draft", withExtension: "json"))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: directory.appending(path: SessionDraftStore.fileName))

        let store = SessionDraftStore(directory: directory, now: { Self.now })
        let draft = try #require(store.loadResumable())
        #expect(draft.version == 2)
        #expect(draft.templateSlot == nil)
        #expect(draft.exercises[0].sets[0] == ActiveSessionDraft.Set(weightKg: 102.25, reps: 8, isCompleted: true, rir: 1))
        #expect(draft.exercises[0].targets == TemplateTargets(targetSets: 3, repRangeMin: 6, repRangeMax: 10, targetRIR: 2))
        #expect(draft.exercises[1].customName == "Sled Push")
        let setAside = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix("ActiveSessionDraft.corrupt-") }
        #expect(setAside.isEmpty)

        let vm = viewModel(draftStore: store)
        vm.restore(from: draft, context: context, progression: Self.smart)
        #expect(vm.exercises[0].sets[0].rir == 1)
        #expect(vm.exercises[0].sets.allSatisfy { $0.recommendation == nil })
        #expect(vm.snapshot().version == ActiveSessionDraft.currentVersion)
    }
}

private final class BundleToken {}
