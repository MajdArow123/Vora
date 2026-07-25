//
//  WorkoutHomeViewModelTests.swift
//  VoraTests
//
//  Created by Majd Arow on 2026-07-21.
//

import Foundation
import SwiftData
import Testing
@testable import Vora

struct WorkoutHomeViewModelTests {
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

    private func insertProfile(_ context: ModelContext, split: TrainingSplit = .ppl) {
        context.insert(UserProfile(
            name: "Test User",
            dateOfBirth: Calendar.current.date(byAdding: .year, value: -30, to: .now)!,
            heightCm: 180,
            biologicalSex: .male,
            goalType: .fatLoss,
            activityLevel: .moderatelyActive,
            trainingSplit: split,
            dailyCalorieTarget: 2400,
            proteinTargetG: 170,
            carbsTargetG: 250,
            fatTargetG: 70
        ))
    }

    /// Inserts a session with a single exercise; each tuple becomes a set.
    private func insertSession(
        _ context: ModelContext,
        date: Date = .now,
        exercise: String,
        sets: [(weight: Double, reps: Int, done: Bool)]
    ) {
        let entries = sets.enumerated().map { index, set in
            SetEntry(setNumber: index + 1, weightKg: set.weight, reps: set.reps, isCompleted: set.done)
        }
        let log = ExerciseLog(exerciseName: exercise, orderIndex: 0, sets: entries)
        context.insert(WorkoutSession(date: date, sessionName: "Session", exercises: [log]))
    }

    // MARK: - Personal records

    @Test func bestWeightPerExerciseWins() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        insertSession(context, exercise: "Bench Press", sets: [(90, 8, true), (100, 5, true)])
        try context.save()

        let records = WorkoutHomeViewModel.computePersonalRecords(from: context)
        #expect(records.count == 1)
        #expect(records.first?.weightKg == 100)
        #expect(records.first?.reps == 5)
    }

    @Test func equalWeightPrefersHigherReps() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        insertSession(context, exercise: "Squat", sets: [(120, 5, true), (120, 8, true), (120, 3, true)])
        try context.save()

        let records = WorkoutHomeViewModel.computePersonalRecords(from: context)
        #expect(records.first?.weightKg == 120)
        #expect(records.first?.reps == 8)
    }

    @Test func incompleteSetsAreExcluded() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        insertSession(context, exercise: "Deadlift", sets: [(180, 3, false), (140, 5, true)])
        try context.save()

        let records = WorkoutHomeViewModel.computePersonalRecords(from: context)
        #expect(records.first?.weightKg == 140)
    }

    @Test func zeroWeightAndZeroRepSetsAreExcluded() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        insertSession(context, exercise: "Push Up", sets: [(0, 20, true), (50, 0, true)])
        try context.save()

        let records = WorkoutHomeViewModel.computePersonalRecords(from: context)
        #expect(records.isEmpty)
    }

    @Test func exerciseNameGroupingIsCaseInsensitive() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let cal = Calendar.current
        insertSession(
            context,
            date: cal.date(byAdding: .day, value: -2, to: .now)!,
            exercise: "bench press",
            sets: [(95, 5, true)]
        )
        insertSession(context, exercise: "Bench Press", sets: [(100, 5, true)])
        try context.save()

        let records = WorkoutHomeViewModel.computePersonalRecords(from: context)
        #expect(records.count == 1)
        #expect(records.first?.weightKg == 100)
    }

    @Test func recordsAreSortedByWeightDescending() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        insertSession(context, exercise: "Curl", sets: [(20, 10, true)])
        insertSession(context, exercise: "Squat", sets: [(140, 5, true)])
        insertSession(context, exercise: "Bench", sets: [(100, 5, true)])
        try context.save()

        let records = WorkoutHomeViewModel.computePersonalRecords(from: context)
        #expect(records.map(\.weightKg) == [140, 100, 20])
    }

    @Test func limitCapsReturnedRecords() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        insertSession(context, exercise: "Curl", sets: [(20, 10, true)])
        insertSession(context, exercise: "Squat", sets: [(140, 5, true)])
        insertSession(context, exercise: "Bench", sets: [(100, 5, true)])
        try context.save()

        let limited = WorkoutHomeViewModel.computePersonalRecords(from: context, limit: 2)
        #expect(limited.count == 2)
        #expect(limited.map(\.weightKg) == [140, 100])
    }

    @Test func recordDateComesFromAchievingSession() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let cal = Calendar.current
        let prDate = cal.date(byAdding: .day, value: -3, to: .now)!
        insertSession(context, date: prDate, exercise: "Row", sets: [(80, 8, true)])
        insertSession(context, exercise: "Row", sets: [(70, 10, true)])
        try context.save()

        let records = WorkoutHomeViewModel.computePersonalRecords(from: context)
        #expect(records.first?.date == prDate)
    }

    @Test func recordCarriesSetCountAndRepRangeFromAchievingSession() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        insertSession(context, exercise: "Lat Pulldown", sets: [
            (30, 12, true), (30, 12, true), (27.5, 10, true), (27.5, 10, true), (25, 8, false),
        ])
        try context.save()

        let record = try #require(WorkoutHomeViewModel.computePersonalRecords(from: context).first)
        #expect(record.totalSets == 4)
        #expect(record.minReps == 10)
        #expect(record.maxReps == 12)
    }

    @Test func setStatsComeFromTheAchievingSessionNotTheLatest() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let cal = Calendar.current
        let prDate = cal.date(byAdding: .day, value: -3, to: .now)!
        insertSession(context, date: prDate, exercise: "Row",
                      sets: [(80, 8, true), (80, 8, true), (75, 8, true)])
        insertSession(context, exercise: "Row", sets: [(70, 10, true), (70, 10, true)])
        try context.save()

        let record = try #require(WorkoutHomeViewModel.computePersonalRecords(from: context).first)
        #expect(record.totalSets == 3)
        #expect(record.minReps == 8)
        #expect(record.maxReps == 8)
    }

    // MARK: - Sets summary formatting

    @Test func setsSummaryShowsRepRangeWhenRepsVary() {
        let record = PersonalRecord(
            exerciseName: "Bench", weightKg: 100, reps: 10, date: .now,
            totalSets: 4, minReps: 10, maxReps: 12
        )
        #expect(record.setsSummary == "4 sets × 10–12 reps")
    }

    @Test func setsSummaryCollapsesUniformReps() {
        let record = PersonalRecord(
            exerciseName: "Bench", weightKg: 100, reps: 8, date: .now,
            totalSets: 4, minReps: 8, maxReps: 8
        )
        #expect(record.setsSummary == "4 sets × 8 reps")
    }

    @Test func setsSummaryUsesSingularSetAndRep() {
        let record = PersonalRecord(
            exerciseName: "Deadlift", weightKg: 200, reps: 1, date: .now,
            totalSets: 1, minReps: 1, maxReps: 1
        )
        #expect(record.setsSummary == "1 set × 1 rep")
    }

    // MARK: - Epley estimate

    @Test func estimatedOneRepMaxUsesEpleyFormula() {
        let record = PersonalRecord(exerciseName: "Bench", weightKg: 100, reps: 10, date: .now)
        #expect(abs(record.estimatedOneRepMax - 133.3333) < 0.001)

        let single = PersonalRecord(exerciseName: "Bench", weightKg: 100, reps: 1, date: .now)
        #expect(abs(single.estimatedOneRepMax - 103.3333) < 0.001)
    }

    // MARK: - Split day seeding

    @Test func loadSeedsSevenDaysFromProfileTemplate() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        insertProfile(context, split: .ppl)
        try context.save()

        let viewModel = WorkoutHomeViewModel()
        viewModel.load(from: context)

        #expect(viewModel.splitDays.count == 7)
        let expectedTitles = TrainingSplit.ppl.weeklyTemplate.map(\.title)
        #expect(viewModel.splitDays.sorted { $0.dayIndex < $1.dayIndex }.map(\.title) == expectedTitles)

        let stored = try context.fetch(FetchDescriptor<SplitDay>())
        #expect(stored.count == 7)
    }

    @Test func loadDoesNotReseedWhenSevenDaysExist() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        insertProfile(context, split: .ppl)
        for index in 0..<7 {
            context.insert(SplitDay(dayIndex: index, title: "Custom \(index)"))
        }
        try context.save()

        let viewModel = WorkoutHomeViewModel()
        viewModel.load(from: context)

        #expect(viewModel.splitDays.count == 7)
        #expect(viewModel.splitDays.first?.title == "Custom 0")
        #expect(viewModel.splitDays.allSatisfy { $0.title.hasPrefix("Custom") })
    }

    @Test func loadReplacesPartialSeedWithFullTemplate() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        insertProfile(context, split: .fullBody)
        for index in 0..<3 {
            context.insert(SplitDay(dayIndex: index, title: "Stale \(index)"))
        }
        try context.save()

        let viewModel = WorkoutHomeViewModel()
        viewModel.load(from: context)

        #expect(viewModel.splitDays.count == 7)
        #expect(viewModel.splitDays.allSatisfy { !$0.title.hasPrefix("Stale") })
        let stored = try context.fetch(FetchDescriptor<SplitDay>())
        #expect(stored.count == 7)
    }

    @Test func loadWithoutProfileFallsBackToFullBodyTemplate() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let viewModel = WorkoutHomeViewModel()
        viewModel.load(from: context)

        let titles = viewModel.splitDays.sorted { $0.dayIndex < $1.dayIndex }.map(\.title)
        #expect(titles == TrainingSplit.fullBody.weeklyTemplate.map(\.title))
    }

    @Test func todaySplitDayMatchesTodayIndex() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        insertProfile(context)
        try context.save()

        let viewModel = WorkoutHomeViewModel()
        viewModel.load(from: context)

        #expect(viewModel.todaySplitDay?.dayIndex == viewModel.todayIndex)
    }

    // MARK: - Day states

    @Test func untrainedWeekStatesFollowTodayRelativeRules() {
        let viewModel = WorkoutHomeViewModel()
        let today = viewModel.todayIndex

        for index in 0..<7 {
            let day = SplitDay(dayIndex: index, title: "Training")
            let expected: SplitDayState = index == today
                ? .today
                : (index > today ? .upcoming : .missed)
            #expect(viewModel.state(for: day) == expected, "index \(index), today \(today)")
        }
    }

    @Test func restDayIsRestWhenUntrained() {
        let viewModel = WorkoutHomeViewModel()
        for index in 0..<7 {
            let day = SplitDay(dayIndex: index, title: "Rest", isRest: true)
            #expect(viewModel.state(for: day) == .rest)
        }
    }

    @Test func trainedTodayMarksDayDone() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        insertSession(context, exercise: "Bench", sets: [(100, 5, true)])
        try context.save()

        let viewModel = WorkoutHomeViewModel()
        viewModel.load(from: context)

        let trainingDay = SplitDay(dayIndex: viewModel.todayIndex, title: "Push")
        #expect(viewModel.state(for: trainingDay) == .done)
    }

    @Test func doneOutranksRestWhenTrainedOnRestDay() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        insertSession(context, exercise: "Bench", sets: [(100, 5, true)])
        try context.save()

        let viewModel = WorkoutHomeViewModel()
        viewModel.load(from: context)

        let restDay = SplitDay(dayIndex: viewModel.todayIndex, title: "Rest", isRest: true)
        #expect(viewModel.state(for: restDay) == .done)
    }

    // MARK: - hasTrainedToday

    @Test func hasTrainedTodayFalseWithNoSessions() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let viewModel = WorkoutHomeViewModel()
        viewModel.load(from: context)

        #expect(!viewModel.hasTrainedToday)
    }

    @Test func hasTrainedTodayTrueAfterSessionToday() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        insertSession(context, exercise: "Bench", sets: [(100, 5, true)])
        try context.save()

        let viewModel = WorkoutHomeViewModel()
        viewModel.load(from: context)

        #expect(viewModel.hasTrainedToday)
    }

    @Test func hasTrainedTodayFalseForYesterdaySession() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        insertSession(context, date: yesterday, exercise: "Bench", sets: [(100, 5, true)])
        try context.save()

        let viewModel = WorkoutHomeViewModel()
        viewModel.load(from: context)

        #expect(!viewModel.hasTrainedToday)
    }
}
