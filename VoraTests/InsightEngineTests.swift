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

    // MARK: - Supplement rules

    @Test func supplementGapFiresAfter2pmWithUntakenName() {
        var input = baseInput(hour: 14)
        input.untakenEarlySupplementNames = ["Creatine", "Vitamin D"]
        let insight = InsightEngine.generate(from: input)
        #expect(insight.rule == .supplementGap)
        #expect(insight.message == "You haven't taken your Creatine today.")
    }

    @Test func supplementGapSilentBefore2pm() {
        var input = baseInput(hour: 13)
        input.untakenEarlySupplementNames = ["Creatine"]
        #expect(InsightEngine.generate(from: input).rule != .supplementGap)
    }

    @Test func supplementGapSilentWhenAllTaken() {
        let input = baseInput(hour: 16)
        #expect(InsightEngine.generate(from: input).rule != .supplementGap)
    }

    @Test(arguments: [7, 14, 30])
    func supplementStreakMilestoneFiresAtMilestones(days: Int) {
        var input = baseInput()
        input.supplementStreakDays = days
        #expect(InsightEngine.generate(from: input).rule == .supplementStreakMilestone)
    }

    @Test(arguments: [6, 8, 29, 31])
    func supplementStreakMilestoneSilentOffMilestones(days: Int) {
        var input = baseInput()
        input.supplementStreakDays = days
        #expect(InsightEngine.generate(from: input).rule != .supplementStreakMilestone)
    }

    @Test func proteinGapOutranksSupplementGap() {
        var input = baseInput(hour: 16)
        input.proteinConsumedG = 10
        input.untakenEarlySupplementNames = ["Creatine"]
        #expect(InsightEngine.generate(from: input).rule == .proteinGap)
        #expect(InsightEngine.generate(from: input, excluding: .proteinGap).rule == .supplementGap)
    }

    @Test func excludedSupplementGapDoesNotRepeat() {
        var input = baseInput(hour: 16)
        input.untakenEarlySupplementNames = ["Creatine"]
        #expect(InsightEngine.generate(from: input, excluding: .supplementGap).rule != .supplementGap)
    }

    // MARK: - AI protein suggestion

    @Test func aiProteinSuggestionFiresAfter6pmWithBigGap() {
        var input = baseInput(hour: 18)
        input.proteinConsumedG = 119 // remaining 41 > 40, but above half target
        let insight = InsightEngine.generate(from: input)
        #expect(insight.rule == .aiProteinSuggestion)
        #expect(insight.message == "You still need 41g of protein today. Tap for an AI meal suggestion.")
        #expect(insight.iconName == "sparkles")
    }

    @Test func aiProteinSuggestionSilentBefore6pm() {
        var input = baseInput(hour: 17)
        input.proteinConsumedG = 100
        #expect(InsightEngine.generate(from: input).rule != .aiProteinSuggestion)
    }

    @Test func aiProteinSuggestionSilentAtFortyGramsRemaining() {
        // baseInput leaves exactly 40 g remaining (120 of 160); the rule
        // needs strictly more than 40.
        let input = baseInput(hour: 18)
        #expect(InsightEngine.generate(from: input).rule != .aiProteinSuggestion)
    }

    @Test func aiProteinSuggestionSilentWithoutTarget() {
        var input = baseInput(hour: 18)
        input.proteinTargetG = 0
        input.proteinConsumedG = 0
        #expect(InsightEngine.generate(from: input).rule != .aiProteinSuggestion)
    }

    @Test func aiProteinSuggestionOutranksProteinGap() {
        var input = baseInput(hour: 18)
        input.proteinConsumedG = 60 // matches both rules
        #expect(InsightEngine.generate(from: input).rule == .aiProteinSuggestion)
        #expect(InsightEngine.generate(from: input, excluding: .aiProteinSuggestion).rule == .proteinGap)
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
