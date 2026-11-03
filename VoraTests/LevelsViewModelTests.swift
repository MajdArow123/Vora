//
//  LevelsViewModelTests.swift
//  VoraTests
//
//  Created by Majd Arow on 2026-11-02.
//

import Foundation
import SwiftData
import Testing
@testable import Vora

private final class NoHealthDeletes: HealthWorkoutDeleting {
    func deleteWorkout(id: UUID) async throws -> HealthWorkoutDeletionResult { .deleted }
    func deleteWorkout(matching match: HealthWorkoutMatch) async throws -> HealthWorkoutDeletionResult { .deleted }
}

struct LevelsViewModelTests {
    private let container: ModelContainer
    private let context: ModelContext
    private let calendar = Calendar.current
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    init() throws {
        container = try PersistenceController.makeContainer(inMemory: true)
        context = container.mainContext
    }

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))!
            .addingTimeInterval(17 * 3600)
    }

    @discardableResult
    private func insertSession(
        day offset: Int,
        name: String,
        exerciseId: String? = nil,
        muscleGroups: [String] = [],
        completed: Int = 3,
        skipped: Int = 0
    ) throws -> WorkoutSession {
        let sets = (0..<(completed + skipped)).map { index in
            SetEntry(setNumber: index + 1, weightKg: 50, reps: 8, isCompleted: index < completed)
        }
        let session = WorkoutSession(
            date: day(offset),
            sessionName: "Session",
            durationSeconds: 3000,
            totalVolumeKg: 1000,
            exercises: [ExerciseLog(
                exerciseName: name,
                exerciseId: exerciseId,
                muscleGroups: muscleGroups,
                orderIndex: 0,
                sets: sets
            )]
        )
        context.insert(session)
        try context.save()
        return session
    }

    private func loadedViewModel(range: LevelsCalculator.Range = .oneWeek) -> LevelsViewModel {
        let viewModel = LevelsViewModel()
        viewModel.load(from: context, now: now, calendar: calendar)
        viewModel.selectedRange = range
        return viewModel
    }

    private func perWeek(_ viewModel: LevelsViewModel, _ muscle: Muscle) -> Double {
        viewModel.result.level(for: muscle)?.setsPerWeek ?? -1
    }

    @Test func usesLibraryMusclesForALoggedExercise() throws {
        try insertSession(day: -1, name: "Barbell Bench Press", exerciseId: "barbell-bench-press", completed: 4)
        let viewModel = loadedViewModel()
        let bench = try #require(ExerciseLibrary.definition(id: "barbell-bench-press"))

        for muscle in bench.primaryMuscles {
            #expect(perWeek(viewModel, muscle) == 4)
        }
        for muscle in bench.secondaryMuscles {
            #expect(perWeek(viewModel, muscle) == 2)
        }
    }

    @Test func incompleteSetsDoNotCount() throws {
        try insertSession(day: -1, name: "Barbell Bench Press", exerciseId: "barbell-bench-press", completed: 2, skipped: 3)
        #expect(perWeek(loadedViewModel(), .chest) == 2)
    }

    @Test func deletedSessionsAreExcluded() throws {
        try insertSession(day: -1, name: "Barbell Bench Press", exerciseId: "barbell-bench-press", completed: 2)
        let doomed = try insertSession(day: -2, name: "Barbell Bench Press", exerciseId: "barbell-bench-press", completed: 5)
        #expect(perWeek(loadedViewModel(), .chest) == 7)

        _ = try WorkoutDeletionService(health: NoHealthDeletes()).delete(doomed, context: context)
        #expect(perWeek(loadedViewModel(), .chest) == 2)
    }

    @Test func aliasedLegacyNameMergesWithTheLibraryExercise() throws {
        try insertSession(day: -1, name: "bench press", exerciseId: nil, completed: 2)
        try insertSession(day: -2, name: "Barbell Bench Press", exerciseId: "barbell-bench-press", completed: 3)
        let viewModel = loadedViewModel()
        let contributors = viewModel.result.level(for: .chest)?.contributors ?? []

        #expect(contributors.count == 1)
        #expect(contributors.first?.exerciseKey == "barbell-bench-press")
        #expect(contributors.first?.completedSets == 5)
        #expect(contributors.first?.displayName == "Barbell Bench Press")
    }

    @Test func aRenamedExerciseStaysMatchedByID() throws {
        try insertSession(day: -1, name: "An Older Name", exerciseId: "barbell-bench-press", completed: 3)
        let contributors = loadedViewModel().result.level(for: .chest)?.contributors ?? []
        #expect(contributors.first?.exerciseKey == "barbell-bench-press")
        #expect(contributors.first?.displayName == "Barbell Bench Press")
    }

    @Test func customExerciseSavedThroughThePickerIsExcluded() throws {
        // The picker stores custom exercises with no muscle groups.
        try insertSession(day: -1, name: "Landmine Press", muscleGroups: [], completed: 3)
        let viewModel = loadedViewModel()

        #expect(viewModel.result.levels.allSatisfy { $0.setsPerWeek == 0 })
        #expect(viewModel.result.excluded.map(\.displayName) == ["Landmine Press"])
        #expect(viewModel.result.excludedSetCount == 3)
        #expect(viewModel.result.hasTraining)
    }

    @Test func customExerciseWithAnUnambiguousStoredGroupCounts() throws {
        try insertSession(day: -1, name: "Weird Curl", muscleGroups: ["biceps"], completed: 3)
        #expect(perWeek(loadedViewModel(), .biceps) == 3)
    }

    @Test func firstTrainingDayComesFromBeforeTheFetchWindow() throws {
        try insertSession(day: -200, name: "Barbell Bench Press", exerciseId: "barbell-bench-press", completed: 9)
        try insertSession(day: -1, name: "Barbell Bench Press", exerciseId: "barbell-bench-press", completed: 12)
        let viewModel = loadedViewModel(range: .twelveWeeks)

        #expect(viewModel.result.weeksAveraged == 12)
        #expect(perWeek(viewModel, .chest) == 1)
    }

    @Test func changingRangeRecalculatesWithoutReloading() throws {
        try insertSession(day: -1, name: "Barbell Bench Press", exerciseId: "barbell-bench-press", completed: 4)
        try insertSession(day: -20, name: "Barbell Bench Press", exerciseId: "barbell-bench-press", completed: 8)
        let viewModel = loadedViewModel(range: .oneWeek)
        #expect(perWeek(viewModel, .chest) == 4)

        viewModel.selectedRange = .fourWeeks
        #expect(perWeek(viewModel, .chest) == 12.0 / 3)
    }

    @Test func noTrainingInRangeReadsAsEmpty() throws {
        try insertSession(day: -20, name: "Barbell Bench Press", exerciseId: "barbell-bench-press")
        #expect(!loadedViewModel(range: .oneWeek).result.hasTraining)
        #expect(!LevelsViewModel().result.hasTraining)
    }

    @Test func dayOffsetsCountCalendarDaysNotElapsedTime() throws {
        // Late the previous evening is -1 even though under a day has passed.
        let lateYesterday = calendar.startOfDay(for: now).addingTimeInterval(-60)
        let session = try insertSession(day: -1, name: "Barbell Bench Press", exerciseId: "barbell-bench-press")
        session.date = lateYesterday
        try context.save()

        let viewModel = LevelsViewModel()
        viewModel.load(from: context, now: calendar.startOfDay(for: now).addingTimeInterval(60), calendar: calendar)
        viewModel.selectedRange = .oneWeek
        #expect(perWeek(viewModel, .chest) == 3)
    }

    @Test func libraryMusclesCoverEveryLibraryExercise() {
        #expect(LevelsViewModel.libraryMuscles.count == ExerciseLibrary.all.count)
        for exercise in ExerciseLibrary.all {
            #expect(LevelsViewModel.libraryMuscles[exercise.id]?.primary == exercise.primaryMuscles)
            #expect(LevelsViewModel.libraryMuscles[exercise.id]?.secondary == exercise.secondaryMuscles)
        }
    }

    private func sets(in viewModel: LevelsViewModel, exerciseId: String) -> Int? {
        viewModel.result.levels.flatMap(\.contributors).first { $0.exerciseKey == exerciseId }?.completedSets
    }

    private func loadBench(_ sets: [SetEntry]) throws -> LevelsViewModel {
        let log = ExerciseLog(
            exerciseName: "Barbell Bench Press", exerciseId: "barbell-bench-press", muscleGroups: ["chest"], orderIndex: 0, sets: sets
        )
        context.insert(WorkoutSession(date: day(-1), sessionName: "Session", exercises: [log]))
        try context.save()
        let viewModel = LevelsViewModel()
        viewModel.load(from: context, now: now, calendar: calendar)
        return viewModel
    }

    private func bench(_ number: Int, type: SetType = .normal, side: SetSide? = nil) -> SetEntry {
        SetEntry(setNumber: number, weightKg: 50, reps: 8, isCompleted: true, setType: type, side: side)
    }

    @Test func warmUpsDontCountButDropAndMyoRepsDo() throws {
        let viewModel = try loadBench([
            bench(1, type: .warmUp),
            bench(2),
            bench(3, type: .failure),
            bench(4, type: .drop),
            bench(5, type: .myoRep),
        ])
        #expect(sets(in: viewModel, exerciseId: "barbell-bench-press") == 4)
    }

    @Test func aWarmUpOnlySessionAddsNoSets() throws {
        let viewModel = try loadBench([bench(1, type: .warmUp)])
        #expect(sets(in: viewModel, exerciseId: "barbell-bench-press") == nil)
    }

    @Test func aLeftAndRightPairCountsOnce() throws {
        let viewModel = try loadBench([bench(1, side: .left), bench(2, side: .right), bench(3, side: .left)])
        #expect(sets(in: viewModel, exerciseId: "barbell-bench-press") == 2)
    }

    @Test func everySeededExerciseResolvesToTheLibrary() throws {
        // The seed is dated from the real clock, so load against it too.
        DemoSeeder.seed(into: context)
        let viewModel = LevelsViewModel()
        viewModel.load(from: context, calendar: calendar)
        viewModel.selectedRange = .twelveWeeks

        #expect(viewModel.result.excluded.isEmpty)
        #expect(viewModel.result.hasTraining)
    }
}
