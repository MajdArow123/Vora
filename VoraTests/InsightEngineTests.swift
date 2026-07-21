//
//  InsightEngineTests.swift
//  VoraTests
//
//  Created by Majd Arow on 2026-07-21.
//

import Foundation
import Testing
@testable import Vora

struct InsightEngineTests {
    /// A quiet baseline day that triggers no rule.
    private func baseInput(hour: Int = 10) -> InsightInput {
        InsightInput(
            date: .now,
            hour: hour,
            proteinConsumedG: 120,
            proteinTargetG: 160,
            caloriesConsumed: 1800,
            calorieTarget: 2600,
            isScheduledWorkoutDay: false,
            hasTrainedToday: false,
            streakDays: 3,
            consecutiveDailyWeightsKg: [],
            daysTracked: 12
        )
    }

    // MARK: - Individual rules

    @Test func proteinGapFiresAfter2pmWhenUnderHalf() {
        var input = baseInput(hour: 15)
        input.proteinConsumedG = 60 // < 50% of 160
        let insight = InsightEngine.generate(from: input)
        #expect(insight.rule == .proteinGap)
    }

    @Test func proteinGapDoesNotFireBefore2pm() {
        var input = baseInput(hour: 13)
        input.proteinConsumedG = 60
        #expect(InsightEngine.generate(from: input).rule != .proteinGap)
    }

    @Test func proteinGapDoesNotFireAtExactlyHalf() {
        var input = baseInput(hour: 15)
        input.proteinConsumedG = 80 // exactly 50%
        #expect(InsightEngine.generate(from: input).rule != .proteinGap)
    }

    @Test func missedWorkoutFiresOnScheduledUntrainedDay() {
        var input = baseInput()
        input.isScheduledWorkoutDay = true
        input.hasTrainedToday = false
        #expect(InsightEngine.generate(from: input).rule == .missedWorkout)
    }

    @Test func missedWorkoutDoesNotFireAfterTraining() {
        var input = baseInput()
        input.isScheduledWorkoutDay = true
        input.hasTrainedToday = true
        #expect(InsightEngine.generate(from: input).rule != .missedWorkout)
    }

    @Test(arguments: [7, 14, 30])
    func streakMilestoneFiresAtMilestones(days: Int) {
        var input = baseInput()
        input.streakDays = days
        #expect(InsightEngine.generate(from: input).rule == .streakMilestone)
    }

    @Test(arguments: [6, 8, 29, 31])
    func streakMilestoneSilentOffMilestones(days: Int) {
        var input = baseInput()
        input.streakDays = days
        #expect(InsightEngine.generate(from: input).rule != .streakMilestone)
    }

    @Test func calorieSurplusFiresOnlyBeyond200Over() {
        var input = baseInput()
        input.caloriesConsumed = Double(input.calorieTarget) + 201
        #expect(InsightEngine.generate(from: input).rule == .calorieSurplus)

        input.caloriesConsumed = Double(input.calorieTarget) + 200
        #expect(InsightEngine.generate(from: input).rule != .calorieSurplus)
    }

    @Test func weightTrendFiresOnThreeConsecutiveDrops() {
        var input = baseInput()
        input.consecutiveDailyWeightsKg = [80.5, 80.2, 79.9]
        #expect(InsightEngine.generate(from: input).rule == .weightTrendPositive)
    }

    @Test func weightTrendIgnoresNonMonotonicRun() {
        var input = baseInput()
        input.consecutiveDailyWeightsKg = [80.5, 80.6, 79.9]
        #expect(InsightEngine.generate(from: input).rule != .weightTrendPositive)
    }

    @Test func weightTrendNeedsThreeDays() {
        var input = baseInput()
        input.consecutiveDailyWeightsKg = [80.5, 80.2]
        #expect(InsightEngine.generate(from: input).rule != .weightTrendPositive)
    }

    @Test func weightTrendUsesLatestThreeOfLongerRun() {
        var input = baseInput()
        input.consecutiveDailyWeightsKg = [79.0, 80.5, 80.2, 79.9]
        #expect(InsightEngine.generate(from: input).rule == .weightTrendPositive)
    }

    // MARK: - Priority, exclusion, fallback

    @Test func streakMilestoneOutranksOtherMatches() {
        var input = baseInput(hour: 16)
        input.streakDays = 7
        input.proteinConsumedG = 10
        input.caloriesConsumed = Double(input.calorieTarget) + 500
        #expect(InsightEngine.generate(from: input).rule == .streakMilestone)
    }

    @Test func excludedRuleYieldsNextMatch() {
        var input = baseInput(hour: 16)
        input.proteinConsumedG = 10
        input.caloriesConsumed = Double(input.calorieTarget) + 500

        #expect(InsightEngine.generate(from: input).rule == .proteinGap)
        #expect(InsightEngine.generate(from: input, excluding: .proteinGap).rule == .calorieSurplus)
    }

    @Test func quietDayFallsBackToGenericInsight() {
        let insight = InsightEngine.generate(from: baseInput())
        #expect(insight.rule == nil)
        #expect(!insight.message.isEmpty)
    }

    /// Quality gate: seven consecutive days of realistic data produce
    /// seven insights with no rule repeating on consecutive days.
    @Test func sevenDaysNeverRepeatARule() {
        var lastRule: InsightRule?
        var rules: [InsightRule?] = []

        for day in 0..<7 {
            // Every day is a scheduled, untrained day with low protein and
            // a calorie surplus, so several rules always compete.
            var input = baseInput(hour: 16)
            input.isScheduledWorkoutDay = true
            input.proteinConsumedG = 10
            input.caloriesConsumed = Double(input.calorieTarget) + 300
            input.streakDays = day == 3 ? 7 : 3
            if day == 5 {
                input.consecutiveDailyWeightsKg = [81.0, 80.4, 80.1]
            }

            let insight = InsightEngine.generate(from: input, excluding: lastRule)
            rules.append(insight.rule)
            if let rule = insight.rule, let last = lastRule {
                #expect(rule != last, "day \(day) repeated rule \(rule)")
            }
            lastRule = insight.rule
        }

        #expect(rules.count == 7)
        #expect(rules.allSatisfy { $0 != nil })
    }
}
