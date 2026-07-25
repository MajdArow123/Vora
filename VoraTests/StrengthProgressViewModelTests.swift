//
//  StrengthProgressViewModelTests.swift
//  VoraTests
//
//  Created by Majd Arow on 2026-07-25.
//

import Foundation
import SwiftData
import Testing
@testable import Vora

struct StrengthProgressViewModelTests {
    private let calendar = Calendar.current
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    private var thisWeekStart: Date {
        calendar.dateInterval(of: .weekOfYear, for: now)!.start
    }

    private func weekStart(_ offset: Int) -> Date {
        calendar.date(byAdding: .weekOfYear, value: offset, to: thisWeekStart)!
    }

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

    private func insertVolumeSession(_ context: ModelContext, date: Date, volume: Double) {
        context.insert(WorkoutSession(
            date: date,
            sessionName: "Session",
            durationSeconds: 3600,
            totalVolumeKg: volume,
            exercises: []
        ))
    }

    /// Inserts a session with a single exercise; each tuple becomes a set.
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

    private func insertCardio(
        _ context: ModelContext,
        date: Date,
        minutes: Int,
        calories: Double
    ) {
        context.insert(CardioEntry(
            date: date,
            type: .treadmill,
            durationSeconds: minutes * 60,
            estimatedCalories: calories
        ))
    }

    private func fetchSessions(_ context: ModelContext) throws -> [WorkoutSession] {
        try context.fetch(FetchDescriptor<WorkoutSession>(sortBy: [SortDescriptor(\.date)]))
    }

    // MARK: - Weekly volume

    @Test func sameWeekSessionsSumIntoOneBucket() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        insertVolumeSession(context, date: thisWeekStart.addingTimeInterval(3600), volume: 5000)
        insertVolumeSession(context, date: thisWeekStart.addingTimeInterval(26 * 3600), volume: 3000)
        try context.save()

        let points = StrengthProgressViewModel.weeklyVolume(
            sessions: try fetchSessions(context), range: .all, now: now, calendar: calendar
        )
        #expect(points.count == 1)
        #expect(points.first?.volumeKg == 8000)
        #expect(points.first?.weekStart == thisWeekStart)
    }

    @Test func weekBoundarySplitsIntoSeparateBuckets() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        insertVolumeSession(context, date: weekStart(-1).addingTimeInterval(3600), volume: 4000)
        insertVolumeSession(context, date: thisWeekStart.addingTimeInterval(3600), volume: 6000)
        try context.save()

        let points = StrengthProgressViewModel.weeklyVolume(
            sessions: try fetchSessions(context), range: .all, now: now, calendar: calendar
        )
        #expect(points.count == 2)
        #expect(points.map(\.volumeKg) == [4000, 6000])
    }

    @Test func emptyWeekBetweenActiveWeeksIsGapFilledWithZero() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        insertVolumeSession(context, date: weekStart(-2).addingTimeInterval(3600), volume: 4000)
        insertVolumeSession(context, date: thisWeekStart.addingTimeInterval(3600), volume: 6000)
        try context.save()

        let points = StrengthProgressViewModel.weeklyVolume(
            sessions: try fetchSessions(context), range: .all, now: now, calendar: calendar
        )
        #expect(points.count == 3)
        #expect(points.map(\.volumeKg) == [4000, 0, 6000])
        #expect(points[1].weekStart == weekStart(-1))
    }

    @Test func rangeCutoffExcludesOldSessions() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let old = calendar.date(byAdding: .day, value: -100, to: now)!
        insertVolumeSession(context, date: old, volume: 9000)
        insertVolumeSession(context, date: thisWeekStart.addingTimeInterval(3600), volume: 6000)
        try context.save()

        let quarter = StrengthProgressViewModel.weeklyVolume(
            sessions: try fetchSessions(context), range: .quarter, now: now, calendar: calendar
        )
        #expect(quarter.map(\.volumeKg).reduce(0, +) == 6000)

        let all = StrengthProgressViewModel.weeklyVolume(
            sessions: try fetchSessions(context), range: .all, now: now, calendar: calendar
        )
        #expect(all.map(\.volumeKg).reduce(0, +) == 15000)
    }

    @Test func noSessionsProducesNoPoints() {
        let points = StrengthProgressViewModel.weeklyVolume(
            sessions: [], range: .all, now: now, calendar: calendar
        )
        #expect(points.isEmpty)
    }

    // MARK: - Weekly cardio

    @Test func weeklyCardioSumsMinutesAndCalories() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        insertCardio(context, date: thisWeekStart.addingTimeInterval(3600), minutes: 30, calories: 300)
        insertCardio(context, date: thisWeekStart.addingTimeInterval(50 * 3600), minutes: 25, calories: 250)
        insertCardio(context, date: weekStart(-1).addingTimeInterval(3600), minutes: 20, calories: 200)
        try context.save()

        let entries = try context.fetch(
            FetchDescriptor<CardioEntry>(sortBy: [SortDescriptor(\.date)])
        )
        let points = StrengthProgressViewModel.weeklyCardio(
            entries: entries, range: .all, now: now, calendar: calendar
        )
        #expect(points.count == 2)
        #expect(points[0].minutes == 20)
        #expect(points[0].calories == 200)
        #expect(points[1].minutes == 55)
        #expect(points[1].calories == 550)
    }

    // MARK: - Distinct exercise names

    @Test func distinctNamesDedupeCaseInsensitivelyAndSort() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        insertSession(context, date: weekStart(-1), exercise: "Squat", sets: [(120, 5, true)])
        insertSession(context, date: thisWeekStart, exercise: "bench press", sets: [(90, 8, true)])
        insertSession(context, date: now, exercise: "Bench Press", sets: [(100, 5, true)])
        try context.save()

        let names = StrengthProgression.distinctExerciseNames(in: try fetchSessions(context))
        #expect(names == ["bench press", "Squat"])
    }

    @Test func exercisesWithoutQualifyingSetsAreExcluded() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        insertSession(context, date: thisWeekStart, exercise: "Deadlift", sets: [(180, 3, false)])
        insertSession(context, date: now, exercise: "Push Up", sets: [(0, 20, true)])
        insertSession(context, date: now, exercise: "Squat", sets: [(120, 5, true)])
        try context.save()

        let names = StrengthProgression.distinctExerciseNames(in: try fetchSessions(context))
        #expect(names == ["Squat"])
    }

    // MARK: - Session stats

    @Test func sessionStatsPickBestSetPerSession() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        insertSession(context, date: weekStart(-1), exercise: "Bench Press",
                      sets: [(90, 8, true), (100, 5, true), (95, 6, true)])
        insertSession(context, date: thisWeekStart, exercise: "Bench Press",
                      sets: [(102.5, 4, true)])
        try context.save()

        let stats = StrengthProgression.sessionStats(
            for: "Bench Press", sessions: try fetchSessions(context)
        )
        #expect(stats.count == 2)
        #expect(stats[0].bestWeightKg == 100)
        #expect(stats[0].completedSets == 3)
        #expect(stats[1].bestWeightKg == 102.5)
        #expect(stats[0].date < stats[1].date)
    }

    @Test func sessionStatsBreakWeightTiesByHigherReps() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        insertSession(context, date: now, exercise: "Squat",
                      sets: [(120, 5, true), (120, 8, true), (120, 3, true)])
        try context.save()

        let stats = StrengthProgression.sessionStats(
            for: "Squat", sessions: try fetchSessions(context)
        )
        #expect(stats.first?.bestReps == 8)
    }

    @Test func sessionStatsExcludeIncompleteAndOtherExercises() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        insertSession(context, date: now, exercise: "Deadlift",
                      sets: [(200, 1, false), (150, 5, true)])
        insertSession(context, date: now, exercise: "Row", sets: [(80, 8, true)])
        try context.save()

        let stats = StrengthProgression.sessionStats(
            for: "Deadlift", sessions: try fetchSessions(context)
        )
        #expect(stats.count == 1)
        #expect(stats.first?.bestWeightKg == 150)
        #expect(stats.first?.completedSets == 1)
    }

    @Test func sessionStatsIncludeIndividualSetsSortedBySetNumber() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        insertSession(context, date: now, exercise: "Lat Pulldown",
                      sets: [(30, 12, true), (30, 12, true), (27.5, 10, true), (25, 8, false)])
        try context.save()

        let stat = try #require(StrengthProgression.sessionStats(
            for: "Lat Pulldown", sessions: try fetchSessions(context)
        ).first)
        #expect(stat.sets.map(\.setNumber) == [1, 2, 3])
        #expect(stat.sets.map(\.weightKg) == [30, 30, 27.5])
        #expect(stat.sets.map(\.reps) == [12, 12, 10])
        #expect(stat.setsSummary == "3 sets × 10–12 reps")
    }

    @Test func sessionStatEstimatedOneRepMaxUsesEpley() {
        let stat = ExerciseSessionStat(
            id: UUID(), date: .now, bestWeightKg: 100, bestReps: 10, completedSets: 3
        )
        #expect(abs(stat.estimatedOneRepMax - 133.3333) < 0.001)
    }

    // MARK: - Load

    @Test func loadDefaultsSelectionToHeaviestPRExercise() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        insertSession(context, date: weekStart(-1), exercise: "Bench Press", sets: [(100, 5, true)])
        insertSession(context, date: thisWeekStart, exercise: "Squat", sets: [(140, 5, true)])
        try context.save()

        let viewModel = StrengthProgressViewModel()
        viewModel.load(from: context, now: now)

        #expect(viewModel.selectedExercise == "Squat")
        #expect(viewModel.exerciseNames == ["Bench Press", "Squat"])
    }

    @Test func loadKeepsValidExistingSelection() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        insertSession(context, date: weekStart(-1), exercise: "Bench Press", sets: [(100, 5, true)])
        insertSession(context, date: thisWeekStart, exercise: "Squat", sets: [(140, 5, true)])
        try context.save()

        let viewModel = StrengthProgressViewModel()
        viewModel.selectedExercise = "Bench Press"
        viewModel.load(from: context, now: now)

        #expect(viewModel.selectedExercise == "Bench Press")
    }

    @Test func loadWithNoSessionsLeavesEverythingEmpty() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let viewModel = StrengthProgressViewModel()
        viewModel.load(from: context, now: now)

        #expect(viewModel.exerciseNames.isEmpty)
        #expect(viewModel.selectedExercise == nil)
        #expect(viewModel.progression.isEmpty)
        #expect(viewModel.weeklyVolume.isEmpty)
        #expect(viewModel.weeklyCardio.isEmpty)
    }
}
