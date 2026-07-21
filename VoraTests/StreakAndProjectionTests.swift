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
