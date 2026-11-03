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

    /// Daily weigh-ins ending today (or `endOffset`), oldest first.
    private func trend(
        days: Int,
        endOffset: Int = 0,
        weight: (Int) -> Double
    ) -> WeightTrendSeries? {
        let entries = (0..<days).map { index in
            WeightEntry(date: day(endOffset - (days - 1 - index)), weightKg: weight(index))
        }
        return WeightTrendSeries(entries: entries, calendar: cal)
    }

    @Test func projectsFromTheTrendsRecentRate() throws {
        // Losing 0.1 kg/day for 60 days, so the trend has settled to that rate
        // and sits about 1 kg behind the scale.
        let series = try #require(trend(days: 60) { 86 - 0.1 * Double($0) })
        let rate = try #require(series.result.ratePerDay(window: ProgressViewModel.projectionWindowDays))
        #expect(abs(rate + 0.1) < 0.01)

        let goal = series.currentKg - 2
        let projection = ProgressViewModel.projectGoal(trend: series, goalWeightKg: goal)
        guard case .projected(let goalKg, let date) = projection else {
            Issue.record("Expected a date, got \(projection)")
            return
        }
        #expect(goalKg == goal)
        let days = try #require(cal.dateComponents([.day], from: day(0), to: date).day)
        #expect((18...22).contains(days))
    }

    @Test func oneOutlierBarelyMovesTheProjection() throws {
        let steady = try #require(trend(days: 60) { 86 - 0.1 * Double($0) })
        let spiked = try #require(trend(days: 60) { 86 - 0.1 * Double($0) + ($0 == 59 ? 3 : 0) })
        // A straight line through the same spike would swing by 3 kg.
        #expect(abs(spiked.currentKg - steady.currentKg - 0.3) < 0.0001)
    }

    @Test func underTenLoggedDaysIsNotEnoughData() {
        let projection = ProgressViewModel.projectGoal(
            trend: trend(days: 9) { 83 - 0.1 * Double($0) },
            goalWeightKg: 80
        )
        #expect(projection == .notEnoughData(loggedDays: 9, needed: 10))
    }

    @Test func tenLoggedDaysIsEnough() {
        let projection = ProgressViewModel.projectGoal(
            trend: trend(days: 10) { 83 - 0.1 * Double($0) },
            goalWeightKg: 80
        )
        if case .projected = projection {} else {
            Issue.record("Expected a date, got \(projection)")
        }
    }

    @Test func staleWeighInsAreNotEnoughData() {
        let series = trend(days: 30, endOffset: -15) { 83 - 0.1 * Double($0) }
        let projection = ProgressViewModel.projectGoal(trend: series, goalWeightKg: 70)
        #expect(projection == .notEnoughData(loggedDays: 30, needed: 10))
    }

    @Test func oneReadingInTheRateWindowIsNotEnoughData() {
        // Ten old days, then one weigh-in today after a long gap.
        var entries = (0..<10).map { WeightEntry(date: day($0 - 40), weightKg: 83) }
        entries.append(WeightEntry(date: day(0), weightKg: 82))
        let projection = ProgressViewModel.projectGoal(
            trend: WeightTrendSeries(entries: entries, calendar: cal),
            goalWeightKg: 70
        )
        #expect(projection == .notEnoughData(loggedDays: 11, needed: 10))
    }

    @Test func noWeighInsAreNotEnoughData() {
        #expect(ProgressViewModel.projectGoal(trend: nil, goalWeightKg: 80) == .notEnoughData(loggedDays: 0, needed: 10))
    }

    @Test func noProjectionWithoutGoalWeight() {
        let projection = ProgressViewModel.projectGoal(trend: trend(days: 20) { _ in 82 }, goalWeightKg: 0)
        #expect(projection == .noGoal)
    }

    @Test func trendMovingAwayFromGoalGivesNoDate() {
        let projection = ProgressViewModel.projectGoal(
            trend: trend(days: 20) { 82 + 0.1 * Double($0) },
            goalWeightKg: 80
        )
        #expect(projection == .notMovingTowardGoal)
    }

    @Test func flatTrendGivesNoDate() {
        let projection = ProgressViewModel.projectGoal(trend: trend(days: 20) { _ in 82 }, goalWeightKg: 80)
        #expect(projection == .notMovingTowardGoal)
    }

    @Test func projectionBeyondTwoYearsGivesNoDate() {
        // About 0.001 kg/day with 20 kg to go.
        let projection = ProgressViewModel.projectGoal(
            trend: trend(days: 60) { 100 - 0.001 * Double($0) },
            goalWeightKg: 80
        )
        #expect(projection == .notMovingTowardGoal)
    }

    @Test func trendAtTheGoalHasReachedIt() {
        let projection = ProgressViewModel.projectGoal(trend: trend(days: 20) { _ in 80 }, goalWeightKg: 80)
        #expect(projection == .goalReached(goalKg: 80))
    }
}
