//
//  ActiveSessionViewModelTests.swift
//  VoraTests
//
//  Created by Majd Arow on 2026-07-21.
//

import Foundation
import SwiftData
import Testing
@testable import Vora

struct ActiveSessionViewModelTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            UserProfile.self, FoodEntry.self, CustomFood.self,
            WorkoutSession.self, ExerciseLog.self, SetEntry.self,
            WeightEntry.self, WaterEntry.self, CardioEntry.self, SplitDay.self,
            SavedMeal.self, SavedMealItem.self, Recipe.self, RecipeIngredient.self,
        ])
        return try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
    }

    private func insertSession(
        _ context: ModelContext,
        date: Date,
        exercise: String,
        sets: [(weight: Double, reps: Int, done: Bool)]
    ) {
        let entries = sets.enumerated().map { index, set in
            SetEntry(setNumber: index + 1, weightKg: set.weight, reps: set.reps, isCompleted: set.done)
        }
        let log = ExerciseLog(exerciseName: exercise, orderIndex: 0, sets: entries)
        context.insert(WorkoutSession(date: date, sessionName: "Session", exercises: [log]))
    }

    // MARK: - Draft parsing and formatting

    @Test func draftSetParsesWeightAndReps() {
        var set = ActiveSessionViewModel.DraftSet()
        set.weightText = "100"
        set.repsText = "8"
        #expect(set.weightKg == 100)
        #expect(set.reps == 8)
    }

    @Test func draftSetAcceptsCommaDecimalWeight() {
        var set = ActiveSessionViewModel.DraftSet()
        set.weightText = "82,5"
        #expect(set.weightKg == 82.5)
    }

    @Test func draftSetRejectsBlankAndNonNumericInput() {
        var set = ActiveSessionViewModel.DraftSet()
        #expect(set.weightKg == nil)
        #expect(set.reps == nil)
        set.weightText = "abc"
        set.repsText = "five"
        #expect(set.weightKg == nil)
        #expect(set.reps == nil)
    }

    @Test func previousSetTextDropsTrailingZeroForWholeWeights() {
        let whole = ActiveSessionViewModel.PreviousSet(weightKg: 100, reps: 8)
        #expect(whole.text == "100×8")
        let fractional = ActiveSessionViewModel.PreviousSet(weightKg: 82.5, reps: 5)
        #expect(fractional.text == "82.5×5")
    }

    @Test func weightStringFormatsWholeAndFractionalValues() {
        #expect(ActiveSessionViewModel.weightString(100) == "100")
        #expect(ActiveSessionViewModel.weightString(82.5) == "82.5")
    }

    // MARK: - Exercise management

    @Test func addExerciseWithNoHistoryStartsWithOneEmptySet() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let viewModel = ActiveSessionViewModel(sessionName: "Push")

        viewModel.addExercise(name: "Bench Press", muscleGroups: ["chest"], context: context)

        #expect(viewModel.exercises.count == 1)
        let exercise = try #require(viewModel.exercises.first)
        #expect(exercise.sets.count == 1)
        #expect(exercise.sets[0].weightText.isEmpty)
        #expect(exercise.sets[0].repsText.isEmpty)
        #expect(exercise.previousSets.isEmpty)
    }

    @Test func addExercisePrefillsFromMostRecentSessionCaseInsensitively() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let cal = Calendar.current
        insertSession(
            context,
            date: cal.date(byAdding: .day, value: -2, to: .now)!,
            exercise: "bench press",
            sets: [(60, 10, true), (62.5, 8, true), (65, 6, false)]
        )
        try context.save()

        let viewModel = ActiveSessionViewModel(sessionName: "Push")
        viewModel.addExercise(name: "Bench Press", muscleGroups: ["chest"], context: context)

        let exercise = try #require(viewModel.exercises.first)
        #expect(exercise.previousSets.count == 2)
        #expect(exercise.previousSets.map(\.text) == ["60×10", "62.5×8"])
        #expect(exercise.sets[0].weightText == "60")
        #expect(exercise.sets[0].repsText == "10")
    }

    @Test func previousSetsFallBackPastSessionsWithOnlyIncompleteSets() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let cal = Calendar.current
        insertSession(
            context,
            date: cal.date(byAdding: .day, value: -7, to: .now)!,
            exercise: "Squat",
            sets: [(100, 5, true)]
        )
        insertSession(
            context,
            date: cal.date(byAdding: .day, value: -1, to: .now)!,
            exercise: "Squat",
            sets: [(110, 5, false)]
        )
        try context.save()

        let viewModel = ActiveSessionViewModel(sessionName: "Legs")
        viewModel.addExercise(name: "Squat", muscleGroups: ["quads"], context: context)

        let exercise = try #require(viewModel.exercises.first)
        #expect(exercise.previousSets.count == 1)
        #expect(exercise.previousSets.first?.weightKg == 100)
    }

    @Test func removeExerciseDeletesOnlyThatExercise() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let viewModel = ActiveSessionViewModel(sessionName: "Push")
        viewModel.addExercise(name: "Bench", muscleGroups: [], context: context)
        viewModel.addExercise(name: "Fly", muscleGroups: [], context: context)

        viewModel.removeExercise(viewModel.exercises[0].id)

        #expect(viewModel.exercises.count == 1)
        #expect(viewModel.exercises.first?.name == "Fly")
    }

    @Test func addSetCopiesLastSetValues() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let viewModel = ActiveSessionViewModel(sessionName: "Push")
        viewModel.addExercise(name: "Bench", muscleGroups: [], context: context)
        viewModel.exercises[0].sets[0].weightText = "80"
        viewModel.exercises[0].sets[0].repsText = "8"

        viewModel.addSet(to: viewModel.exercises[0].id)

        let sets = viewModel.exercises[0].sets
        #expect(sets.count == 2)
        #expect(sets[1].weightText == "80")
        #expect(sets[1].repsText == "8")
        #expect(!sets[1].isCompleted)
    }

    @Test func removeSetDeletesOnlyThatSet() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let viewModel = ActiveSessionViewModel(sessionName: "Push")
        viewModel.addExercise(name: "Bench", muscleGroups: [], context: context)
        viewModel.addSet(to: viewModel.exercises[0].id)
        let firstID = viewModel.exercises[0].sets[0].id

        viewModel.removeSet(firstID, from: viewModel.exercises[0].id)

        #expect(viewModel.exercises[0].sets.count == 1)
        #expect(viewModel.exercises[0].sets.first?.id != firstID)
    }

    // MARK: - Set completion

    @Test func toggleCompletionCompletesValidSetAndReportsTransition() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let viewModel = ActiveSessionViewModel(sessionName: "Push")
        viewModel.addExercise(name: "Bench", muscleGroups: [], context: context)
        viewModel.exercises[0].sets[0].weightText = "100"
        viewModel.exercises[0].sets[0].repsText = "5"

        let started = viewModel.toggleCompletion(
            setID: viewModel.exercises[0].sets[0].id,
            in: viewModel.exercises[0].id
        )

        #expect(started)
        #expect(viewModel.exercises[0].sets[0].isCompleted)
    }

    @Test func toggleCompletionUncompletesWithoutReportingTransition() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let viewModel = ActiveSessionViewModel(sessionName: "Push")
        viewModel.addExercise(name: "Bench", muscleGroups: [], context: context)
        viewModel.exercises[0].sets[0].weightText = "100"
        viewModel.exercises[0].sets[0].repsText = "5"
        _ = viewModel.toggleCompletion(setID: viewModel.exercises[0].sets[0].id, in: viewModel.exercises[0].id)

        let second = viewModel.toggleCompletion(
            setID: viewModel.exercises[0].sets[0].id,
            in: viewModel.exercises[0].id
        )

        #expect(!second)
        #expect(!viewModel.exercises[0].sets[0].isCompleted)
    }

    @Test func toggleCompletionRejectsMissingOrZeroReps() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let viewModel = ActiveSessionViewModel(sessionName: "Push")
        viewModel.addExercise(name: "Bench", muscleGroups: [], context: context)
        viewModel.exercises[0].sets[0].weightText = "100"

        #expect(!viewModel.toggleCompletion(
            setID: viewModel.exercises[0].sets[0].id,
            in: viewModel.exercises[0].id
        ))

        viewModel.exercises[0].sets[0].repsText = "0"
        #expect(!viewModel.toggleCompletion(
            setID: viewModel.exercises[0].sets[0].id,
            in: viewModel.exercises[0].id
        ))
        #expect(!viewModel.exercises[0].sets[0].isCompleted)
    }

    @Test func toggleCompletionRejectsMissingWeightButAllowsZeroWeight() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let viewModel = ActiveSessionViewModel(sessionName: "Push")
        viewModel.addExercise(name: "Pull Up", muscleGroups: [], context: context)
        viewModel.exercises[0].sets[0].repsText = "10"

        #expect(!viewModel.toggleCompletion(
            setID: viewModel.exercises[0].sets[0].id,
            in: viewModel.exercises[0].id
        ))

        viewModel.exercises[0].sets[0].weightText = "0"
        #expect(viewModel.toggleCompletion(
            setID: viewModel.exercises[0].sets[0].id,
            in: viewModel.exercises[0].id
        ))
    }

    @Test func toggleCompletionWithUnknownIDsReturnsFalse() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let viewModel = ActiveSessionViewModel(sessionName: "Push")
        viewModel.addExercise(name: "Bench", muscleGroups: [], context: context)

        #expect(!viewModel.toggleCompletion(setID: UUID(), in: viewModel.exercises[0].id))
        #expect(!viewModel.toggleCompletion(setID: viewModel.exercises[0].sets[0].id, in: UUID()))
    }

    // MARK: - Live stats

    @Test func totalVolumeCountsOnlyCompletedParseableSets() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let viewModel = ActiveSessionViewModel(sessionName: "Push")

        viewModel.addExercise(name: "Bench", muscleGroups: [], context: context)
        viewModel.exercises[0].sets[0].weightText = "100"
        viewModel.exercises[0].sets[0].repsText = "5"
        _ = viewModel.toggleCompletion(setID: viewModel.exercises[0].sets[0].id, in: viewModel.exercises[0].id)
        viewModel.addSet(to: viewModel.exercises[0].id) // copied 100x5, left incomplete

        viewModel.addExercise(name: "Cable Fly", muscleGroups: [], context: context)
        viewModel.exercises[1].sets[0].weightText = "20"
        viewModel.exercises[1].sets[0].repsText = "8"
        _ = viewModel.toggleCompletion(setID: viewModel.exercises[1].sets[0].id, in: viewModel.exercises[1].id)

        #expect(viewModel.totalVolumeKg == 660) // 100*5 + 20*8
        #expect(viewModel.completedSetCount == 2)
    }

    @Test func canFinishRequiresACompletedSet() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let viewModel = ActiveSessionViewModel(sessionName: "Push")
        #expect(!viewModel.canFinish)

        viewModel.addExercise(name: "Bench", muscleGroups: [], context: context)
        #expect(!viewModel.canFinish)

        viewModel.exercises[0].sets[0].weightText = "100"
        viewModel.exercises[0].sets[0].repsText = "5"
        _ = viewModel.toggleCompletion(setID: viewModel.exercises[0].sets[0].id, in: viewModel.exercises[0].id)
        #expect(viewModel.canFinish)
    }

    @Test func elapsedSecondsIsNonNegativeAtStart() {
        let viewModel = ActiveSessionViewModel(sessionName: "Push")
        #expect(viewModel.elapsedSeconds >= 0)
        #expect(viewModel.elapsedSeconds < 5)
    }

    // MARK: - Rest timer
    //
    // Only synchronous state transitions are tested. Actual countdown
    // expiry needs real elapsed time and is intentionally not covered.

    @Test func startRestSetsEndDateDurationAhead() throws {
        let viewModel = ActiveSessionViewModel(sessionName: "Push")
        #expect(viewModel.restEndDate == nil)

        viewModel.startRest(duration: 90)

        let remaining = try #require(viewModel.restEndDate).timeIntervalSinceNow
        #expect(remaining > 85)
        #expect(remaining <= 90)
    }

    @Test func cancelRestClearsEndDate() {
        let viewModel = ActiveSessionViewModel(sessionName: "Push")
        viewModel.startRest(duration: 120)
        viewModel.cancelRest()
        #expect(viewModel.restEndDate == nil)
    }

    @Test func startRestAgainReplacesEndDate() {
        let viewModel = ActiveSessionViewModel(sessionName: "Push")
        viewModel.startRest(duration: 60)
        let first = viewModel.restEndDate
        viewModel.startRest(duration: 180)
        let second = viewModel.restEndDate
        #expect(second != nil)
        #expect(second! > first!)
    }

    // MARK: - Finish

    @Test func finishPersistsCompletedWorkAndDropsEmptyExercises() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let viewModel = ActiveSessionViewModel(sessionName: "Push Day")

        viewModel.addExercise(name: "Bench Press", muscleGroups: ["chest"], context: context)
        viewModel.exercises[0].sets[0].weightText = "100"
        viewModel.exercises[0].sets[0].repsText = "5"
        _ = viewModel.toggleCompletion(setID: viewModel.exercises[0].sets[0].id, in: viewModel.exercises[0].id)
        viewModel.addSet(to: viewModel.exercises[0].id) // incomplete, must not be saved
        viewModel.addExercise(name: "Fly", muscleGroups: [], context: context) // no completed sets

        viewModel.finish(context: context)

        let summary = try #require(viewModel.summary)
        #expect(summary.exerciseCount == 1)
        #expect(summary.setCount == 1)
        #expect(summary.totalVolumeKg == 500)

        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        #expect(sessions.count == 1)
        let session = try #require(sessions.first)
        #expect(session.sessionName == "Push Day")
        #expect(session.totalVolumeKg == 500)
        #expect(session.exercises.count == 1)
        #expect(session.exercises.first?.exerciseName == "Bench Press")
        #expect(session.exercises.first?.sets.count == 1)
        #expect(session.exercises.first?.sets.first?.isCompleted == true)
    }

    @Test func finishRenumbersSavedSetsSequentially() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let viewModel = ActiveSessionViewModel(sessionName: "Legs")

        viewModel.addExercise(name: "Squat", muscleGroups: [], context: context)
        viewModel.addSet(to: viewModel.exercises[0].id)
        viewModel.addSet(to: viewModel.exercises[0].id)
        // Complete only sets 2 and 3; set 1 stays blank.
        for index in [1, 2] {
            viewModel.exercises[0].sets[index].weightText = index == 1 ? "100" : "110"
            viewModel.exercises[0].sets[index].repsText = "5"
            _ = viewModel.toggleCompletion(
                setID: viewModel.exercises[0].sets[index].id,
                in: viewModel.exercises[0].id
            )
        }

        viewModel.finish(context: context)

        let session = try #require(try context.fetch(FetchDescriptor<WorkoutSession>()).first)
        let saved = try #require(session.exercises.first).sets.sorted { $0.setNumber < $1.setNumber }
        #expect(saved.map(\.setNumber) == [1, 2])
        #expect(saved.map(\.weightKg) == [100, 110])
    }

    @Test func finishDetectsPRAgainstPriorHistory() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        insertSession(
            context,
            date: Calendar.current.date(byAdding: .day, value: -7, to: .now)!,
            exercise: "Bench Press",
            sets: [(100, 5, true)]
        )
        try context.save()

        let viewModel = ActiveSessionViewModel(sessionName: "Push")
        viewModel.addExercise(name: "Bench Press", muscleGroups: [], context: context)
        viewModel.exercises[0].sets[0].weightText = "105"
        viewModel.exercises[0].sets[0].repsText = "3"
        _ = viewModel.toggleCompletion(setID: viewModel.exercises[0].sets[0].id, in: viewModel.exercises[0].id)

        viewModel.finish(context: context)

        let summary = try #require(viewModel.summary)
        #expect(summary.newPRs.count == 1)
        #expect(summary.newPRs.first?.weightKg == 105)
        #expect(summary.newPRs.first?.reps == 3)
    }

    @Test func finishDoesNotAwardPRForEqualOrLowerWeight() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        insertSession(
            context,
            date: Calendar.current.date(byAdding: .day, value: -7, to: .now)!,
            exercise: "Bench Press",
            sets: [(100, 5, true)]
        )
        try context.save()

        let viewModel = ActiveSessionViewModel(sessionName: "Push")
        viewModel.addExercise(name: "bench press", muscleGroups: [], context: context)
        viewModel.exercises[0].sets[0].weightText = "100"
        viewModel.exercises[0].sets[0].repsText = "8"
        _ = viewModel.toggleCompletion(setID: viewModel.exercises[0].sets[0].id, in: viewModel.exercises[0].id)

        viewModel.finish(context: context)

        #expect(viewModel.summary?.newPRs.isEmpty == true)
    }

    @Test func finishWithNoHistoryAwardsPRForAnyPositiveWeight() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let viewModel = ActiveSessionViewModel(sessionName: "Push")
        viewModel.addExercise(name: "Overhead Press", muscleGroups: [], context: context)
        viewModel.exercises[0].sets[0].weightText = "40"
        viewModel.exercises[0].sets[0].repsText = "8"
        _ = viewModel.toggleCompletion(setID: viewModel.exercises[0].sets[0].id, in: viewModel.exercises[0].id)

        viewModel.finish(context: context)

        #expect(viewModel.summary?.newPRs.first?.weightKg == 40)
    }

    @Test func finishBodyweightOnlyWorkIsNotAPR() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let viewModel = ActiveSessionViewModel(sessionName: "Calisthenics")
        viewModel.addExercise(name: "Pull Up", muscleGroups: [], context: context)
        viewModel.exercises[0].sets[0].weightText = "0"
        viewModel.exercises[0].sets[0].repsText = "10"
        _ = viewModel.toggleCompletion(setID: viewModel.exercises[0].sets[0].id, in: viewModel.exercises[0].id)

        viewModel.finish(context: context)

        let summary = try #require(viewModel.summary)
        #expect(summary.newPRs.isEmpty)
        #expect(summary.setCount == 1)
    }
}
