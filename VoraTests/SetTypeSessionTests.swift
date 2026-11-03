//
//  SetTypeSessionTests.swift
//  VoraTests
//
//  Created by Majd Arow on 2026-11-02.
//

import Foundation
import SwiftData
import Testing
@testable import Vora

@MainActor
struct SetTypeSessionTests {
    private static let now = Date(timeIntervalSinceReferenceDate: 815_780_000)
    private nonisolated static let bench = "barbell-bench-press"
    private static let smart = ProgressionContext(mode: .repsFirst, inventory: .standard(units: .metric))
    private static let gym = LoadingInventory.standard(units: .metric)

    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    init() throws {
        container = try PersistenceController.makeContainer(inMemory: true)
    }

    private func seed(
        exerciseId: String? = Self.bench,
        name: String = "Barbell Bench Press",
        sets: [SetEntry],
        daysAgo: Int = 3
    ) throws {
        let date = try #require(Calendar.current.date(byAdding: .day, value: -daysAgo, to: Self.now))
        let session = WorkoutSession(date: date, sessionName: "Seeded")
        context.insert(session)
        let log = ExerciseLog(exerciseName: name, exerciseId: exerciseId, orderIndex: 0)
        session.exercises.append(log)
        log.sets.append(contentsOf: sets)
        try context.save()
    }

    private func entry(
        _ number: Int,
        _ weight: Double,
        _ reps: Int = 8,
        rir: Int? = nil,
        type: SetType = .normal
    ) -> SetEntry {
        SetEntry(setNumber: number, weightKg: weight, reps: reps, isCompleted: true, rir: rir, setType: type)
    }

    private func viewModel(warmUps: Bool = true) -> ActiveSessionViewModel {
        let vm = ActiveSessionViewModel(sessionName: "Push", health: NoHealthWrites(), now: { Self.now })
        vm.warmUpInventory = warmUps ? Self.gym : nil
        return vm
    }

    private func spec(_ id: String = Self.bench, sets: Int = 3) -> TemplateExerciseSpec {
        TemplateExerciseSpec(exerciseId: id, targetSets: sets, repRangeMin: 6, repRangeMax: 10, targetRIR: 2)
    }

    /// An exercise added by hand with the given set types, each at `weight` × 10.
    private func logged(_ vm: ActiveSessionViewModel, _ types: [SetType], weight: Double = 100) {
        vm.addExercise(name: "Barbell Bench Press", muscleGroups: ["chest"], context: context)
        let e = vm.exercises.count - 1
        vm.exercises[e].sets = types.map { type in
            var set = ActiveSessionViewModel.DraftSet()
            set.setWeight(kg: weight)
            set.repsText = "10"
            set.setType = type
            return set
        }
    }

    private func completeAll(_ vm: ActiveSessionViewModel) {
        for exercise in vm.exercises {
            for set in exercise.sets {
                _ = vm.toggleCompletion(setID: set.id, in: exercise.id)
            }
        }
    }

    // MARK: - Generation

    @Test func prefillPutsTheRampAboveWorkingSets() throws {
        try seed(sets: [entry(1, 100), entry(2, 100), entry(3, 100)])
        let vm = viewModel()
        vm.prefill(with: [spec()], context: context)

        let sets = try #require(vm.exercises.first).sets
        #expect(sets.map(\.setType) == [.warmUp, .warmUp, .warmUp, .warmUp, .normal, .normal, .normal])
        #expect(sets.prefix(4).map(\.weightKg) == [20, 50, 70, 85])
        #expect(sets.prefix(4).map(\.reps) == [10, 5, 3, 1])
        // Working sets stay unfilled, so logged numbers stay real.
        #expect(sets.suffix(3).allSatisfy { $0.repsText.isEmpty && $0.weightKg == 100 })
    }

    @Test func rampFollowsTheEnginesFirstWorkingWeight() throws {
        try seed(sets: [entry(1, 100, 10, rir: 2), entry(2, 100, 10, rir: 2), entry(3, 100, 10, rir: 2)])
        let vm = viewModel()
        vm.prefill(with: [spec()], context: context, progression: Self.smart)

        let sets = try #require(vm.exercises.first).sets
        let working = try #require(sets.first { $0.setType == .normal }?.weightKg)
        #expect(working > 100)
        #expect(sets.filter { $0.setType == .warmUp }.allSatisfy { ($0.weightKg ?? working) < working })
        #expect(sets.filter { $0.setType == .warmUp }.allSatisfy { $0.recommendation == nil })
    }

    @Test func settingOffGeneratesNone() throws {
        try seed(sets: [entry(1, 100)])
        let vm = viewModel(warmUps: false)
        vm.prefill(with: [spec()], context: context)
        #expect(vm.exercises[0].sets.allSatisfy { $0.setType == .normal })
        #expect(!vm.canAddWarmUps(to: vm.exercises[0].id))
    }

    @Test func isolationAndCustomGetNone() throws {
        try seed(exerciseId: "lateral-raise", name: "Lateral Raise", sets: [entry(1, 12)])
        try seed(exerciseId: nil, name: "Sled Push", sets: [entry(1, 100)])
        let vm = viewModel()
        vm.prefill(
            with: [spec("lateral-raise"), TemplateExerciseSpec(exerciseId: nil, customName: "Sled Push")],
            context: context
        )
        #expect(vm.exercises.count == 2)
        #expect(vm.exercises.allSatisfy { $0.sets.allSatisfy { $0.setType == .normal } })
    }

    @Test func noHistoryMeansNoRampUntilAWeightIsTyped() throws {
        let vm = viewModel()
        vm.prefill(with: [spec()], context: context)
        let id = vm.exercises[0].id
        #expect(vm.exercises[0].sets.count == 3)
        #expect(!vm.canAddWarmUps(to: id))

        vm.exercises[0].sets[0].weightText = "100"
        #expect(vm.canAddWarmUps(to: id))
        vm.addWarmUps(to: id)
        #expect(vm.exercises[0].sets.prefix(4).map(\.weightKg) == [20, 50, 70, 85])
        #expect(vm.exercises[0].sets.count == 7)
        #expect(!vm.canAddWarmUps(to: id))
    }

    @Test func deletedWarmUpsCanBeRebuiltFromTheCurrentWeight() throws {
        try seed(sets: [entry(1, 100)])
        let vm = viewModel()
        vm.prefill(with: [spec(sets: 1)], context: context)
        let id = vm.exercises[0].id
        for set in vm.exercises[0].sets where set.setType == .warmUp {
            vm.removeSet(set.id, from: id)
        }
        vm.exercises[0].sets[0].weightText = "60"
        #expect(vm.canAddWarmUps(to: id))
        vm.addWarmUps(to: id)
        #expect(vm.exercises[0].sets.prefix(4).map(\.weightKg) == [20, 30, 42.5, 50])
    }

    @Test func warmUpsDontFollowALaterWeightChange() throws {
        try seed(sets: [entry(1, 100)])
        let vm = viewModel()
        vm.prefill(with: [spec(sets: 1)], context: context)
        vm.exercises[0].sets[4].weightText = "60"
        #expect(vm.exercises[0].sets.prefix(4).map(\.weightKg) == [20, 50, 70, 85])
    }

    @Test func addedAndSwappedExercisesGetARamp() throws {
        try seed(sets: [entry(1, 100)])
        let vm = viewModel()
        vm.addExercise(name: "Barbell Bench Press", muscleGroups: ["chest"], context: context)
        #expect(vm.exercises[0].sets.count == 5)

        vm.addExercise(name: "Lateral Raise", muscleGroups: ["shoulders"], context: context)
        vm.replaceExercise(vm.exercises[1].id, withName: "Barbell Bench Press", muscleGroups: ["chest"], context: context)
        #expect(vm.exercises[1].sets.count == 5)
        #expect(vm.exercises[1].sets.first?.setType == .warmUp)
    }

    @Test func warmUpsAreEditableAndDeletable() throws {
        try seed(sets: [entry(1, 100)])
        let vm = viewModel()
        vm.prefill(with: [spec(sets: 1)], context: context)
        let id = vm.exercises[0].id
        vm.exercises[0].sets[0].weightText = "25"
        vm.exercises[0].sets[0].repsText = "12"
        #expect(vm.exercises[0].sets[0].weightKg == 25)
        #expect(vm.exercises[0].sets[0].reps == 12)
        vm.removeSet(vm.exercises[0].sets[0].id, from: id)
        #expect(vm.exercises[0].sets.count == 4)
    }

    // MARK: - Changing type

    @Test func changingToWarmUpMovesTheSetAboveWorkingSets() {
        let vm = viewModel(warmUps: false)
        logged(vm, [.warmUp, .normal, .normal, .normal])
        let id = vm.exercises[0].id
        let last = vm.exercises[0].sets[3].id
        vm.setType(.warmUp, setID: last, in: id)
        #expect(vm.exercises[0].sets.map(\.setType) == [.warmUp, .warmUp, .normal, .normal])
        #expect(vm.exercises[0].sets[1].id == last)
    }

    @Test func leavingWarmUpMovesTheSetToTheFirstWorkingPlace() {
        let vm = viewModel(warmUps: false)
        logged(vm, [.warmUp, .warmUp, .normal])
        let id = vm.exercises[0].id
        let first = vm.exercises[0].sets[0].id
        vm.setType(.normal, setID: first, in: id)
        #expect(vm.exercises[0].sets.map(\.setType) == [.warmUp, .normal, .normal])
        #expect(vm.exercises[0].sets[1].id == first)
    }

    @Test func otherChangesKeepTheOrder() {
        let vm = viewModel(warmUps: false)
        logged(vm, [.normal, .normal, .normal])
        let id = vm.exercises[0].id
        let middle = vm.exercises[0].sets[1].id
        vm.setType(.drop, setID: middle, in: id)
        #expect(vm.exercises[0].sets[1].id == middle)
        #expect(vm.exercises[0].sets[1].setType == .drop)
    }

    @Test func recommendationHidesOnOtherTypesAndComesBack() {
        let vm = viewModel(warmUps: false)
        logged(vm, [.normal])
        let id = vm.exercises[0].id
        let set = vm.exercises[0].sets[0].id
        vm.exercises[0].sets[0].recommendation = Recommendation(weightKg: 100, targetReps: 8, reason: .repeatTop(topReps: 8))
        #expect(vm.exercises[0].sets[0].activeRecommendation != nil)
        vm.setType(.drop, setID: set, in: id)
        #expect(vm.exercises[0].sets[0].activeRecommendation == nil)
        vm.setType(.failure, setID: set, in: id)
        #expect(vm.exercises[0].sets[0].activeRecommendation != nil)
    }

    @Test func sideIsSetAndCleared() {
        let vm = viewModel(warmUps: false)
        logged(vm, [.normal])
        let id = vm.exercises[0].id
        let set = vm.exercises[0].sets[0].id
        vm.setSide(.left, setID: set, in: id)
        #expect(vm.exercises[0].sets[0].side == .left)
        vm.setSide(nil, setID: set, in: id)
        #expect(vm.exercises[0].sets[0].side == nil)
    }

    @Test func addedSetIsNormalWithNoSide() {
        let vm = viewModel(warmUps: false)
        logged(vm, [.drop])
        vm.exercises[0].sets[0].side = .left
        vm.addSet(to: vm.exercises[0].id)
        #expect(vm.exercises[0].sets[1].setType == .normal)
        #expect(vm.exercises[0].sets[1].side == nil)
    }

    // MARK: - Working-set alignment

    @Test func previousLinesUpWithWorkingSets() throws {
        try seed(sets: [
            entry(1, 40, 10, type: .warmUp),
            entry(2, 100, 8),
            entry(3, 90, 7),
            entry(4, 60, 12, type: .drop),
        ])
        let vm = viewModel()
        vm.prefill(with: [spec()], context: context)
        let exercise = vm.exercises[0]
        #expect(exercise.previousSets.map(\.weightKg) == [100, 90])
        let firstWorking = try #require(exercise.sets.firstIndex { $0.setType == .normal })
        #expect(exercise.previousSet(at: 0) == nil)
        #expect(exercise.previousSet(at: firstWorking)?.weightKg == 100)
        #expect(exercise.previousSet(at: firstWorking + 1)?.weightKg == 90)
        #expect(exercise.previousSet(at: firstWorking + 2) == nil)
    }

    @Test func historyHoldsWorkingSetsWithImpliedRIR() throws {
        try seed(sets: [
            entry(1, 40, 10, type: .warmUp),
            entry(2, 100, 8, rir: 1),
            entry(3, 100, 6, type: .failure),
            entry(4, 100, 6, rir: 1, type: .failure),
            entry(5, 60, 12, type: .drop),
            entry(6, 60, 5, type: .myoRep),
        ])
        let history = ActiveSessionViewModel.recentHistory(
            exerciseId: Self.bench, name: "Barbell Bench Press", limit: 1, context: context
        )
        #expect(history.first?.sets == [
            ProgressionSet(weightKg: 100, reps: 8, rir: 1),
            ProgressionSet(weightKg: 100, reps: 6, rir: 0),
            ProgressionSet(weightKg: 100, reps: 6, rir: 1),
        ])
    }

    @Test func aSessionWithNoWorkingSetsIsNotHistory() throws {
        try seed(sets: [entry(1, 100)], daysAgo: 5)
        try seed(sets: [entry(1, 40, type: .warmUp), entry(2, 30, type: .drop)], daysAgo: 1)
        let history = ActiveSessionViewModel.recentHistory(
            exerciseId: Self.bench, name: "Barbell Bench Press", limit: 3, context: context
        )
        #expect(history.count == 1)
        #expect(history.first?.sets.map(\.weightKg) == [100])
    }

    @Test func everyLiftedWeightStaysLoadable() throws {
        try seed(sets: [entry(1, 52, type: .warmUp), entry(2, 100)])
        let history = ActiveSessionViewModel.recentHistory(
            exerciseId: Self.bench, name: "Barbell Bench Press", limit: .max, includingAllSetTypes: true, context: context
        )
        #expect(history.first?.sets.map(\.weightKg) == [52, 100])
    }

    private func retargetSession() throws -> ActiveSessionViewModel {
        try seed(sets: [entry(1, 100, 8, rir: 2), entry(2, 100, 8, rir: 2), entry(3, 100, 8, rir: 2)])
        let vm = viewModel()
        vm.prefill(with: [spec()], context: context, progression: Self.smart)
        return vm
    }

    @Test func aWarmUpNeverRetargets() throws {
        let vm = try retargetSession()
        let before = vm.exercises[0].sets.filter(\.setType.isWorkingSet).map(\.recommendation)
        let warmUp = vm.exercises[0].sets[0]
        vm.exercises[0].sets[0].repsText = "50"
        _ = vm.toggleCompletion(setID: warmUp.id, in: vm.exercises[0].id)
        #expect(vm.exercises[0].sets.filter(\.setType.isWorkingSet).map(\.recommendation) == before)
    }

    @Test func theFirstWorkingSetRetargetsThoseAfterIt() throws {
        let vm = try retargetSession()
        let first = try #require(vm.exercises[0].sets.firstIndex { $0.setType == .normal })
        let id = vm.exercises[0].sets[first].id
        vm.exercises[0].sets[first].repsText = "2"
        _ = vm.toggleCompletion(setID: id, in: vm.exercises[0].id)

        let later = vm.exercises[0].sets[(first + 1)...]
        #expect(!later.isEmpty)
        for set in later {
            guard case .retargeted = set.recommendation?.reason else {
                Issue.record("Not retargeted: \(String(describing: set.recommendation))")
                continue
            }
        }
        #expect(vm.exercises[0].sets[..<first].allSatisfy { $0.recommendation == nil })
    }

    private func isRetargeted(_ set: ActiveSessionViewModel.DraftSet) -> Bool {
        if case .retargeted = set.recommendation?.reason { return true }
        return false
    }

    /// 6 reps with the assumed RIR 2 is close to the prediction; 6 reps to
    /// failure is far enough below it to retarget.
    @Test func impliedRIRReachesTheRetarget() throws {
        let vm = try retargetSession()
        let first = try #require(vm.exercises[0].sets.firstIndex { $0.setType == .normal })
        let id = vm.exercises[0].sets[first].id
        let exerciseID = vm.exercises[0].id
        vm.exercises[0].sets[first].repsText = "6"
        _ = vm.toggleCompletion(setID: id, in: exerciseID)
        #expect(!isRetargeted(vm.exercises[0].sets[first + 1]))

        vm.setType(.failure, setID: id, in: exerciseID)
        #expect(vm.exercises[0].sets[first].effectiveRIR == 0)
        #expect(vm.exercises[0].sets[first].rir == nil)
        #expect(isRetargeted(vm.exercises[0].sets[first + 1]))
    }

    @Test func widenedRangeReachesWorkingSetsByPosition() throws {
        let vm = try retargetSession()
        let id = vm.exercises[0].id
        vm.applyFix(.widenRange(min: 6, max: 15), exerciseID: id, context: context)
        let sets = vm.exercises[0].sets
        #expect(sets.filter { $0.setType == .warmUp }.allSatisfy { $0.recommendation == nil })
        #expect(sets.filter { $0.setType == .warmUp }.map(\.weightKg).contains(20))
        #expect(sets.filter(\.setType.isWorkingSet).allSatisfy { $0.recommendation != nil })
    }

    @Test func warningComesFromTheNextWorkingSet() {
        let vm = viewModel(warmUps: false)
        logged(vm, [.warmUp, .normal])
        let warned = Recommendation(
            weightKg: 100, targetReps: 8, reason: .repeatTop(topReps: 8), warnings: [.noHeavierLoad(currentKg: 100)]
        )
        vm.exercises[0].sets[1].recommendation = warned
        #expect(vm.exercises[0].activeWarningRecommendation == warned)
    }

    // MARK: - Volume, counts and records

    @Test func volumeLeavesOutWarmUpsOnly() {
        let vm = viewModel(warmUps: false)
        logged(vm, [.warmUp, .normal, .failure, .drop, .myoRep], weight: 100)
        completeAll(vm)
        #expect(vm.totalVolumeKg == 4 * 100 * 10)
        #expect(vm.completedSetCount == 5)
    }

    @Test func finishSavesTypesSidesAndCounts() throws {
        let vm = viewModel(warmUps: false)
        logged(vm, [.warmUp, .normal, .drop])
        vm.exercises[0].sets[1].side = .left
        completeAll(vm)
        vm.finish(context: context)

        let summary = try #require(vm.summary)
        #expect(summary.totalVolumeKg == 2 * 100 * 10)
        #expect(summary.setCount == 2)
        let session = try #require(try context.fetch(FetchDescriptor<WorkoutSession>()).first)
        #expect(session.totalVolumeKg == 2 * 100 * 10)
        let sets = try #require(session.exercises.first).sets.sorted { $0.setNumber < $1.setNumber }
        #expect(sets.map(\.setNumber) == [1, 2, 3])
        #expect(sets.map(\.setType) == [.warmUp, .normal, .drop])
        #expect(sets.map(\.side) == [nil, .left, nil])
    }

    @Test func failureRIRIsNotStoredAtFinish() throws {
        let vm = viewModel(warmUps: false)
        logged(vm, [.failure])
        completeAll(vm)
        vm.finish(context: context)
        let set = try #require(try context.fetch(FetchDescriptor<SetEntry>()).first)
        #expect(set.rir == nil)
        #expect(set.effectiveRIR == 0)
    }

    @Test func aWarmUpOnlySessionCanStillBeFinished() throws {
        let vm = viewModel(warmUps: false)
        logged(vm, [.warmUp])
        completeAll(vm)
        #expect(vm.canFinish)
        vm.finish(context: context)
        #expect(vm.summary?.setCount == 0)
        #expect(vm.summary?.totalVolumeKg == 0)
        #expect(try context.fetchCount(FetchDescriptor<SetEntry>()) == 1)
    }

    @Test(arguments: [SetType.warmUp, .drop, .myoRep])
    func nonStraightSetsNeverBreakARecord(type: SetType) throws {
        try seed(sets: [entry(1, 100, 5)])
        let vm = viewModel(warmUps: false)
        logged(vm, [type], weight: 200)
        completeAll(vm)
        vm.finish(context: context)
        #expect(vm.summary?.newPRs.isEmpty == true)
    }

    @Test(arguments: [SetType.normal, .failure])
    func straightSetsBreakRecords(type: SetType) throws {
        try seed(sets: [entry(1, 100, 5)])
        let vm = viewModel(warmUps: false)
        logged(vm, [type], weight: 200)
        completeAll(vm)
        vm.finish(context: context)
        #expect(vm.summary?.newPRs.contains { $0.kind == .weight } == true)
    }

    @Test func aPastWarmUpDoesntBlockARecord() throws {
        try seed(sets: [entry(1, 300, 5, type: .warmUp), entry(2, 100, 5)])
        let vm = viewModel(warmUps: false)
        logged(vm, [.normal], weight: 110)
        completeAll(vm)
        vm.finish(context: context)
        #expect(vm.summary?.newPRs.contains { $0.kind == .weight } == true)
    }

    // MARK: - Rest

    private func restStarted(_ vm: ActiveSessionViewModel, exercise e: Int, set s: Int) -> Bool {
        vm.cancelRest()
        vm.startRestIfDue(afterCompleting: vm.exercises[e].sets[s].id, in: vm.exercises[e].id)
        return vm.restEndDate != nil
    }

    @Test func noRestAfterAWarmUp() {
        let vm = viewModel(warmUps: false)
        logged(vm, [.warmUp, .normal])
        #expect(!restStarted(vm, exercise: 0, set: 0))
        #expect(restStarted(vm, exercise: 0, set: 1))
    }

    @Test func restUsesTheExercisesTime() {
        let vm = viewModel(warmUps: false)
        logged(vm, [.normal])
        vm.startRestIfDue(afterCompleting: vm.exercises[0].sets[0].id, in: vm.exercises[0].id)
        let expected = Self.now.addingTimeInterval(TimeInterval(vm.exercises[0].restSeconds))
        #expect(vm.restEndDate == expected)
    }

    @Test(arguments: [SetType.drop, .myoRep])
    func noRestBeforeASetThatFollowsImmediately(next: SetType) {
        let vm = viewModel(warmUps: false)
        logged(vm, [.normal, next])
        #expect(!restStarted(vm, exercise: 0, set: 0))
        #expect(restStarted(vm, exercise: 0, set: 1))
    }

    @Test func aSupersetRestsAfterItsLastExercise() {
        let vm = viewModel(warmUps: false)
        logged(vm, [.normal])
        logged(vm, [.normal])
        vm.linkWithNext(vm.exercises[0].id)
        #expect(!restStarted(vm, exercise: 0, set: 0))
        #expect(restStarted(vm, exercise: 1, set: 0))
    }

    @Test func aSupersetRestsOnceLaterExercisesAreDone() {
        let vm = viewModel(warmUps: false)
        logged(vm, [.normal, .normal])
        logged(vm, [.normal])
        vm.linkWithNext(vm.exercises[0].id)
        _ = vm.toggleCompletion(setID: vm.exercises[1].sets[0].id, in: vm.exercises[1].id)
        #expect(restStarted(vm, exercise: 0, set: 1))
    }

    // MARK: - Supersets

    private func threeExercises() -> ActiveSessionViewModel {
        let vm = viewModel(warmUps: false)
        logged(vm, [.normal])
        logged(vm, [.normal])
        logged(vm, [.normal])
        return vm
    }

    @Test func linkingGivesPositions() {
        let vm = threeExercises()
        vm.linkWithNext(vm.exercises[0].id)
        #expect(vm.exercises.map(\.supersetGroup) == [1, 1, nil])
        #expect(vm.supersetPosition(of: vm.exercises[0].id) == .first)
        #expect(vm.supersetPosition(of: vm.exercises[1].id) == .last)
        #expect(vm.supersetPosition(of: vm.exercises[2].id) == nil)

        vm.linkWithNext(vm.exercises[1].id)
        #expect(vm.exercises.map(\.supersetGroup) == [1, 1, 1])
        #expect(vm.supersetPosition(of: vm.exercises[1].id) == .middle)
    }

    @Test func theLastExerciseHasNothingToLinkWith() {
        let vm = threeExercises()
        vm.linkWithNext(vm.exercises[2].id)
        #expect(vm.exercises.allSatisfy { $0.supersetGroup == nil })
    }

    @Test func linkingMergesTwoSupersets() {
        let vm = threeExercises()
        logged(vm, [.normal])
        vm.linkWithNext(vm.exercises[0].id)
        vm.linkWithNext(vm.exercises[2].id)
        #expect(vm.exercises.map(\.supersetGroup) == [1, 1, 2, 2])
        vm.linkWithNext(vm.exercises[1].id)
        #expect(vm.exercises.map(\.supersetGroup) == [1, 1, 1, 1])
    }

    @Test func unlinkingLeavesNoLoneExercise() {
        let vm = threeExercises()
        vm.linkWithNext(vm.exercises[0].id)
        vm.unlinkFromSuperset(vm.exercises[0].id)
        #expect(vm.exercises.allSatisfy { $0.supersetGroup == nil })
    }

    @Test func removingAndMovingKeepGroupsConsecutive() {
        let vm = threeExercises()
        vm.linkWithNext(vm.exercises[0].id)
        vm.moveExercise(fromOffsets: IndexSet(integer: 2), toOffset: 1)
        #expect(vm.exercises.allSatisfy { $0.supersetGroup == nil })

        let other = threeExercises()
        other.linkWithNext(other.exercises[0].id)
        other.removeExercise(other.exercises[0].id)
        #expect(other.exercises.allSatisfy { $0.supersetGroup == nil })
    }

    @Test func swappingKeepsTheLink() {
        let vm = threeExercises()
        vm.linkWithNext(vm.exercises[0].id)
        vm.replaceExercise(vm.exercises[0].id, withName: "Lateral Raise", muscleGroups: [], context: context)
        #expect(vm.exercises.map(\.supersetGroup) == [1, 1, nil])
    }

    @Test func finishSavesGroupsAndDropsLoneOnes() throws {
        let vm = threeExercises()
        logged(vm, [.normal])
        vm.linkWithNext(vm.exercises[0].id)
        vm.linkWithNext(vm.exercises[2].id)
        // Exercise 1 stays incomplete, so it isn't saved and 0 is left alone.
        for e in [0, 2, 3] {
            _ = vm.toggleCompletion(setID: vm.exercises[e].sets[0].id, in: vm.exercises[e].id)
        }
        vm.finish(context: context)
        let session = try #require(try context.fetch(FetchDescriptor<WorkoutSession>()).first)
        let logs = session.exercises.sorted { $0.orderIndex < $1.orderIndex }
        #expect(logs.map(\.supersetGroup) == [nil, 1, 1])
    }

    // MARK: - Drafts

    @Test func draftRoundTripsTypesSidesAndGroups() throws {
        let vm = viewModel(warmUps: false)
        logged(vm, [.warmUp, .failure])
        logged(vm, [.drop])
        vm.exercises[0].sets[1].side = .right
        vm.linkWithNext(vm.exercises[0].id)

        let snapshot = vm.snapshot()
        #expect(snapshot.version == 4)
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(ActiveSessionDraft.self, from: data)
        #expect(decoded == snapshot)

        let restored = viewModel(warmUps: false)
        restored.restore(from: decoded, context: context)
        #expect(restored.exercises[0].sets.map(\.setType) == [.warmUp, .failure])
        #expect(restored.exercises[0].sets.map(\.side) == [nil, .right])
        #expect(restored.exercises[1].sets.map(\.setType) == [.drop])
        #expect(restored.exercises.map(\.supersetGroup) == [1, 1])
    }

    @Test func normalSetsAreWrittenAsNil() {
        let vm = viewModel(warmUps: false)
        logged(vm, [.normal])
        #expect(vm.snapshot().exercises[0].sets[0].setType == nil)
    }

    @Test func restoringNeverGeneratesWarmUps() {
        let source = viewModel(warmUps: false)
        logged(source, [.normal])
        let restored = viewModel()
        restored.restore(from: source.snapshot(), context: context)
        #expect(restored.exercises[0].sets.map(\.setType) == [.normal])
    }

    /// `Fixtures/v3-session-draft.json` was written by the shipped code (commit
    /// 0dbc46f): a template bench press with one completed set at RIR 1 and two
    /// recommended ones, then a custom Sled Push.
    @Test func realV3DraftRestoresAsNormalSets() throws {
        let source = try #require(Bundle(for: BundleToken.self).url(forResource: "v3-session-draft", withExtension: "json"))
        let draft = try JSONDecoder().decode(ActiveSessionDraft.self, from: Data(contentsOf: source))
        #expect(draft.version == 3)
        #expect(ActiveSessionDraft.readableVersions.contains(draft.version))
        #expect(draft.templateSlot == TemplateSlot(split: .ppl, dayIndex: 0))

        let vm = viewModel()
        vm.restore(from: draft, context: context, progression: Self.smart)
        #expect(vm.exercises.map(\.name) == ["Barbell Bench Press", "Sled Push"])
        #expect(vm.exercises.allSatisfy { $0.supersetGroup == nil })
        #expect(vm.exercises.allSatisfy { $0.sets.allSatisfy { $0.setType == .normal && $0.side == nil } })
        #expect(vm.exercises[0].sets.count == 3)
        #expect(vm.exercises[0].sets[0].weightKg == 102.5)
        #expect(vm.exercises[0].sets[0].rir == 1)
        #expect(vm.exercises[0].sets[0].isCompleted)
        #expect(vm.exercises[0].sets[1].activeRecommendation != nil)
        #expect(vm.snapshot().version == ActiveSessionDraft.currentVersion)
    }

    // MARK: - Plate captions

    private func exerciseWithRamp() -> ActiveSessionViewModel.DraftExercise {
        let vm = ActiveSessionViewModel(sessionName: "Push", health: NoHealthWrites(), now: { Self.now })
        vm.addExercise(name: "Barbell Bench Press", muscleGroups: ["chest"], context: context)
        var exercise = vm.exercises[0]
        var warmUp = ActiveSessionViewModel.DraftSet()
        warmUp.setType = .warmUp
        exercise.sets = [warmUp, ActiveSessionViewModel.DraftSet(), ActiveSessionViewModel.DraftSet()]
        return exercise
    }

    @Test func plateCaptionShowsOnlyOnTheNextSetToDo() {
        let exercise = exerciseWithRamp()
        let shown = exercise.sets.map { exercise.showsPlateCaption(for: $0.id, revealed: nil) }
        // The warm-up comes first, so it's the next set even though it isn't a working set.
        #expect(shown == [true, false, false])
    }

    @Test func plateCaptionMovesOnWhenASetIsCompleted() {
        var exercise = exerciseWithRamp()
        exercise.sets[0].isCompleted = true
        let shown = exercise.sets.map { exercise.showsPlateCaption(for: $0.id, revealed: nil) }
        #expect(shown == [false, true, false])
    }

    @Test func tappingAWeightRevealsThatSetsPlateCaptionToo() {
        var exercise = exerciseWithRamp()
        let last = exercise.sets[2].id
        var shown = exercise.sets.map { exercise.showsPlateCaption(for: $0.id, revealed: last) }
        #expect(shown == [true, false, true])

        // A completed set can still be revealed.
        exercise.sets[0].isCompleted = true
        shown = exercise.sets.map { exercise.showsPlateCaption(for: $0.id, revealed: exercise.sets[0].id) }
        #expect(shown == [true, true, false])
    }

    @Test func noPlateCaptionOnceEverySetIsDoneUnlessRevealed() {
        var exercise = exerciseWithRamp()
        for index in exercise.sets.indices {
            exercise.sets[index].isCompleted = true
        }
        #expect(exercise.nextSetID == nil)
        #expect(!exercise.sets.contains { exercise.showsPlateCaption(for: $0.id, revealed: nil) })
        #expect(exercise.showsPlateCaption(for: exercise.sets[1].id, revealed: exercise.sets[1].id))
    }
}

private final class BundleToken {
}
