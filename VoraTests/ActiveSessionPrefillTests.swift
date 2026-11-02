//
//  ActiveSessionPrefillTests.swift
//  VoraTests
//
//  Created by Majd Arow on 2026-07-24.
//

import Foundation
import SwiftData
import Testing
@testable import Vora

struct ActiveSessionPrefillTests {
    private func makeContainer() throws -> ModelContainer {
        try PersistenceController.makeContainer(inMemory: true)
    }

    private func spec(_ id: String, sets: Int = 3) -> TemplateExerciseSpec {
        TemplateExerciseSpec(exerciseId: id, targetSets: sets)
    }

    private func custom(_ name: String) -> TemplateExerciseSpec {
        TemplateExerciseSpec(exerciseId: nil, customName: name)
    }

    @MainActor
    private func seedSession(
        in context: ModelContext,
        exerciseName: String,
        weights: [Double],
        daysAgo: Int
    ) throws {
        let date = try #require(Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now))
        let session = WorkoutSession(date: date, sessionName: "Seeded")
        context.insert(session)
        let log = ExerciseLog(exerciseName: exerciseName, orderIndex: 0)
        session.exercises.append(log)
        for (index, weight) in weights.enumerated() {
            log.sets.append(SetEntry(
                setNumber: index + 1,
                weightKg: weight,
                reps: 8,
                isCompleted: true
            ))
        }
        try context.save()
    }

    @Test @MainActor func prefillCreatesTargetSetsPerExercise() throws {
        let container = try makeContainer()
        let viewModel = ActiveSessionViewModel(sessionName: "Push", health: NoHealthWrites())
        viewModel.prefill(
            with: [spec("barbell-bench-press", sets: 1), spec("overhead-press"), spec("dip", sets: 5)],
            context: container.mainContext
        )

        #expect(viewModel.exercises.map(\.sets.count) == [1, 3, 5])
        for exercise in viewModel.exercises {
            #expect(exercise.sets.allSatisfy { $0.repsText.isEmpty && !$0.isCompleted })
        }
    }

    @Test @MainActor func prefillUsesDefaultSetsForOutOfRangeTargets() throws {
        let container = try makeContainer()
        let viewModel = ActiveSessionViewModel(sessionName: "Push", health: NoHealthWrites())
        viewModel.prefill(with: [spec("dip", sets: 0), spec("dip", sets: 99)], context: container.mainContext)

        #expect(viewModel.exercises.map(\.sets.count) == [3, 3])
    }

    @Test @MainActor func prefillCarriesRestAndRepRange() throws {
        let container = try makeContainer()
        let viewModel = ActiveSessionViewModel(sessionName: "Push", health: NoHealthWrites())
        var bench = spec("barbell-bench-press")
        bench.repRangeMin = 5
        bench.repRangeMax = 8
        bench.restSeconds = 240
        viewModel.prefill(with: [bench, spec("lateral-raise")], context: container.mainContext)

        #expect(viewModel.exercises[0].restSeconds == 240)
        #expect(viewModel.exercises[0].repRange == 5...8)
        #expect(viewModel.exercises[1].restSeconds == 90)
        #expect(viewModel.exercises[1].repRange == 8...12)
    }

    @Test @MainActor func prefillResolvesNamesAndMuscleGroupsFromLibrary() throws {
        let container = try makeContainer()
        let viewModel = ActiveSessionViewModel(sessionName: "Push", health: NoHealthWrites())
        viewModel.prefill(with: [spec("barbell-bench-press"), custom("Made-up Movement")], context: container.mainContext)

        #expect(viewModel.exercises.map(\.name) == ["Barbell Bench Press", "Made-up Movement"])
        #expect(viewModel.exercises.map(\.exerciseId) == ["barbell-bench-press", nil])
        #expect(viewModel.exercises[0].muscleGroups == [MuscleGroup.chest.rawValue])
        #expect(viewModel.exercises[1].muscleGroups.isEmpty)
    }

    @Test @MainActor func prefillFillsWeightsFromMostRecentSession() throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedSession(in: context, exerciseName: "Back Squat", weights: [100, 105], daysAgo: 10)
        try seedSession(in: context, exerciseName: "Back Squat", weights: [110, 115], daysAgo: 3)

        let viewModel = ActiveSessionViewModel(sessionName: "Legs", health: NoHealthWrites())
        viewModel.prefill(with: [spec("back-squat", sets: 4)], context: context)

        let sets = viewModel.exercises[0].sets
        // Per-index from the latest session; later sets fall back to its last weight.
        #expect(sets.map(\.weightText) == ["110", "115", "115", "115"])
        #expect(sets.allSatisfy { $0.repsText.isEmpty })
    }

    @Test @MainActor func prefillLeavesWeightsEmptyWithoutHistory() throws {
        let container = try makeContainer()
        let viewModel = ActiveSessionViewModel(sessionName: "Legs", health: NoHealthWrites())
        viewModel.prefill(with: [spec("back-squat")], context: container.mainContext)

        #expect(viewModel.exercises[0].sets.allSatisfy { $0.weightText.isEmpty })
    }

    @Test @MainActor func prefillIsNoOpWhenExercisesExist() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let viewModel = ActiveSessionViewModel(sessionName: "Push", health: NoHealthWrites())
        viewModel.addExercise(name: "Dip", muscleGroups: [], context: context)
        viewModel.prefill(with: [spec("barbell-bench-press")], context: context)

        #expect(viewModel.exercises.count == 1)
        #expect(viewModel.exercises[0].name == "Dip")
    }

    @Test @MainActor func addedExercisesUseLibraryRestAndNoRepRange() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let viewModel = ActiveSessionViewModel(sessionName: "Push", health: NoHealthWrites())
        viewModel.addExercise(name: "Back Squat", muscleGroups: ["quads"], context: context)
        viewModel.addExercise(name: "Cable Fly", muscleGroups: ["chest"], context: context)
        viewModel.addExercise(name: "Sled Push", muscleGroups: [], context: context)

        #expect(viewModel.exercises.map(\.restSeconds) == [120, 90, 90])
        #expect(viewModel.exercises.allSatisfy { $0.repRange == nil })
    }

    @Test @MainActor func swappingKeepsTheSlotsTargets() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let viewModel = ActiveSessionViewModel(sessionName: "Push", health: NoHealthWrites())
        var bench = spec("barbell-bench-press")
        bench.repRangeMin = 6
        bench.repRangeMax = 10
        bench.restSeconds = 180
        viewModel.prefill(with: [bench], context: context)

        let slot = try #require(viewModel.exercises.first)
        viewModel.replaceExercise(slot.id, withName: "Dumbbell Bench Press", muscleGroups: ["chest"], context: context)

        let swapped = try #require(viewModel.exercises.first)
        #expect(swapped.name == "Dumbbell Bench Press")
        #expect(swapped.restSeconds == 180)
        #expect(swapped.repRange == 6...10)
        #expect(swapped.sets.count == 1)
    }

    @Test @MainActor func moveExerciseReorders() throws {
        let container = try makeContainer()
        let viewModel = ActiveSessionViewModel(sessionName: "Push", health: NoHealthWrites())
        viewModel.prefill(with: [custom("A"), custom("B"), custom("C")], context: container.mainContext)

        viewModel.moveExercise(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        #expect(viewModel.exercises.map(\.name) == ["C", "A", "B"])
    }
}
