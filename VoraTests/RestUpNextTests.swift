//
//  RestUpNextTests.swift
//  VoraTests
//
//  Created by Majd Arow on 2026-11-03.
//

import Foundation
import Testing
@testable import Vora

struct RestUpNextTests {
    private typealias Exercise = ActiveSessionViewModel.DraftExercise
    private typealias DraftSet = ActiveSessionViewModel.DraftSet

    private func draftSet(
        weight: Double? = nil,
        reps: Int? = nil,
        type: SetType = .normal,
        done: Bool = false,
        units: UnitSystem = .metric
    ) -> DraftSet {
        var set = DraftSet(units: units)
        if let weight { set.setWeight(kg: weight) }
        if let reps { set.repsText = String(reps) }
        set.setType = type
        set.isCompleted = done
        return set
    }

    private func exercise(_ name: String, _ sets: [DraftSet], group: Int? = nil) -> Exercise {
        Exercise(
            name: name,
            exerciseId: nil,
            muscleGroups: [],
            sets: sets,
            previousSets: [],
            restSeconds: 90,
            supersetGroup: group
        )
    }

    private func resolve(_ exercises: [Exercise], after: Exercise?) -> RestUpNext {
        RestUpNext.resolve(exercises: exercises, restedAfter: after?.id, units: .metric, fallbackName: "Push")
    }

    private var done: DraftSet { draftSet(weight: 80, reps: 8, done: true) }
    private var open: DraftSet { draftSet(weight: 80, reps: 8) }

    // MARK: - Set text

    @Test func kilograms() {
        #expect(RestUpNext.setText(draftSet(weight: 82.5, reps: 8), repRange: nil, units: .metric) == "82.5 kg × 8")
    }

    @Test func pounds() {
        let set = draftSet(weight: 180 / UnitConversion.poundsPerKg, reps: 8, units: .imperial)
        #expect(RestUpNext.setText(set, repRange: nil, units: .imperial) == "180 lb × 8")
    }

    @Test func typedRepsWinOverTheRecommendationAndRange() {
        var set = draftSet(weight: 80, reps: 5)
        set.recommendation = Recommendation(weightKg: 80, targetReps: 9, reason: .repeatTop(topReps: 9))
        #expect(RestUpNext.setText(set, repRange: 6...10, units: .metric) == "80 kg × 5")
    }

    @Test func theRecommendationWinsOverTheRange() {
        var set = draftSet(weight: 80)
        set.recommendation = Recommendation(weightKg: 80, targetReps: 9, reason: .repeatTop(topReps: 9))
        #expect(RestUpNext.setText(set, repRange: 6...10, units: .metric) == "80 kg × 9")
    }

    @Test func aChangedWeightDropsTheRecommendationsReps() {
        var set = draftSet(weight: 85)
        set.recommendation = Recommendation(weightKg: 80, targetReps: 9, reason: .repeatTop(topReps: 9))
        #expect(RestUpNext.setText(set, repRange: 6...10, units: .metric) == "85 kg × 6–10")
    }

    @Test func aSingleRepTargetIsNotARange() {
        #expect(RestUpNext.setText(draftSet(weight: 80), repRange: 8...8, units: .metric) == "80 kg × 8")
    }

    @Test func weightWithoutReps() {
        #expect(RestUpNext.setText(draftSet(weight: 80), repRange: nil, units: .metric) == "80 kg")
    }

    @Test func bodyweightShowsRepsOnly() {
        #expect(RestUpNext.setText(draftSet(weight: 0, reps: 12), repRange: nil, units: .metric) == "12 reps")
        #expect(RestUpNext.setText(draftSet(reps: 12), repRange: nil, units: .metric) == "12 reps")
    }

    @Test func nothingKnown() {
        #expect(RestUpNext.setText(draftSet(), repRange: nil, units: .metric) == "Next set")
    }

    @Test func aWarmUpIsLabelled() {
        let set = draftSet(weight: 40, reps: 5, type: .warmUp)
        #expect(RestUpNext.setText(set, repRange: 6...10, units: .metric) == "Warm-up · 40 kg × 5")
    }

    @Test func aWarmUpWithNothingKnownIsJustItsLabel() {
        #expect(RestUpNext.setText(draftSet(type: .warmUp), repRange: 6...10, units: .metric) == "Warm-up")
    }

    @Test func aWarmUpDoesNotBorrowTheWorkingRange() {
        #expect(RestUpNext.setText(draftSet(weight: 40, type: .warmUp), repRange: 6...10, units: .metric) == "Warm-up · 40 kg")
    }

    @Test(arguments: [SetType.drop, .failure, .myoRep])
    func otherTypesUseTheirNames(type: SetType) {
        let set = draftSet(weight: 60, reps: 10, type: type)
        #expect(RestUpNext.setText(set, repRange: nil, units: .metric) == "\(type.displayName) · 60 kg × 10")
    }

    // MARK: - Which set

    @Test func theNextSetInTheSameExercise() {
        let bench = exercise("Bench", [done, draftSet(weight: 85, reps: 6)])
        let row = exercise("Row", [open])
        #expect(resolve([bench, row], after: bench) == RestUpNext(exerciseName: "Bench", setText: "85 kg × 6"))
    }

    @Test func aFinishedExerciseMovesToTheNextOne() {
        let bench = exercise("Bench", [done])
        let row = exercise("Row", [draftSet(weight: 60, reps: 10)])
        #expect(resolve([bench, row], after: bench) == RestUpNext(exerciseName: "Row", setText: "60 kg × 10"))
    }

    @Test func nothingLaterGoesBackToAnEarlierSkippedSet() {
        let bench = exercise("Bench", [open])
        let row = exercise("Row", [done])
        #expect(resolve([bench, row], after: row).exerciseName == "Bench")
    }

    @Test func aSupersetStartsItsNextRoundAtTheTop() {
        let bench = exercise("Bench", [done, open], group: 1)
        let row = exercise("Row", [done, open], group: 1)
        let curl = exercise("Curl", [open])
        #expect(resolve([bench, row, curl], after: row).exerciseName == "Bench")
    }

    @Test func aFinishedSupersetMovesPastTheGroup() {
        let bench = exercise("Bench", [done], group: 1)
        let row = exercise("Row", [done], group: 1)
        let curl = exercise("Curl", [open])
        #expect(resolve([bench, row, curl], after: row).exerciseName == "Curl")
    }

    @Test func theLastSetSaysSo() {
        let bench = exercise("Bench", [done])
        #expect(resolve([bench], after: bench) == RestUpNext(exerciseName: "Bench", setText: RestUpNext.lastSetText))
    }

    @Test func noExerciseFallsBackToTheSessionName() {
        #expect(resolve([], after: nil) == RestUpNext(exerciseName: "Push", setText: RestUpNext.lastSetText))
    }

    @Test func aRemovedExerciseUsesTheLastWithACompletedSet() {
        let bench = exercise("Bench", [open])
        let row = exercise("Row", [done, open])
        let removed = exercise("Gone", [done])
        #expect(resolve([bench, row], after: removed).exerciseName == "Row")
    }

    @Test func noCompletedSetsStartsFromTheTop() {
        let bench = exercise("Bench", [open])
        let row = exercise("Row", [open])
        #expect(resolve([bench, row], after: nil).exerciseName == "Bench")
    }

    @Test func theNotificationBodyNamesBoth() {
        #expect(RestUpNext(exerciseName: "Bench", setText: "80 kg × 8").notificationBody == "Bench: 80 kg × 8")
    }

    // MARK: - Content state

    @Test func contentStateRoundTrips() throws {
        let state = RestActivityAttributes.ContentState(
            exerciseName: "Bench",
            nextSetText: "80 kg × 8",
            startDate: Date(timeIntervalSinceReferenceDate: 100),
            endDate: Date(timeIntervalSinceReferenceDate: 190)
        )
        let decoded = try JSONDecoder().decode(
            RestActivityAttributes.ContentState.self,
            from: JSONEncoder().encode(state)
        )
        #expect(decoded == state)
    }

    @Test func anInvertedRangeIsClamped() {
        let end = Date(timeIntervalSinceReferenceDate: 100)
        let state = RestActivityAttributes.ContentState(
            exerciseName: "Bench",
            nextSetText: "80 kg × 8",
            startDate: end.addingTimeInterval(30),
            endDate: end
        )
        #expect(state.timerRange == end...end)
    }
}
