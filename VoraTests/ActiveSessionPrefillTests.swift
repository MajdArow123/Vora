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
        let schema = Schema([
            UserProfile.self, FoodEntry.self, CustomFood.self,
            WorkoutSession.self, ExerciseLog.self, SetEntry.self,
            WeightEntry.self, WaterEntry.self, CardioEntry.self, SplitDay.self,
        ])
        return try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
    }

    @MainActor
    private func seedSession(
        in context: ModelContext,
        exerciseName: String,
        weights: [Double],
        daysAgo: Int
    ) {
        let session = WorkoutSession(
            date: Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!,
            sessionName: "Seeded"
        )
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
        try? context.save()
    }

    @Test @MainActor func prefillCreatesFourEmptySetsPerExercise() throws {
        let container = try makeContainer()
        let viewModel = ActiveSessionViewModel(sessionName: "Push")
        viewModel.prefill(with: ["Barbell Bench Press", "Overhead Press"], context: container.mainContext)

        #expect(viewModel.exercises.count == 2)
        for exercise in viewModel.exercises {
            #expect(exercise.sets.count == 4)
            #expect(exercise.sets.allSatisfy { $0.repsText.isEmpty && !$0.isCompleted })
        }
    }

    @Test @MainActor func prefillResolvesMuscleGroupsFromLibrary() throws {
        let container = try makeContainer()
        let viewModel = ActiveSessionViewModel(sessionName: "Push")
        viewModel.prefill(with: ["Barbell Bench Press", "Made-up Movement"], context: container.mainContext)

        #expect(viewModel.exercises[0].muscleGroups == [MuscleGroup.chest.rawValue])
        #expect(viewModel.exercises[1].muscleGroups.isEmpty)
    }

    @Test @MainActor func prefillFillsWeightsFromMostRecentSession() throws {
        let container = try makeContainer()
        let context = container.mainContext
        seedSession(in: context, exerciseName: "Back Squat", weights: [100, 105], daysAgo: 10)
        seedSession(in: context, exerciseName: "Back Squat", weights: [110, 115], daysAgo: 3)

        let viewModel = ActiveSessionViewModel(sessionName: "Legs")
        viewModel.prefill(with: ["Back Squat"], context: context)

        let sets = viewModel.exercises[0].sets
        // Per-index from the latest session; later sets fall back to its last weight.
        #expect(sets.map(\.weightText) == ["110", "115", "115", "115"])
        #expect(sets.allSatisfy { $0.repsText.isEmpty })
    }

    @Test @MainActor func prefillLeavesWeightsEmptyWithoutHistory() throws {
        let container = try makeContainer()
        let viewModel = ActiveSessionViewModel(sessionName: "Legs")
        viewModel.prefill(with: ["Back Squat"], context: container.mainContext)

        #expect(viewModel.exercises[0].sets.allSatisfy { $0.weightText.isEmpty })
    }

    @Test @MainActor func prefillIsNoOpWhenExercisesExist() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let viewModel = ActiveSessionViewModel(sessionName: "Push")
        viewModel.addExercise(name: "Dip", muscleGroups: [], context: context)
        viewModel.prefill(with: ["Barbell Bench Press"], context: context)

        #expect(viewModel.exercises.count == 1)
        #expect(viewModel.exercises[0].name == "Dip")
    }

    @Test @MainActor func moveExerciseReorders() throws {
        let container = try makeContainer()
        let viewModel = ActiveSessionViewModel(sessionName: "Push")
        viewModel.prefill(with: ["A", "B", "C"], context: container.mainContext)

        viewModel.moveExercise(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        #expect(viewModel.exercises.map(\.name) == ["C", "A", "B"])
    }
}
