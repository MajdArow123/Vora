//
//  WorkoutTemplateServiceTests.swift
//  VoraTests
//
//  Created by Majd Arow on 2026-11-01.
//

import Foundation
import SwiftData
import Testing
@testable import Vora

@MainActor
struct WorkoutTemplateServiceTests {
    /// Held for the test's lifetime; a context outlives its container
    /// only as a dangling reference.
    private let container: ModelContainer

    init() throws {
        container = try PersistenceController.makeContainer(inMemory: true)
    }

    private func makeContext() -> ModelContext {
        container.mainContext
    }

    // MARK: - Defaults

    @Test func upperLowerHasDistinctAAndBDays() {
        let upperA = WorkoutTemplateService.defaultExerciseIDs(for: .upperLower, dayIndex: 0)
        let upperB = WorkoutTemplateService.defaultExerciseIDs(for: .upperLower, dayIndex: 3)
        #expect(upperA.first == "barbell-bench-press")
        #expect(upperB.first == "pull-up")
        #expect(upperA != upperB)
    }

    @Test func pplRepeatsTemplatesAcrossTheWeek() {
        #expect(WorkoutTemplateService.defaultExerciseIDs(for: .ppl, dayIndex: 0)
                == WorkoutTemplateService.defaultExerciseIDs(for: .ppl, dayIndex: 3))
        #expect(WorkoutTemplateService.defaultExerciseIDs(for: .ppl, dayIndex: 2)
                == WorkoutTemplateService.defaultExerciseIDs(for: .ppl, dayIndex: 5))
    }

    @Test func fullBodyAlternatesAAndB() {
        let dayA = WorkoutTemplateService.defaultExerciseIDs(for: .fullBody, dayIndex: 0)
        let dayB = WorkoutTemplateService.defaultExerciseIDs(for: .fullBody, dayIndex: 2)
        #expect(dayA == WorkoutTemplateService.defaultExerciseIDs(for: .fullBody, dayIndex: 4))
        #expect(dayB.first == "deadlift")
        #expect(dayA != dayB)
    }

    @Test func restDaysAndCustomSplitHaveNoDefaults() {
        #expect(WorkoutTemplateService.defaultExerciseIDs(for: .upperLower, dayIndex: 2).isEmpty)
        #expect(WorkoutTemplateService.defaultExerciseIDs(for: .ppl, dayIndex: 6).isEmpty)
        for day in WorkoutTemplateService.dayIndices {
            #expect(WorkoutTemplateService.defaultExerciseIDs(for: .custom, dayIndex: day).isEmpty)
        }
    }

    @Test func everyDefaultExerciseIsAPickableLibraryExercise() {
        for split in TrainingSplit.allCases {
            for day in WorkoutTemplateService.dayIndices {
                for id in WorkoutTemplateService.defaultExerciseIDs(for: split, dayIndex: day) {
                    let definition = ExerciseLibrary.definition(id: id)
                    #expect(definition != nil, "\(id) missing from ExerciseLibrary")
                    #expect(definition?.isLegacyOnly == false, "\(id) is legacy-only")
                }
            }
        }
    }

    @Test func defaultNamesFollowTheSplitsWeek() {
        #expect(WorkoutTemplateService.defaultName(for: .ppl, dayIndex: 1) == "Pull")
        #expect(WorkoutTemplateService.defaultName(for: .upperLower, dayIndex: 4) == "Lower")
        #expect(WorkoutTemplateService.defaultName(for: .ppl, dayIndex: 6) == "Day 7")
        #expect(WorkoutTemplateService.defaultName(for: .custom, dayIndex: 0) == "Day 1")
    }

    // MARK: - Plan

    @Test func planFallsBackToDefaultsWithDefaultTargets() throws {
        let context = makeContext()
        let plan = try WorkoutTemplateService.plan(for: .ppl, dayIndex: 0, context: context)

        #expect(plan.map(\.exerciseId) == WorkoutTemplateService.defaultExerciseIDs(for: .ppl, dayIndex: 0))
        #expect(plan.allSatisfy { $0.targetSets == 3 && $0.repRange == 8...12 && $0.targetRIR == 2 })
        #expect(plan.first?.restSeconds == 120)
        #expect(plan.last?.restSeconds == 90)
        #expect(try !WorkoutTemplateService.isCustomized(for: .ppl, dayIndex: 0, context: context))
    }

    @Test func planReturnsSavedExercisesInOrder() throws {
        let context = makeContext()
        let specs = [
            TemplateExerciseSpec(exerciseId: "dip", targetSets: 4),
            TemplateExerciseSpec(exerciseId: nil, customName: "Sled Push"),
            TemplateExerciseSpec(exerciseId: "back-squat", repRangeMin: 3, repRangeMax: 5, restSeconds: 300),
        ]
        try WorkoutTemplateService.save(specs, for: .ppl, dayIndex: 0, context: context)

        let plan = try WorkoutTemplateService.plan(for: .ppl, dayIndex: 0, context: context)
        #expect(plan == specs)
        #expect(try WorkoutTemplateService.isCustomized(for: .ppl, dayIndex: 0, context: context))
    }

    @Test func slotsAreSeparatedBySplitAndDay() throws {
        let context = makeContext()
        try WorkoutTemplateService.save([TemplateExerciseSpec(exerciseId: "dip")], for: .ppl, dayIndex: 0, context: context)

        #expect(try WorkoutTemplateService.isCustomized(for: .ppl, dayIndex: 0, context: context))
        #expect(try !WorkoutTemplateService.isCustomized(for: .ppl, dayIndex: 3, context: context))
        #expect(try !WorkoutTemplateService.isCustomized(for: .upperLower, dayIndex: 0, context: context))
    }

    // MARK: - Save

    @Test func saveClampsTargetsToLimits() throws {
        let context = makeContext()
        let wild = TemplateExerciseSpec(
            exerciseId: "dip", targetSets: 40, repRangeMin: 0, repRangeMax: 99, targetRIR: 9, restSeconds: 5000
        )
        try WorkoutTemplateService.save([wild], for: .ppl, dayIndex: 0, context: context)

        let saved = try #require(try WorkoutTemplateService.plan(for: .ppl, dayIndex: 0, context: context).first)
        #expect(saved.targetSets == 10)
        #expect(saved.repRange == 1...50)
        #expect(saved.targetRIR == 5)
        #expect(saved.restSeconds == 600)
    }

    @Test func savingTwiceKeepsOneRowPerSlot() throws {
        let context = makeContext()
        try WorkoutTemplateService.save([TemplateExerciseSpec(exerciseId: "dip")], for: .ppl, dayIndex: 0, context: context)
        try WorkoutTemplateService.save([TemplateExerciseSpec(exerciseId: "push-up")], for: .ppl, dayIndex: 0, context: context)

        #expect(try context.fetchCount(FetchDescriptor<WorkoutTemplate>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<TemplateExercise>()) == 1)
        #expect(try WorkoutTemplateService.plan(for: .ppl, dayIndex: 0, context: context).map(\.exerciseId) == ["push-up"])
    }

    @Test func unchangedExerciseKeepsItsIDAfterSave() throws {
        let context = makeContext()
        try WorkoutTemplateService.save(
            [TemplateExerciseSpec(exerciseId: "dip"), TemplateExerciseSpec(exerciseId: "push-up")],
            for: .ppl, dayIndex: 0, context: context
        )
        let loaded = try WorkoutTemplateService.plan(for: .ppl, dayIndex: 0, context: context)

        try WorkoutTemplateService.save(loaded, for: .ppl, dayIndex: 0, context: context)

        let reloaded = try WorkoutTemplateService.plan(for: .ppl, dayIndex: 0, context: context)
        #expect(reloaded.map(\.id) == loaded.map(\.id))
        let rowIDs = try context.fetch(FetchDescriptor<TemplateExercise>()).map(\.id)
        #expect(Set(rowIDs) == Set(loaded.map(\.id)))
    }

    @Test func editsUpdateInPlaceAndRemovalsAndReordersApply() throws {
        let context = makeContext()
        try WorkoutTemplateService.save(
            [
                TemplateExerciseSpec(exerciseId: "dip"),
                TemplateExerciseSpec(exerciseId: "push-up"),
                TemplateExerciseSpec(exerciseId: "back-squat"),
            ],
            for: .ppl, dayIndex: 0, context: context
        )
        var edited = try WorkoutTemplateService.plan(for: .ppl, dayIndex: 0, context: context)
        let dipID = edited[0].id
        let squatID = edited[2].id
        edited[0].targetSets = 5
        edited.remove(at: 1)
        edited.swapAt(0, 1)
        let added = TemplateExerciseSpec(exerciseId: nil, customName: "Sled Push")
        edited.append(added)

        try WorkoutTemplateService.save(edited, for: .ppl, dayIndex: 0, context: context)

        let rows = try #require(try WorkoutTemplateService.template(for: .ppl, dayIndex: 0, context: context))
            .orderedExercises
        #expect(rows.map(\.id) == [squatID, dipID, added.id])
        #expect(rows.map(\.orderIndex) == [0, 1, 2])
        #expect(rows[1].targetSets == 5)
        #expect(rows[2].customName == "Sled Push")
        #expect(try context.fetchCount(FetchDescriptor<TemplateExercise>()) == 3)
    }

    // MARK: - Reset

    @Test func resetDeletesTemplateAndChildrenAndRestoresDefaults() throws {
        let context = makeContext()
        try WorkoutTemplateService.save(
            [TemplateExerciseSpec(exerciseId: "dip"), TemplateExerciseSpec(exerciseId: "push-up")],
            for: .ppl, dayIndex: 0, context: context
        )

        try WorkoutTemplateService.reset(for: .ppl, dayIndex: 0, context: context)

        #expect(try context.fetchCount(FetchDescriptor<WorkoutTemplate>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<TemplateExercise>()) == 0)
        #expect(try WorkoutTemplateService.plan(for: .ppl, dayIndex: 0, context: context).map(\.exerciseId)
                == WorkoutTemplateService.defaultExerciseIDs(for: .ppl, dayIndex: 0))
    }

    @Test func resetWithoutSavedTemplateIsANoOp() throws {
        let context = makeContext()
        try WorkoutTemplateService.reset(for: .fullBody, dayIndex: 0, context: context)
        #expect(try context.fetchCount(FetchDescriptor<WorkoutTemplate>()) == 0)
    }
}
