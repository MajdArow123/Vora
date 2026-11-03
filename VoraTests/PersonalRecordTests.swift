//
//  PersonalRecordTests.swift
//  VoraTests
//
//  Created by Majd Arow on 2026-11-02.
//

import Foundation
import SwiftData
import Testing
@testable import Vora

struct SetTypeRecordTests {
    private let container: ModelContainer
    private let context: ModelContext

    init() throws {
        container = try PersistenceController.makeContainer(inMemory: true)
        context = container.mainContext
    }

    private func set(_ number: Int, _ weight: Double, _ reps: Int = 8, rir: Int? = nil, type: SetType = .normal) -> SetEntry {
        SetEntry(setNumber: number, weightKg: weight, reps: reps, isCompleted: true, rir: rir, setType: type)
    }

    private func session(_ sets: [SetEntry]) throws -> [WorkoutSession] {
        let log = ExerciseLog(
            exerciseName: "Barbell Bench Press", exerciseId: "barbell-bench-press", muscleGroups: ["chest"], orderIndex: 0, sets: sets
        )
        let session = WorkoutSession(date: Date(timeIntervalSince1970: 1_795_075_200), sessionName: "Push", exercises: [log])
        context.insert(session)
        try context.save()
        return [session]
    }

    @Test func personalRecordsUseStraightSetsOnly() throws {
        _ = try session([
            set(1, 300, type: .warmUp),
            set(2, 100, 5),
            set(3, 280, type: .drop),
            set(4, 260, type: .myoRep),
        ])
        let record = try #require(WorkoutHomeViewModel.computePersonalRecords(from: context).first)
        #expect(record.weightKg == 100)
        #expect(record.bestE1RMKg == StrengthProgression.epley(weightKg: 100, repsToFailure: 5))
        // The summary counts what was trained, which leaves only warm-ups out.
        #expect(record.totalSets == 3)
    }

    @Test func aFailureSetCanBeARecord() throws {
        _ = try session([set(1, 100), set(2, 110, 3, type: .failure)])
        #expect(WorkoutHomeViewModel.computePersonalRecords(from: context).first?.weightKg == 110)
    }

    @Test func sessionStatsListEverySetButJudgeStraightOnes() throws {
        let sessions = try session([set(1, 300, type: .warmUp), set(2, 100, 5), set(3, 90, 6, type: .failure), set(4, 200, 12, type: .drop)])
        let stat = try #require(StrengthProgression.sessionStats(forKey: "barbell-bench-press", sessions: sessions).first)
        #expect(stat.bestWeightKg == 100)
        #expect(stat.bestReps == 5)
        #expect(stat.completedSets == 3)
        #expect(stat.sets.map(\.setType) == [.warmUp, .normal, .failure, .drop])
        #expect(stat.sets.map(\.rir) == [nil, nil, 0, nil])
        // Reps in the summary leave the warm-up's out.
        #expect(stat.setsSummary == "3 sets × 5–12 reps")
    }

    @Test func sessionsWithoutStraightSetsHaveNoStat() throws {
        let sessions = try session([set(1, 100, type: .warmUp), set(2, 50, type: .drop)])
        #expect(StrengthProgression.sessionStats(forKey: "barbell-bench-press", sessions: sessions).isEmpty)
        #expect(StrengthProgression.distinctExerciseNames(in: sessions).isEmpty)
    }
}

struct NewRecordDetectionTests {
    private func set(_ weight: Double, _ reps: Int) -> RecordSet { RecordSet(weightKg: weight, reps: reps) }

    private func kinds(prior: [RecordSet], session: [RecordSet]) -> [PersonalRecordKind] {
        StrengthProgression.newRecords(prior: prior, session: session).map(\.kind)
    }

    @Test func firstLogOnlyCountsAsAWeightRecord() {
        #expect(kinds(prior: [], session: [set(100, 5)]) == [.weight])
    }

    @Test func heavierIsAWeightRecord() {
        let found = StrengthProgression.newRecords(prior: [set(100, 5)], session: [set(105, 3)])
        #expect(found.contains(NewRecord(kind: .weight, weightKg: 105, reps: 3)))
    }

    @Test func tyingTheHeaviestIsNotAWeightRecord() {
        #expect(!kinds(prior: [set(100, 5)], session: [set(100, 5)]).contains(.weight))
    }

    @Test func moreRepsAtALiftedWeightIsARepRecord() {
        let found = StrengthProgression.newRecords(prior: [set(100, 5)], session: [set(100, 6)])
        #expect(found.contains(NewRecord(kind: .reps, weightKg: 100, reps: 6)))
    }

    @Test func tyingRepsIsNotARepRecord() {
        #expect(!kinds(prior: [set(100, 5)], session: [set(100, 5)]).contains(.reps))
    }

    @Test func aNewWeightIsNotARepRecord() {
        #expect(!kinds(prior: [set(100, 5)], session: [set(90, 20)]).contains(.reps))
    }

    @Test func aLighterWeightCanBeARepRecordEvenBelowTheHeaviest() {
        let prior = [set(100, 5), set(80, 10)]
        #expect(kinds(prior: prior, session: [set(80, 11)]).contains(.reps))
    }

    @Test func reportsTheHeaviestRepRecordOnly() {
        let prior = [set(100, 5), set(80, 10)]
        let found = StrengthProgression.newRecords(prior: prior, session: [set(100, 6), set(80, 11)])
        #expect(found.filter { $0.kind == .reps } == [NewRecord(kind: .reps, weightKg: 100, reps: 6)])
    }

    @Test func bodyweightRepsCount() {
        let found = StrengthProgression.newRecords(prior: [set(0, 10)], session: [set(0, 12)])
        #expect(found == [NewRecord(kind: .reps, weightKg: 0, reps: 12)])
    }

    @Test func zeroWeightIsNeverAWeightOrE1RMRecord() {
        #expect(kinds(prior: [], session: [set(0, 12)]).isEmpty)
    }

    @Test func aBetterEstimateIsAnE1RMRecord() {
        // 100×5 is 116.67; 90×10 is 120.
        let found = StrengthProgression.newRecords(prior: [set(100, 5)], session: [set(90, 10)])
        #expect(found == [NewRecord(kind: .estimatedOneRepMax, weightKg: 90, reps: 10)])
    }

    @Test func aMatchingEstimateIsNoE1RMRecord() {
        #expect(!kinds(prior: [set(100, 5)], session: [set(100, 5)]).contains(.estimatedOneRepMax))
    }

    @Test func aSingleSetCanBreakAllThree() {
        // 105×6 beats the heaviest and the estimate; rep record at 100 from another set.
        let kinds = kinds(prior: [set(100, 5)], session: [set(105, 6), set(100, 6)])
        #expect(kinds == [.weight, .reps, .estimatedOneRepMax])
    }

    @Test func noRecordsWithALesserSession() {
        #expect(kinds(prior: [set(100, 5)], session: [set(90, 5)]).isEmpty)
    }

    @Test func recordsIgnoreIncompleteValues() {
        let records = StrengthProgression.records(from: [set(100, 0), set(-5, 10)])
        #expect(records.heaviest == nil)
        #expect(records.repBests.isEmpty)
    }

    @Test func exerciseRecordsKeepEachBest() {
        let records = StrengthProgression.records(from: [set(100, 1), set(90, 10), set(90, 8), set(0, 12)])
        #expect(records.heaviest == set(100, 1))
        #expect(records.bestE1RMSet == set(90, 10))
        #expect(records.bestE1RMKg == 120)
        #expect(records.repBests == [
            .init(weightKg: 100, reps: 1),
            .init(weightKg: 90, reps: 10),
            .init(weightKg: 0, reps: 12),
        ])
    }

    @Test func convertedPoundWeightsMatchThemselves() {
        let lb = UnitConversion.kg(fromPounds: 185)
        #expect(kinds(prior: [set(lb, 8)], session: [set(lb, 9)]).contains(.reps))
    }
}

@MainActor
struct SessionPRTests {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    init() throws {
        container = try PersistenceController.makeContainer(inMemory: true)
    }

    private func log(_ sets: [(Double, Int)], name: String = "Barbell Bench Press") {
        let vm = ActiveSessionViewModel(sessionName: "Push", health: NoHealthWrites())
        vm.addExercise(name: name, muscleGroups: [], context: context)
        let id = vm.exercises[0].id
        while vm.exercises[0].sets.count < sets.count { vm.addSet(to: id) }
        for (index, set) in sets.enumerated() {
            vm.exercises[0].sets[index].weightText = String(set.0)
            vm.exercises[0].sets[index].repsText = String(set.1)
            _ = vm.toggleCompletion(setID: vm.exercises[0].sets[index].id, in: id)
        }
        vm.finish(context: context)
        lastSummary = vm.summary
    }

    private final class Box { var summary: SessionSummary? }
    private let box = Box()
    private var lastSummary: SessionSummary? {
        get { box.summary }
        nonmutating set { box.summary = newValue }
    }

    @Test func aSessionReportsEveryKindItBroke() throws {
        log([(100, 5)])
        log([(105, 6), (100, 6)])
        let summary = try #require(lastSummary)
        #expect(summary.newPRs.map(\.kind) == [.weight, .reps, .estimatedOneRepMax])
        #expect(Set(summary.newPRs.map(\.id)).count == 3)
        #expect(summary.newPRs.first?.exerciseKey == "barbell-bench-press")
    }

    @Test func aFirstSessionIsAWeightRecordOnly() throws {
        log([(100, 5)])
        #expect(try #require(lastSummary).newPRs.map(\.kind) == [.weight])
    }

    @Test func anEqualSessionBreaksNothing() throws {
        log([(100, 5)])
        log([(100, 5)])
        #expect(try #require(lastSummary).newPRs.isEmpty)
    }

    @Test func customExercisesGetRecordsToo() throws {
        log([(50, 10)], name: "Sled Push")
        log([(50, 12)], name: "sled push")
        let summary = try #require(lastSummary)
        #expect(summary.newPRs.contains { $0.kind == .reps && $0.reps == 12 })
    }

    @Test func personalRecordCardUsesTheBestEstimateAcrossSets() throws {
        log([(100, 1), (90, 10)])
        let record = try #require(WorkoutHomeViewModel.computePersonalRecords(from: context).first)
        #expect(record.weightKg == 100)
        #expect(record.estimatedOneRepMax == 120)
    }
}
