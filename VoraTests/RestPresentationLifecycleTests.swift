//
//  RestPresentationLifecycleTests.swift
//  VoraTests
//
//  Created by Majd Arow on 2026-11-03.
//

import Foundation
import SwiftData
import Testing
@testable import Vora

private final class Clock {
    var now: Date
    init(_ now: Date) { self.now = now }
    func advance(by seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

private struct SaveFailed: Error {}

struct RestPresentationLifecycleTests {
    private static let start = Date(timeIntervalSinceReferenceDate: 815_780_000)

    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }
    private let clock = Clock(Self.start)
    private let activity = RecordingRestActivity()
    private let alert = RecordingRestAlert()

    init() throws {
        container = try PersistenceController.makeContainer(inMemory: true)
    }

    private func viewModel(
        units: UnitSystem = .metric,
        store: SessionDraftStore? = nil,
        activity: RecordingRestActivity? = nil,
        alert: RecordingRestAlert? = nil
    ) -> ActiveSessionViewModel {
        let clock = clock
        return ActiveSessionViewModel(
            sessionName: "Push",
            units: units,
            draftStore: store,
            draftDebounce: .seconds(60),
            health: NoHealthWrites(),
            restActivity: activity ?? self.activity,
            restAlert: alert ?? self.alert,
            now: { clock.now }
        )
    }

    private func set(_ weight: Double, _ reps: Int, type: SetType = .normal, done: Bool = false) -> ActiveSessionViewModel.DraftSet {
        var set = ActiveSessionViewModel.DraftSet()
        set.setWeight(kg: weight)
        set.repsText = String(reps)
        set.setType = type
        set.isCompleted = done
        return set
    }

    private func exercise(
        _ name: String,
        _ sets: [ActiveSessionViewModel.DraftSet],
        group: Int? = nil
    ) -> ActiveSessionViewModel.DraftExercise {
        ActiveSessionViewModel.DraftExercise(
            name: name,
            exerciseId: nil,
            muscleGroups: [],
            sets: sets,
            previousSets: [],
            restSeconds: 90,
            supersetGroup: group
        )
    }

    /// Bench with one set done and one to go.
    private func benchSession(store: SessionDraftStore? = nil) -> ActiveSessionViewModel {
        let vm = viewModel(store: store)
        vm.exercises = [exercise("Bench", [set(80, 8, done: true), set(80, 8)])]
        return vm
    }

    private func restAfterFirstSet(_ vm: ActiveSessionViewModel) {
        vm.startRestIfDue(afterCompleting: vm.exercises[0].sets[0].id, in: vm.exercises[0].id)
    }

    private func temporaryStore() -> SessionDraftStore {
        let clock = clock
        return SessionDraftStore(
            directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString),
            now: { clock.now }
        )
    }

    // MARK: - Start and update

    @Test func aStartingRestShowsTheActivityAndSchedulesTheAlert() throws {
        let vm = benchSession()
        restAfterFirstSet(vm)

        let end = Self.start.addingTimeInterval(90)
        let state = RestActivityAttributes.ContentState(
            exerciseName: "Bench",
            nextSetText: "80 kg × 8",
            startDate: Self.start,
            endDate: end
        )
        #expect(activity.calls == [.show(state)])
        #expect(alert.calls == [.schedule(end, "Bench: 80 kg × 8")])
    }

    @Test func noRestMeansNothingIsShown() {
        let vm = benchSession()
        vm.exercises[0].sets[1].repsText = "9"
        vm.cancelRest()
        #expect(activity.calls.isEmpty)
        #expect(alert.calls.isEmpty)
    }

    @Test func addingTimeUpdatesAndReschedules() {
        let vm = benchSession()
        restAfterFirstSet(vm)
        vm.adjustRest(by: 15)

        let end = Self.start.addingTimeInterval(105)
        #expect(vm.restEndDate == end)
        #expect(activity.shown.map(\.endDate) == [Self.start.addingTimeInterval(90), end])
        #expect(activity.shown.last?.startDate == Self.start)
        #expect(alert.calls.last == .schedule(end, "Bench: 80 kg × 8"))
        #expect(!activity.calls.contains(.end))
    }

    @Test func takingOffTimeUpdatesAndReschedules() {
        let vm = benchSession()
        restAfterFirstSet(vm)
        vm.adjustRest(by: -15)

        let end = Self.start.addingTimeInterval(75)
        #expect(activity.shown.last?.endDate == end)
        #expect(alert.calls.last == .schedule(end, "Bench: 80 kg × 8"))
    }

    @Test func takingOffAllTheTimeEndsTheRest() {
        let vm = benchSession()
        restAfterFirstSet(vm)
        vm.adjustRest(by: -90)

        #expect(vm.restEndDate == nil)
        #expect(activity.calls.last == .end)
        #expect(alert.calls.last == .cancel)
    }

    @Test func adjustingWithoutARestDoesNothing() {
        let vm = benchSession()
        vm.adjustRest(by: 15)
        #expect(vm.restEndDate == nil)
        #expect(activity.calls.isEmpty)
    }

    @Test func aNewRestUpdatesTheSameActivity() {
        let vm = benchSession()
        restAfterFirstSet(vm)
        clock.advance(by: 30)
        restAfterFirstSet(vm)

        let end = Self.start.addingTimeInterval(120)
        #expect(activity.shown.count == 2)
        #expect(activity.shown.last?.startDate == Self.start.addingTimeInterval(30))
        #expect(activity.shown.last?.endDate == end)
        // Never ended in between, so there is one activity throughout.
        #expect(!activity.calls.contains(.end))
    }

    @Test func editingTheNextSetUpdatesItsText() {
        let vm = benchSession()
        restAfterFirstSet(vm)
        vm.exercises[0].sets[1].weightText = "85"

        #expect(activity.shown.last?.nextSetText == "85 kg × 8")
        #expect(alert.calls.last == .schedule(Self.start.addingTimeInterval(90), "Bench: 85 kg × 8"))
    }

    @Test func unrelatedEditsSendNothing() {
        let vm = benchSession()
        vm.exercises.append(exercise("Row", [set(60, 10)]))
        restAfterFirstSet(vm)
        let activityCalls = activity.calls.count
        let alertCalls = alert.calls.count

        vm.exercises[1].sets[0].repsText = "12"
        vm.exercises[0].sets[0].rir = 2

        #expect(activity.calls.count == activityCalls)
        #expect(alert.calls.count == alertCalls)
    }

    // MARK: - End

    @Test func skippingEndsAndCancels() {
        let vm = benchSession()
        restAfterFirstSet(vm)
        vm.cancelRest()

        #expect(activity.calls.last == .end)
        #expect(alert.calls.last == .cancel)
    }

    @Test func endingTwiceOnlyEndsOnce() {
        let vm = benchSession()
        restAfterFirstSet(vm)
        vm.cancelRest()
        vm.cancelRest()

        #expect(activity.calls.filter { $0 == .end }.count == 1)
        #expect(alert.calls.filter { $0 == .cancel }.count == 1)
    }

    @Test func anExpiredRestEndsWhenTheAppBecomesActive() {
        let vm = benchSession()
        restAfterFirstSet(vm)
        clock.advance(by: 90)
        vm.reconcileRest()

        #expect(vm.restEndDate == nil)
        #expect(activity.calls.last == .end)
        #expect(alert.calls.last == .cancel)
    }

    @Test func aRunningRestSurvivesBecomingActive() {
        let vm = benchSession()
        restAfterFirstSet(vm)
        clock.advance(by: 89)
        vm.reconcileRest()

        #expect(vm.restEndDate != nil)
        #expect(!activity.calls.contains(.end))
        #expect(!alert.calls.contains(.cancel))
    }

    @Test func finishingEndsAndCancels() {
        let vm = benchSession()
        restAfterFirstSet(vm)
        vm.finish(context: context)

        #expect(vm.savedSessionID != nil)
        #expect(vm.restEndDate == nil)
        #expect(activity.calls.last == .end)
        #expect(alert.calls.last == .cancel)
    }

    /// The session screen goes away with the summary, so nothing would be
    /// left to end the activity. The draft stays, so the work isn't lost.
    @Test func aFailedFinishStillEndsTheRestAndKeepsTheDraft() throws {
        let store = temporaryStore()
        let vm = benchSession(store: store)
        restAfterFirstSet(vm)
        vm.flushDraft()
        vm.finish(context: context, save: { _ in throw SaveFailed() })

        #expect(vm.savedSessionID == nil)
        #expect(vm.restEndDate == nil)
        #expect(activity.calls.last == .end)
        #expect(alert.calls.last == .cancel)
        #expect(store.loadResumable() != nil)
    }

    @Test func discardingEndsAndCancels() {
        let vm = benchSession()
        restAfterFirstSet(vm)
        vm.discardDraft()

        #expect(vm.restEndDate == nil)
        #expect(activity.calls.last == .end)
        #expect(alert.calls.last == .cancel)
    }

    @Test func terminationEndsTheActivityButKeepsTheDraftAndAlert() throws {
        let store = temporaryStore()
        let vm = benchSession(store: store)
        restAfterFirstSet(vm)
        vm.prepareForTermination()

        #expect(activity.calls.last == .endAllBeforeTermination)
        #expect(!alert.calls.contains(.cancel))
        let draft = try #require(store.loadResumable())
        #expect(draft.restEndDate == Self.start.addingTimeInterval(90))
    }

    // MARK: - Resume

    private func killedDraft() -> ActiveSessionDraft {
        let original = viewModel(activity: RecordingRestActivity(), alert: RecordingRestAlert())
        original.exercises = [exercise("Bench", [set(80, 8, done: true), set(80, 8)])]
        restAfterFirstSet(original)
        return original.snapshot()
    }

    @Test func resumingARunningRestRecreatesTheActivity() {
        let draft = killedDraft()
        clock.advance(by: 30)
        let restored = viewModel()
        restored.restore(from: draft, context: context)

        let end = Self.start.addingTimeInterval(90)
        #expect(restored.restEndDate == end)
        #expect(activity.shown.count == 1)
        #expect(activity.shown.last?.startDate == Self.start.addingTimeInterval(30))
        #expect(activity.shown.last?.endDate == end)
        #expect(alert.calls.last.map { if case let .schedule(date, _) = $0 { date == end } else { false } } == true)
    }

    @Test func resumingAnExpiredRestShowsNothing() {
        let draft = killedDraft()
        clock.advance(by: 91)
        let restored = viewModel()
        restored.restore(from: draft, context: context)

        #expect(restored.restEndDate == nil)
        #expect(activity.calls.isEmpty)
        #expect(alert.calls.isEmpty)
    }

    /// The exercise rested after isn't in the draft; the last one with a
    /// completed set stands in, so an earlier skipped set doesn't show.
    @Test func aResumedRestStillKnowsWhereYouAre() {
        let original = viewModel(activity: RecordingRestActivity(), alert: RecordingRestAlert())
        original.exercises = [
            exercise("Bench", [set(80, 8)]),
            exercise("Row", [set(60, 10, done: true), set(60, 10)]),
        ]
        original.startRest(duration: 90)
        let draft = original.snapshot()

        let restored = viewModel()
        restored.restore(from: draft, context: context)
        #expect(activity.shown.last?.exerciseName == "Row")
    }

    // MARK: - Prompt 11 rest rules

    private func started(_ vm: ActiveSessionViewModel, exercise e: Int, set s: Int) -> Bool {
        let before = activity.shown.count
        vm.cancelRest()
        vm.startRestIfDue(afterCompleting: vm.exercises[e].sets[s].id, in: vm.exercises[e].id)
        return activity.shown.count > before
    }

    @Test func aWarmUpStartsNoActivity() {
        let vm = viewModel()
        vm.exercises = [exercise("Bench", [set(40, 5, type: .warmUp, done: true), set(80, 8)])]
        #expect(!started(vm, exercise: 0, set: 0))
        #expect(alert.calls.isEmpty)
    }

    @Test(arguments: [SetType.drop, .myoRep])
    func aSetThatFollowsImmediatelyStartsNoActivity(next: SetType) {
        let vm = viewModel()
        vm.exercises = [exercise("Bench", [set(80, 8, done: true), set(60, 8, type: next)])]
        #expect(!started(vm, exercise: 0, set: 0))
        #expect(alert.calls.isEmpty)
    }

    @Test func midSupersetStartsNoActivityAndTheRoundsEndDoes() {
        let vm = viewModel()
        vm.exercises = [
            exercise("Bench", [set(80, 8, done: true), set(80, 8)], group: 1),
            exercise("Row", [set(60, 10), set(60, 10)], group: 1),
        ]
        #expect(!started(vm, exercise: 0, set: 0))

        vm.exercises[1].sets[0].isCompleted = true
        vm.exercises[1].sets[1].isCompleted = true
        #expect(started(vm, exercise: 1, set: 1))
        #expect(activity.shown.last?.exerciseName == "Bench")
    }
}
