//
//  CoachingEngineTests.swift
//  VoraTests
//
//  Created by Majd Arow on 2026-11-03.
//

import Foundation
import Testing
@testable import Vora

@MainActor
struct CoachingEngineTests {
    private typealias Engine = CoachingEngine

    private static let asOf = 100

    /// Sessions `spacing` days apart, ending `lastDayAgo` days before the
    /// as-of day, lying on a straight line centred on 100 kg, so the lift's
    /// weekly change is exactly `percent`.
    private static func lift(
        _ key: String,
        percent: Double,
        sessions: Int = 4,
        spacing: Int = 7,
        lastDayAgo: Int = 0,
        reps: Int = 8,
        setType: SetType = .normal
    ) -> [Engine.StrengthSet] {
        let days = (0..<sessions).map { asOf - lastDayAgo - spacing * $0 }
        let center = Double(days.reduce(0, +)) / Double(days.count)
        return days.map { day in
            Engine.StrengthSet(
                exerciseKey: key,
                dayOffset: day,
                weightKg: 100 * (1 + percent / 100 * (Double(day) - center) / 7),
                reps: reps,
                setType: setType
            )
        }
    }

    private static func trend(_ sets: [Engine.StrengthSet]) -> Engine.StrengthTrend {
        Engine.strengthTrend(sets: sets, asOfDay: asOf)
    }

    private static func usable(_ trend: Engine.StrengthTrend) -> Int? {
        if case .notEnoughData(let usable) = trend { usable } else { nil }
    }

    private static let falling = Engine.StrengthTrend.falling(percentPerWeek: -1)
    private static let flat = Engine.StrengthTrend.flat(percentPerWeek: 0)
    private static let rising = Engine.StrengthTrend.rising(percentPerWeek: 1)
    private static let noData = Engine.StrengthTrend.notEnoughData(usableLifts: 0)

    private static func advice(
        goal: GoalType = .fatLoss,
        expenditure: Double = 3000,
        current: Int = 2400,
        intake: Double = 2400,
        rate: Double = -0.5,
        strength: Engine.StrengthTrend = .flat(percentPerWeek: 0),
        previous: Engine.StrengthTrend = .flat(percentPerWeek: 0),
        bmr: Double = 1780
    ) -> Engine.Advice {
        Engine.advise(Engine.Input(
            goal: goal,
            expenditure: expenditure,
            currentCalories: current,
            proposedTargets: CalorieCalculator.targets(fromExpenditure: expenditure, weightKg: 80, goal: goal, bmr: bmr),
            averageIntake: intake,
            weightKgPerWeek: rate,
            strength: strength,
            previousStrength: previous,
            weightKg: 80,
            bmr: bmr
        ))
    }

    // MARK: - Strength trend thresholds

    @Test func slightlyBeyondThePositiveThresholdIsRising() {
        let trend = Self.trend(Self.lift("a", percent: 0.51) + Self.lift("b", percent: 0.51))
        guard case .rising(let percent) = trend else {
            Issue.record("Expected rising, got \(trend)")
            return
        }
        #expect(abs(percent - 0.51) < 1e-6)
    }

    @Test func justInsideThePositiveThresholdIsFlat() {
        let trend = Self.trend(Self.lift("a", percent: 0.49) + Self.lift("b", percent: 0.49))
        if case .flat = trend {} else { Issue.record("Expected flat, got \(trend)") }
    }

    @Test func slightlyBeyondTheNegativeThresholdIsFalling() {
        #expect(Self.trend(Self.lift("a", percent: -0.51) + Self.lift("b", percent: -0.51)).isFalling)
    }

    @Test func justInsideTheNegativeThresholdIsFlat() {
        let trend = Self.trend(Self.lift("a", percent: -0.49) + Self.lift("b", percent: -0.49))
        if case .flat = trend {} else { Issue.record("Expected flat, got \(trend)") }
    }

    @Test func theMedianLiftDecides() {
        let trend = Self.trend(
            Self.lift("a", percent: 5) + Self.lift("b", percent: -1) + Self.lift("c", percent: -2)
        )
        guard case .falling(let percent) = trend else {
            Issue.record("Expected falling, got \(trend)")
            return
        }
        #expect(abs(percent + 1) < 1e-6)
    }

    @Test func theTwoMiddleLiftsAverageWithAnEvenCount() {
        let trend = Self.trend(Self.lift("a", percent: 1) + Self.lift("b", percent: 3))
        guard case .rising(let percent) = trend else {
            Issue.record("Expected rising, got \(trend)")
            return
        }
        #expect(abs(percent - 2) < 1e-6)
    }

    // MARK: - Too little data

    @Test func noSetsIsNotEnoughData() {
        #expect(Self.usable(Self.trend([])) == 0)
    }

    @Test func oneUsableLiftIsNotEnoughButTwoAre() {
        #expect(Self.usable(Self.trend(Self.lift("a", percent: 1))) == 1)
        #expect(Self.usable(Self.trend(Self.lift("a", percent: 1) + Self.lift("b", percent: 1))) == nil)
    }

    @Test func aLiftNeedsThreeSessions() {
        let good = Self.lift("good", percent: 1)
        #expect(Self.usable(Self.trend(good + Self.lift("short", percent: 1, sessions: 2, spacing: 14))) == 1)
        #expect(Self.usable(Self.trend(good + Self.lift("enough", percent: 1, sessions: 3))) == nil)
    }

    @Test func aLiftNeedsAFourteenDaySpan() {
        let good = Self.lift("good", percent: 1)
        // Sessions on days 0, 6 and 13 back span 13 days; 0, 7 and 14 span 14.
        let narrow = [0, 6, 13].map {
            Engine.StrengthSet(exerciseKey: "narrow", dayOffset: Self.asOf - $0, weightKg: 100, reps: 8, setType: .normal)
        }
        #expect(Self.usable(Self.trend(good + narrow)) == 1)
        #expect(Self.usable(Self.trend(good + Self.lift("wide", percent: 1, sessions: 3, spacing: 7))) == nil)
    }

    @Test func aLiftDroppedTwoWeeksAgoStopsCounting() {
        let good = Self.lift("good", percent: 1)
        #expect(Self.usable(Self.trend(good + Self.lift("recent", percent: 1, sessions: 3, lastDayAgo: 13))) == nil)
        #expect(Self.usable(Self.trend(good + Self.lift("dropped", percent: 1, sessions: 3, lastDayAgo: 14))) == 1)
    }

    @Test func sessionsOutsideTheWindowDontCount() {
        // Only the last 2 of these sessions are inside the 28 days.
        let good = Self.lift("good", percent: 1)
        let old = Self.lift("old", percent: 1, sessions: 3, spacing: 14, lastDayAgo: 14)
        #expect(Self.usable(Self.trend(good + old)) == 1)
    }

    // MARK: - Which sets count

    @Test(arguments: [SetType.warmUp, .drop, .myoRep])
    func nonRecordSetsDontCount(type: SetType) {
        let good = Self.lift("good", percent: 1)
        #expect(Self.usable(Self.trend(good + Self.lift("other", percent: 1, setType: type))) == 1)
    }

    @Test func failureSetsCount() {
        let good = Self.lift("good", percent: 1)
        #expect(Self.usable(Self.trend(good + Self.lift("other", percent: 1, setType: .failure))) == nil)
    }

    @Test func setsOverFifteenRepsDontCountButFifteenDoes() {
        let good = Self.lift("good", percent: 1)
        #expect(Self.usable(Self.trend(good + Self.lift("high", percent: 1, reps: 16))) == 1)
        #expect(Self.usable(Self.trend(good + Self.lift("edge", percent: 1, reps: 15))) == nil)
    }

    @Test func zeroWeightDoesntCount() {
        let good = Self.lift("good", percent: 1)
        let bodyweight = (0..<4).map {
            Engine.StrengthSet(exerciseKey: "pull-up", dayOffset: Self.asOf - 7 * $0, weightKg: 0, reps: 8, setType: .normal)
        }
        #expect(Self.usable(Self.trend(good + bodyweight)) == 1)
    }

    @Test func theBestSetOfASessionIsWhatCounts() {
        let backOffs = (0..<4).map {
            Engine.StrengthSet(exerciseKey: "a", dayOffset: Self.asOf - 7 * $0, weightKg: 30, reps: 8, setType: .normal)
        }
        let flat = (0..<4).map {
            Engine.StrengthSet(exerciseKey: "a", dayOffset: Self.asOf - 7 * $0, weightKg: 100, reps: 8, setType: .normal)
        }
        let trend = Self.trend(backOffs + flat + Self.lift("b", percent: 0))
        if case .flat = trend {} else { Issue.record("Expected flat, got \(trend)") }
    }

    // MARK: - Top lifts

    @Test func onlyTheFiveMostFrequentLiftsCount() {
        let top = (0..<5).flatMap { Self.lift("top\($0)", percent: 1, sessions: 4) }
        // Three more sessions than nothing, but fewer than the top five.
        let rare = (0..<6).flatMap { Self.lift("rare\($0)", percent: -9, sessions: 3) }
        let trend = Self.trend(top + rare)
        if case .rising = trend {} else { Issue.record("Expected rising, got \(trend)") }
    }

    @Test func aTieInSessionsGoesToTheHigherVolume() {
        let heavy = (0..<5).flatMap { index in
            Self.lift("heavy\(index)", percent: 1, reps: 10)
        }
        let light = (0..<3).flatMap { index in
            Self.lift("light\(index)", percent: -9, reps: 5)
        }
        let trend = Self.trend(heavy + light)
        if case .rising = trend {} else { Issue.record("Expected rising, got \(trend)") }
    }

    // MARK: - Falling for two check-ins

    @Test func fallingOnlyNowOffersNothing() {
        #expect(Self.advice(strength: Self.falling, previous: Self.flat).rule == .noChange)
    }

    @Test func fallingOnlyLastWeekOffersNothing() {
        #expect(Self.advice(strength: Self.flat, previous: Self.falling).rule == .noChange)
    }

    @Test func fallingNowWithNoDataLastWeekIsntConsecutive() {
        #expect(Self.advice(strength: Self.falling, previous: Self.noData).rule == .noChange)
    }

    @Test func fallingForTwoCheckInsEasesTheDeficit() {
        let advice = Self.advice(strength: Self.falling, previous: Self.falling)
        #expect(advice.rule == .easeDeficit(reasons: [.strengthFalling(percentPerWeek: -1)]))
        #expect(advice.adjustment?.deltaKcal == 100)
    }

    // MARK: - Losing too fast

    /// At 3,000 kcal the fat-loss goal is about −0.545 kg/week, so 1.5× is −0.818.
    @Test func justUnderOnePointFiveTimesTheGoalRateOffersNothing() {
        #expect(Self.advice(rate: -0.81).rule == .noChange)
    }

    @Test func overOnePointFiveTimesTheGoalRateEasesTheDeficit() {
        let advice = Self.advice(rate: -0.83)
        guard case .easeDeficit(let reasons) = advice.rule, case .losingTooFast(let rate, let goal) = reasons.first else {
            Issue.record("Expected easeDeficit, got \(advice.rule)")
            return
        }
        #expect(rate == -0.83)
        #expect(abs(goal + 3000 * 0.2 * 7 / 7700) < 1e-9)
        #expect(advice.adjustment?.deltaKcal == 150)
    }

    @Test func gainingOnAFatLossGoalIsntLosingTooFast() {
        #expect(Self.advice(rate: 0.5).rule == .noChange)
    }

    @Test func bothSignalsShareOneAdjustment() {
        let advice = Self.advice(rate: -1.0, strength: Self.falling, previous: Self.falling)
        guard case .easeDeficit(let reasons) = advice.rule else {
            Issue.record("Expected easeDeficit, got \(advice.rule)")
            return
        }
        #expect(reasons.count == 2)
        #expect(advice.adjustment?.deltaKcal == 150)
    }

    @Test func losingTooFastStillFiresWithoutTrainingData() {
        let advice = Self.advice(rate: -1.0, strength: Self.noData, previous: Self.noData)
        guard case .easeDeficit = advice.rule else {
            Issue.record("Expected easeDeficit, got \(advice.rule)")
            return
        }
        #expect(Self.usable(advice.strength) == 0)
    }

    // MARK: - Adherence

    /// ±10% of 2,400 is 2,160 to 2,640.
    @Test func theEdgesOfTheToleranceCountAsOnTarget() {
        let adherence = [2160.0, 2640.0].map { Engine.Adherence(averageIntake: $0, targetCalories: 2400) }
        #expect(adherence == [.onTarget, .onTarget])
    }

    @Test func beyondTheToleranceIsUnderOrOver() {
        #expect(Engine.Adherence(averageIntake: 2159, targetCalories: 2400) == .under)
        #expect(Engine.Adherence(averageIntake: 2641, targetCalories: 2400) == .over)
    }

    @Test func eatingUnderTargetAsksForThatInsteadOfAnAdjustment() {
        let advice = Self.advice(intake: 2159, strength: Self.falling, previous: Self.falling)
        #expect(advice.rule == .eatToTarget(reasons: [.strengthFalling(percentPerWeek: -1)]))
        #expect(advice.adjustment == nil)
    }

    @Test func eatingOverTargetOffersNoEasing() {
        let advice = Self.advice(intake: 2641, strength: Self.falling, previous: Self.falling)
        #expect(advice.rule == .overTargetDeficit(reasons: [.strengthFalling(percentPerWeek: -1)]))
        #expect(advice.adjustment == nil)
    }

    @Test func gainingFastWhileOverTargetOffersNoTrim() {
        let advice = Self.advice(goal: .muscleGain, current: 3360, intake: 3700, rate: 0.5)
        #expect(advice.adjustment == nil)
        guard case .overTargetSurplus = advice.rule else {
            Issue.record("Expected overTargetSurplus, got \(advice.rule)")
            return
        }
    }

    @Test func gainingFastWhileUnderTargetOffersNoTrim() {
        let advice = Self.advice(goal: .muscleGain, current: 3360, intake: 3000, rate: 0.5)
        #expect(advice.adjustment == nil)
        guard case .underTargetSurplus = advice.rule else {
            Issue.record("Expected underTargetSurplus, got \(advice.rule)")
            return
        }
    }

    // MARK: - Gain

    /// At 3,000 kcal the gain goal is about +0.327 kg/week, so 1.25× is +0.409.
    @Test func justUnderTheGainThresholdOffersNothing() {
        #expect(Self.advice(goal: .muscleGain, current: 3360, intake: 3360, rate: 0.40).rule == .noChange)
    }

    @Test func overTheGainThresholdWithFlatStrengthTrims() {
        let advice = Self.advice(goal: .muscleGain, current: 3360, intake: 3360, rate: 0.42)
        guard case .trimSurplus = advice.rule else {
            Issue.record("Expected trimSurplus, got \(advice.rule)")
            return
        }
        #expect(advice.adjustment?.deltaKcal == -100)
    }

    @Test func gainingFastWithRisingStrengthIsOnTrack() {
        let advice = Self.advice(goal: .muscleGain, current: 3360, intake: 3360, rate: 0.6, strength: Self.rising)
        #expect(advice.rule == .onTrack)
        #expect(advice.adjustment == nil)
    }

    @Test func gainingFastWithFallingStrengthOffersNoTrim() {
        let advice = Self.advice(goal: .muscleGain, current: 3360, intake: 3360, rate: 0.6, strength: Self.falling)
        #expect(advice.rule == .noChange)
    }

    @Test(arguments: [GoalType.muscleGain, .maintain])
    func risingStrengthIsOnTrack(goal: GoalType) {
        let advice = Self.advice(goal: goal, rate: 0, strength: Self.rising)
        #expect(advice.rule == .onTrack)
    }

    @Test func maintainingWithFlatOrFallingStrengthOffersNothing() {
        #expect(Self.advice(goal: .maintain, rate: 0, strength: Self.flat).rule == .noChange)
        #expect(Self.advice(goal: .maintain, rate: 0, strength: Self.falling).rule == .noChange)
    }

    // MARK: - Not enough training data

    @Test(arguments: GoalType.allCases)
    func noTrainingDataSaysSoAndOffersNoAdjustment(goal: GoalType) {
        let advice = Self.advice(goal: goal, rate: 0, strength: Self.noData, previous: Self.noData)
        #expect(advice.rule == .notEnoughTrainingData)
        #expect(advice.adjustment == nil)
    }

    @Test func gainingFastWithoutTrainingDataDoesntTrim() {
        let advice = Self.advice(goal: .muscleGain, current: 3360, intake: 3360, rate: 0.8, strength: Self.noData)
        #expect(advice.rule == .notEnoughTrainingData)
    }

    // MARK: - Floors and limits

    @Test func easingNeverGoesAboveExpenditure() throws {
        // Held at the 1,780 floor with expenditure just above it.
        let advice = Self.advice(expenditure: 1800, current: 1780, intake: 1780, rate: -1, bmr: 1780)
        let adjustment = try #require(advice.adjustment)
        #expect(adjustment.targets.calories == 1800)
        #expect(adjustment.deltaKcal == 20)
    }

    @Test func easingWithNoRoomOffersNoAdjustmentButKeepsTheRule() {
        let advice = Self.advice(expenditure: 1780, current: 1780, intake: 1780, rate: -1, bmr: 1780)
        #expect(advice.adjustment == nil)
        guard case .easeDeficit = advice.rule else {
            Issue.record("Expected easeDeficit, got \(advice.rule)")
            return
        }
    }

    @Test func trimmingNeverGoesBelowTheFloor() {
        let advice = Self.advice(goal: .muscleGain, expenditure: 1800, current: 2100, intake: 2100, rate: 0.5, bmr: 2100)
        #expect(advice.adjustment == nil)
    }

    @Test func aTrimStopsAtTheFloor() throws {
        // 1.12 × 2,000 = 2,240; a 100 kcal trim would be 2,140, floor is 2,200.
        let advice = Self.advice(goal: .muscleGain, expenditure: 2000, current: 2240, intake: 2240, rate: 0.5, bmr: 2200)
        let adjustment = try #require(advice.adjustment)
        #expect(adjustment.targets.calories == 2200)
    }

    @Test func aTrimNeverGoesBelowExpenditure() {
        let targets = ExpenditureTargets(calories: 2050, proteinG: 150, carbsG: 200, fatG: 60, isFloored: false)
        let trimmed = CalorieCalculator.adjusted(targets, byKcal: -100, expenditure: 2000, weightKg: 80, goal: .muscleGain, bmr: 1500)
        #expect(trimmed?.calories == 2000)
    }

    // MARK: - Goal multipliers and macros

    @Test func theAdjustmentSitsOnTopOfTheGoalMultiplier() throws {
        let easy = try #require(Self.advice(expenditure: 3000, rate: -1).adjustment)
        #expect(easy.targets.calories == 2400 + 150)
        let trim = try #require(Self.advice(goal: .muscleGain, current: 3360, intake: 3360, rate: 0.6).adjustment)
        #expect(trim.targets.calories == 3360 - 100)
    }

    @Test func theAdjustmentKeepsProteinAndMovesTheRest() throws {
        let proposed = CalorieCalculator.targets(fromExpenditure: 3000, weightKg: 80, goal: .fatLoss, bmr: 1780)
        let adjusted = try #require(Self.advice(rate: -1).adjustment).targets
        #expect(adjusted.proteinG == proposed.proteinG)
        #expect(adjusted.carbsG > proposed.carbsG)
        #expect(adjusted.fatG > proposed.fatG)
    }

    @Test func goalRateFollowsTheMultiplier() {
        let loss: Double = -3000 * 0.2 * 7 / 7700
        let gain: Double = 3000 * 0.12 * 7 / 7700
        #expect(abs(CalorieCalculator.goalWeeklyRateKg(expenditure: 3000, goal: .fatLoss) - loss) < 1e-9)
        #expect(CalorieCalculator.goalWeeklyRateKg(expenditure: 3000, goal: .maintain) == 0)
        #expect(abs(CalorieCalculator.goalWeeklyRateKg(expenditure: 3000, goal: .muscleGain) - gain) < 1e-9)
    }

    // MARK: - Deficit

    @Test func exactlyTenPercentIsMeaningful() {
        #expect(Engine.deficitPercent(loggedDays: Array(repeating: 2700, count: 4), expenditure: 3000) == 10)
    }

    @Test func justUnderTenPercentIsNot() {
        #expect(Engine.deficitPercent(loggedDays: Array(repeating: 2701, count: 4), expenditure: 3000) == nil)
    }

    @Test func aSurplusIsNotADeficit() {
        #expect(Engine.deficitPercent(loggedDays: Array(repeating: 3300, count: 7), expenditure: 3000) == nil)
    }

    @Test func tooFewDaysSayNothing() {
        #expect(Engine.deficitPercent(loggedDays: Array(repeating: 2000, count: 3), expenditure: 3000) == nil)
        #expect(Engine.deficitPercent(loggedDays: Array(repeating: 2000, count: 4), expenditure: 3000) == 33)
    }

    @Test func halfLoggedDaysDontCount() {
        // 40% of 3,000 is 1,200: the short day neither counts nor drags the average.
        let days = [2400.0, 2400, 2400, 2400, 300]
        #expect(Engine.deficitPercent(loggedDays: days, expenditure: 3000) == 20)
        #expect(Engine.deficitPercent(loggedDays: [2400, 2400, 2400, 300], expenditure: 3000) == nil)
    }

    @Test func noExpenditureSaysNothing() {
        #expect(Engine.deficitPercent(loggedDays: Array(repeating: 2000, count: 7), expenditure: 0) == nil)
    }

    // MARK: - Explanation

    @Test func everyRuleExplainsItselfInBothUnits() {
        let reasons: [Engine.EaseReason] = [
            .strengthFalling(percentPerWeek: -1),
            .losingTooFast(kgPerWeek: -1, goalKgPerWeek: -0.5),
        ]
        let rules: [Engine.Rule] = [
            .easeDeficit(reasons: reasons),
            .trimSurplus(kgPerWeek: 0.5, goalKgPerWeek: 0.3),
            .eatToTarget(reasons: reasons),
            .overTargetDeficit(reasons: reasons),
            .overTargetSurplus(kgPerWeek: 0.5, goalKgPerWeek: 0.3),
            .underTargetSurplus(kgPerWeek: 0.5, goalKgPerWeek: 0.3),
            .onTrack,
            .notEnoughTrainingData,
            .noChange,
        ]
        for rule in rules {
            let advice = Engine.Advice(strength: Self.flat, previousStrength: Self.flat, rule: rule, adjustment: nil)
            #expect(!CoachingExplanation.detail(advice, units: .metric).isEmpty)
            #expect(!CoachingExplanation.detail(advice, units: .imperial).isEmpty)
        }
    }

    @Test func ratesFollowTheUsersUnits() {
        let advice = Self.advice(rate: -1)
        #expect(CoachingExplanation.detail(advice, units: .metric).contains("1.0 kg/week"))
        #expect(CoachingExplanation.detail(advice, units: .imperial).contains("2.2 lb/week"))
    }

    @Test func notEnoughDataSaysWhatsNeeded() {
        let text = CoachingExplanation.strengthSummary(.notEnoughData(usableLifts: 1))
        #expect(text.contains("Not enough training data"))
        #expect(text.contains("it has 1"))
    }

    @Test func aRuleWithNoRoomSaysSoInsteadOfOfferingIt() {
        let advice = Self.advice(expenditure: 1780, current: 1780, intake: 1780, rate: -1, bmr: 1780)
        #expect(CoachingExplanation.detail(advice, units: .metric).contains("already as high"))
    }

    @Test func adjustmentTextHasItsSign() {
        let targets = ExpenditureTargets(calories: 2000, proteinG: 150, carbsG: 200, fatG: 60, isFloored: false)
        #expect(CoachingExplanation.adjustmentText(Engine.Adjustment(deltaKcal: 150, targets: targets)) == "+150 kcal")
        #expect(CoachingExplanation.adjustmentText(Engine.Adjustment(deltaKcal: -100, targets: targets)) == "-100 kcal")
    }
}
