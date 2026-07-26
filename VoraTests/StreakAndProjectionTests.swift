//
//  StreakAndProjectionTests.swift
//  VoraTests
//
//  Created by Majd Arow on 2026-07-21.
//

import Foundation
import Testing
@testable import Vora

struct StreakAndProjectionTests {
    private let cal = Calendar.current

    private func day(_ offset: Int, from reference: Date = .now) -> Date {
        cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: reference))!
    }

    // MARK: - Adherence streak

    @Test func consecutiveTrainedDaysCount() {
        let streak = StreakCalculator.adherenceStreak(
            sessionDates: [day(-1), day(-2), day(-3)],
            restDayIndices: []
        )
        #expect(streak == 3)
    }

    @Test func untrainedTodayIsGraceNotBreak() {
        let withToday = StreakCalculator.adherenceStreak(
            sessionDates: [day(0), day(-1)],
            restDayIndices: []
        )
        let withoutToday = StreakCalculator.adherenceStreak(
            sessionDates: [day(-1)],
            restDayIndices: []
        )
        #expect(withToday == 2)
        #expect(withoutToday == 1)
    }

    @Test func restDaysCarryTheStreak() {
        // Yesterday was a rest day per the split; the day before was trained.
        let yesterdayIndex = (cal.component(.weekday, from: day(-1)) + 5) % 7
        let streak = StreakCalculator.adherenceStreak(
            sessionDates: [day(-2)],
            restDayIndices: [yesterdayIndex]
        )
        #expect(streak == 2)
    }

    @Test func missedTrainingDayBreaksTheStreak() {
        let streak = StreakCalculator.adherenceStreak(
            sessionDates: [day(-2), day(-3)],
            restDayIndices: []
        )
        #expect(streak == 0)
    }

    // MARK: - Food logging streak

    private func entries(_ offset: Int, _ slots: [MealSlot]) -> [(date: Date, slot: MealSlot)] {
        slots.map { (date: day(offset), slot: $0) }
    }

    @Test func threeDistinctSlotsQualify() {
        let qualifying = StreakCalculator.qualifyingFoodDays(
            entries: entries(-1, [.breakfast, .lunch, .dinner])
        )
        #expect(qualifying == [day(-1)])
    }

    @Test func twoSlotsDoNotQualify() {
        let qualifying = StreakCalculator.qualifyingFoodDays(
            entries: entries(-1, [.breakfast, .dinner])
        )
        #expect(qualifying.isEmpty)
    }

    @Test func duplicateEntriesInOneSlotCountOnce() {
        let qualifying = StreakCalculator.qualifyingFoodDays(
            entries: entries(-1, [.breakfast, .breakfast, .lunch])
        )
        #expect(qualifying.isEmpty)
    }

    @Test func foodStreakCountsConsecutiveDays() {
        let streak = StreakCalculator.foodStreak(qualifyingDays: [day(-1), day(-2), day(-3)])
        #expect(streak == 3)
    }

    @Test func incompleteTodayIsGraceNotBreakForFood() {
        let withToday = StreakCalculator.foodStreak(qualifyingDays: [day(0), day(-1)])
        let withoutToday = StreakCalculator.foodStreak(qualifyingDays: [day(-1)])
        #expect(withToday == 2)
        #expect(withoutToday == 1)
    }

    @Test func gapBreaksTheFoodStreak() {
        let streak = StreakCalculator.foodStreak(qualifyingDays: [day(-2), day(-3)])
        #expect(streak == 0)
    }

    @Test func emptyFoodDataMeansNoStreak() {
        #expect(StreakCalculator.foodStreak(qualifyingDays: []) == 0)
    }

    // MARK: - Suggested meal slot

    @Test func suggestedSlotFollowsTimeOfDay() {
        func at(_ hour: Int, _ minute: Int = 0) -> Date {
            cal.date(bySettingHour: hour, minute: minute, second: 0, of: cal.startOfDay(for: .now))!
        }
        #expect(MealSlot.suggested(for: at(0, 30)) == .breakfast)
        #expect(MealSlot.suggested(for: at(9, 59)) == .breakfast)
        #expect(MealSlot.suggested(for: at(10)) == .postWorkout)
        #expect(MealSlot.suggested(for: at(12, 59)) == .postWorkout)
        #expect(MealSlot.suggested(for: at(13)) == .lunch)
        #expect(MealSlot.suggested(for: at(15, 59)) == .lunch)
        #expect(MealSlot.suggested(for: at(16)) == .dinner)
        #expect(MealSlot.suggested(for: at(19, 59)) == .dinner)
        #expect(MealSlot.suggested(for: at(20)) == .snack)
        #expect(MealSlot.suggested(for: at(23)) == .snack)
    }

    // MARK: - Trailing week dots

    @Test func trailingWeekMarksTrainedDays() {
        let dots = StreakCalculator.trailingWeek(sessionDates: [day(0), day(-2), day(-6)])
        #expect(dots == [true, false, false, false, true, false, true])
    }

    @Test func trailingWeekIgnoresOlderSessions() {
        let dots = StreakCalculator.trailingWeek(sessionDates: [day(-7), day(-30)])
        #expect(dots == Array(repeating: false, count: 7))
    }

    // MARK: - Consecutive daily weights

    @Test func consecutiveWeightsStopAtGaps() {
        let entries = [
            WeightEntry(date: day(-5), weightKg: 82.0),
            // gap at -4 breaks the run
            WeightEntry(date: day(-2), weightKg: 81.0),
            WeightEntry(date: day(-1), weightKg: 80.6),
            WeightEntry(date: day(0), weightKg: 80.2),
        ]
        let run = HomeViewModel.consecutiveDailyWeights(from: entries, calendar: cal)
        #expect(run == [81.0, 80.6, 80.2])
    }

    @Test func latestEntryPerDayWins() {
        let entries = [
            WeightEntry(date: day(0), weightKg: 80.8),
            WeightEntry(date: day(0).addingTimeInterval(3600), weightKg: 80.2),
        ]
        let run = HomeViewModel.consecutiveDailyWeights(from: entries, calendar: cal)
        #expect(run == [80.2])
    }

    // MARK: - Goal projection

    @Test func projectsDateWhenTrendingTowardGoal() throws {
        // Losing 0.1 kg/day, 2 kg from goal → about 20 days out.
        let entries = (0...10).map { offset in
            WeightEntry(date: day(offset - 10), weightKg: 83.0 - 0.1 * Double(offset))
        }
        let projection = ProgressViewModel.projectGoal(weightsAscending: entries, goalWeightKg: 80.0)
        let projected = try #require(projection)
        let days = cal.dateComponents([.day], from: .now, to: projected.projectedDate).day!
        #expect((15...25).contains(days))
    }

    @Test func noProjectionWithoutGoalWeight() {
        let entries = [
            WeightEntry(date: day(-4), weightKg: 82.0),
            WeightEntry(date: day(0), weightKg: 81.0),
        ]
        #expect(ProgressViewModel.projectGoal(weightsAscending: entries, goalWeightKg: 0) == nil)
    }

    @Test func noProjectionWhenTrendMovesAway() {
        let entries = [
            WeightEntry(date: day(-4), weightKg: 82.0),
            WeightEntry(date: day(0), weightKg: 83.0),
        ]
        #expect(ProgressViewModel.projectGoal(weightsAscending: entries, goalWeightKg: 80.0) == nil)
    }

    @Test func noProjectionFromASingleDayOfData() {
        let entries = [
            WeightEntry(date: day(0), weightKg: 82.0),
            WeightEntry(date: day(0).addingTimeInterval(3600), weightKg: 81.9),
        ]
        #expect(ProgressViewModel.projectGoal(weightsAscending: entries, goalWeightKg: 80.0) == nil)
    }
}
