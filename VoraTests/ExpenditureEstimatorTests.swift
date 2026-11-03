//
//  ExpenditureEstimatorTests.swift
//  VoraTests
//
//  Created by Majd Arow on 2026-11-02.
//

import Foundation
import Testing
@testable import Vora

struct ExpenditureEstimatorTests {
    private typealias Estimator = ExpenditureEstimator

    /// A full 21-day window (offsets 0...20) at a steady intake and rate.
    private static func input(
        kcal: Double,
        kgPerWeek: Double,
        previous: Double? = nil,
        formula: Double = 2500
    ) -> Estimator.Input {
        Estimator.Input(
            intake: (0..<21).map { Estimator.IntakeDay(dayOffset: $0, kcal: kcal) },
            weights: (0..<21).map { Estimator.WeightDay(dayOffset: $0, weightKg: 80 + Double($0) * kgPerWeek / 7) },
            formulaTDEE: formula,
            previousEstimate: previous,
            lastDayOffset: 20
        )
    }

    private static func isClose(_ actual: Double?, _ expected: Double, within tolerance: Double = 0.001) -> Bool {
        guard let actual else { return false }
        return abs(actual - expected) <= tolerance
    }

    // MARK: - Known answers

    @Test func steadyLoss() {
        let result = Estimator.estimate(Self.input(kcal: 2600, kgPerWeek: -0.5, previous: 3100))
        #expect(Self.isClose(result.rawEstimate, 3150))
        #expect(Self.isClose(result.estimate, 3150))
        #expect(Self.isClose(result.slopeKgPerDay, -0.5 / 7, within: 0.000001))
        #expect(Self.isClose(result.averageIntake, 2600))
        #expect(result.daysUsed == 21)
        #expect(result.weighInsUsed == 21)
        #expect(result.reason == .fullData)
        #expect(!result.wasCapped)
    }

    @Test func steadyGain() {
        let result = Estimator.estimate(Self.input(kcal: 3000, kgPerWeek: 0.25, previous: 2700))
        #expect(Self.isClose(result.rawEstimate, 2725))
        #expect(Self.isClose(result.estimate, 2725))
    }

    @Test func maintenance() {
        let result = Estimator.estimate(Self.input(kcal: 2500, kgPerWeek: 0, previous: 2500))
        #expect(Self.isClose(result.rawEstimate, 2500))
        #expect(Self.isClose(result.estimate, 2500))
        #expect(Self.isClose(result.slopeKgPerDay, 0))
    }

    /// The EWMA trend lags a steady change, so using its rate would read
    /// about 200 kcal low here. The slope gets the answer exactly.
    @Test func slopeAvoidsTheEWMALag() throws {
        let input = Self.input(kcal: 2600, kgPerWeek: -0.5, previous: 3150)
        let result = Estimator.estimate(input)
        #expect(Self.isClose(result.rawEstimate, 3150))

        let trend = try #require(WeightTrendCalculator.calculate(readings: input.weights.map {
            WeightTrendCalculator.Reading(dayOffset: $0.dayOffset, weightKg: $0.weightKg)
        }))
        let trendRate = try #require(trend.ratePerDay(window: 20))
        let trendBased = 2600 - trendRate * Estimator.energyDensityKcalPerKg
        #expect(trendBased < 3000)
    }

    // MARK: - Missing and incomplete days

    @Test func missingDaysDoNotCountAsZero() {
        var input = Self.input(kcal: 2600, kgPerWeek: -0.5, previous: 3150)
        input.intake = input.intake.map { day in
            day.dayOffset % 3 == 0 ? Estimator.IntakeDay(dayOffset: day.dayOffset, kcal: nil) : day
        }
        let result = Estimator.estimate(input)
        #expect(result.daysUsed == 14)
        #expect(Self.isClose(result.averageIntake, 2600))
        #expect(Self.isClose(result.rawEstimate, 3150))
        #expect(result.excludedIncompleteDays == 0)
    }

    /// At 3000 current the line is exactly 1200: under it is out, on it stays.
    @Test func daysUnderFortyPercentOfCurrentAreExcluded() {
        var input = Self.input(kcal: 2600, kgPerWeek: 0, previous: 3000)
        input.intake[0] = Estimator.IntakeDay(dayOffset: 0, kcal: 1199.9)
        input.intake[1] = Estimator.IntakeDay(dayOffset: 1, kcal: 1200)
        let result = Estimator.estimate(input)
        #expect(result.daysUsed == 20)
        #expect(result.excludedIncompleteDays == 1)
        #expect(Self.isClose(result.averageIntake, (19 * 2600 + 1200) / 20))
    }

    @Test func theIncompleteLineFollowsThePreviousEstimateNotTheFormula() {
        var input = Self.input(kcal: 2600, kgPerWeek: 0, previous: 2000, formula: 3500)
        input.intake[0] = Estimator.IntakeDay(dayOffset: 0, kcal: 1000)
        // 40% of 2000 is 800, so 1000 stays. Against the formula it wouldn't.
        #expect(Estimator.estimate(input).excludedIncompleteDays == 0)
    }

    @Test func excludedDaysCountAgainstTheMinimum() {
        var input = Self.input(kcal: 2600, kgPerWeek: 0, previous: 3000)
        input.intake = input.intake.enumerated().map { index, day in
            Estimator.IntakeDay(dayOffset: day.dayOffset, kcal: index < 12 ? 500 : 2600)
        }
        let result = Estimator.estimate(input)
        #expect(result.reason == .notEnoughData(intakeDays: 9, neededIntakeDays: 10, weighIns: 21, neededWeighIns: 8))
    }

    @Test func daysOutsideTheWindowAreIgnored() {
        var input = Self.input(kcal: 2600, kgPerWeek: -0.5, previous: 3150)
        input.intake.append(Estimator.IntakeDay(dayOffset: -1, kcal: 9000))
        input.intake.append(Estimator.IntakeDay(dayOffset: 21, kcal: 9000))
        input.weights.append(Estimator.WeightDay(dayOffset: -5, weightKg: 200))
        let result = Estimator.estimate(input)
        #expect(result.daysUsed == 21)
        #expect(result.weighInsUsed == 21)
        #expect(Self.isClose(result.rawEstimate, 3150))
    }

    @Test func sameDayWeighInsAreAveragedFirst() {
        let base = Self.input(kcal: 2600, kgPerWeek: -0.5, previous: 3150)
        var doubled = base
        // Readings straddling each day's weight average back to it.
        doubled.weights = base.weights.flatMap { day in
            [
                Estimator.WeightDay(dayOffset: day.dayOffset, weightKg: day.weightKg - 0.3),
                Estimator.WeightDay(dayOffset: day.dayOffset, weightKg: day.weightKg + 0.3),
            ]
        }
        let result = Estimator.estimate(doubled)
        #expect(result.weighInsUsed == 21)
        #expect(Self.isClose(result.slopeKgPerDay, Estimator.estimate(base).slopeKgPerDay ?? 0, within: 0.000001))
    }

    // MARK: - Too little data

    @Test func tooFewIntakeDaysReturnsThePriorWithAReason() {
        var input = Self.input(kcal: 2600, kgPerWeek: -0.5, formula: 2800)
        input.intake = Array(input.intake.prefix(9))
        let result = Estimator.estimate(input)
        #expect(result.estimate == 2800)
        #expect(result.rawEstimate == nil)
        #expect(result.averageIntake == nil)
        #expect(result.slopeKgPerDay == nil)
        #expect(result.reason == .notEnoughData(intakeDays: 9, neededIntakeDays: 10, weighIns: 21, neededWeighIns: 8))
    }

    @Test func tooFewWeighInsReturnsThePriorWithAReason() {
        var input = Self.input(kcal: 2600, kgPerWeek: -0.5, previous: 3000)
        input.weights = Array(input.weights.prefix(7))
        let result = Estimator.estimate(input)
        #expect(result.estimate == 3000)
        #expect(result.reason == .notEnoughData(intakeDays: 21, neededIntakeDays: 10, weighIns: 7, neededWeighIns: 8))
    }

    @Test func theMinimumsThemselvesAreEnough() {
        var input = Self.input(kcal: 2600, kgPerWeek: -0.5, previous: 3150)
        input.intake = Array(input.intake.prefix(10))
        input.weights = Array(input.weights.prefix(8))
        let result = Estimator.estimate(input)
        #expect(result.daysUsed == 10)
        #expect(result.weighInsUsed == 8)
        #expect(Self.isClose(result.rawEstimate, 3150))
    }

    // MARK: - Completeness

    /// min(intakeDays / 21, min(1, weighIns / 14)).
    @Test func completenessTakesTheWeakerSignalAndSaturatesWeighInsAtFourteen() {
        let cases: [(intakeDays: Int, weighIns: Int, expected: Double)] = [
            (21, 21, 1),
            (21, 14, 1),
            (21, 30, 1),
            (21, 13, 13.0 / 14),
            (21, 8, 8.0 / 14),
            (14, 21, 14.0 / 21),
            (14, 14, 14.0 / 21),
            (10, 8, 10.0 / 21),
            (0, 0, 0),
        ]
        for item in cases {
            let actual = Estimator.completeness(intakeDaysUsed: item.intakeDays, weighInsUsed: item.weighIns)
            #expect(Self.isClose(actual, item.expected, within: 0.000001), "\(item)")
        }
    }

    /// Every other day is enough for full weight: no blending, no partial reason.
    @Test func fourteenWeighInsMoveTheFullWay() {
        var input = Self.input(kcal: 2600, kgPerWeek: 0, previous: 2500)
        input.weights = Array(input.weights.prefix(14))
        let result = Estimator.estimate(input)
        #expect(result.reason == .fullData)
        #expect(Self.isClose(result.estimate, 2600))
    }

    /// Raw 2600 from 2500 is a 100 kcal gap, under the cap; 8 of 14 weigh-ins
    /// close 8/14 of it.
    @Test func partialWeighInsBlendPartWay() {
        var input = Self.input(kcal: 2600, kgPerWeek: 0, previous: 2500)
        input.weights = Array(input.weights.prefix(8))
        let result = Estimator.estimate(input)
        #expect(Self.isClose(result.estimate, 2500 + 100 * 8.0 / 14))
        #expect(Self.isClose(result.rawEstimate, 2600))
        if case .partialData(let completeness) = result.reason {
            #expect(Self.isClose(completeness, 8.0 / 14, within: 0.000001))
        } else {
            Issue.record("Expected partial data, got \(result.reason)")
        }
    }

    /// 14 of 21 intake days close 2/3 of the gap, whatever the weigh-ins.
    @Test func partialIntakeBlendsPartWay() {
        var input = Self.input(kcal: 2650, kgPerWeek: 0, previous: 2500)
        input.intake = Array(input.intake.prefix(14))
        let result = Estimator.estimate(input)
        #expect(Self.isClose(result.estimate, 2500 + 150 * 14.0 / 21))
    }

    // MARK: - Weekly cap

    @Test func aBigRiseIsCapped() {
        let result = Estimator.estimate(Self.input(kcal: 3600, kgPerWeek: 0, previous: 3000))
        #expect(Self.isClose(result.estimate, 3150))
        #expect(Self.isClose(result.rawEstimate, 3600))
        #expect(result.wasCapped)
    }

    @Test func aBigDropIsCapped() {
        let result = Estimator.estimate(Self.input(kcal: 2400, kgPerWeek: 0, previous: 3000))
        #expect(Self.isClose(result.estimate, 2850))
        #expect(result.wasCapped)
    }

    @Test func exactlyTheCapIsNotCapped() {
        let result = Estimator.estimate(Self.input(kcal: 3150, kgPerWeek: 0, previous: 3000))
        #expect(Self.isClose(result.estimate, 3150))
        #expect(!result.wasCapped)
    }

    /// The first update starts from the formula.
    @Test func theFirstUpdateMovesFromTheFormula() {
        let result = Estimator.estimate(Self.input(kcal: 3600, kgPerWeek: 0, formula: 2800))
        #expect(Self.isClose(result.estimate, 2950))
    }

    // MARK: - Slope

    @Test func slopeNeedsTwoDistinctDays() {
        #expect(Estimator.leastSquaresSlope([]) == nil)
        #expect(Estimator.leastSquaresSlope([Estimator.WeightDay(dayOffset: 3, weightKg: 80)]) == nil)
    }

    /// Fit through (0, 80), (1, 79), (2, 81), (3, 78): slope −0.4 (endpoints would say −0.67).
    @Test func slopeIsLeastSquaresNotEndpoints() {
        let readings = zip(0..., [80.0, 79, 81, 78]).map { Estimator.WeightDay(dayOffset: $0, weightKg: $1) }
        #expect(Self.isClose(Estimator.leastSquaresSlope(readings), -0.4))
    }
}
