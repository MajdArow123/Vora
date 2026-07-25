//
//  CardioCalculatorTests.swift
//  VoraTests
//
//  Created by Majd Arow on 2026-07-25.
//

import Foundation
import Testing
@testable import Vora

struct CardioCalculatorTests {
    private func met(_ type: CardioType, _ inputs: CardioInputs) -> Double {
        CardioCalculator.met(type: type, inputs: inputs)
    }

    // MARK: - Speed anchor exactness

    @Test(arguments: zip(
        [3.0, 5.0, 8.0, 10.0, 12.0, 14.0, 16.0],
        [2.8, 3.5, 8.3, 10.5, 12.5, 14.0, 16.0]
    ))
    func treadmillAnchorSpeedsReturnExactMET(speed: Double, expected: Double) {
        #expect(abs(met(.treadmill, CardioInputs(speedKmh: speed)) - expected) < 0.001)
    }

    @Test(arguments: zip(
        [8.0, 10.0, 12.0, 14.0, 16.0],
        [8.3, 10.5, 12.5, 14.0, 16.0]
    ))
    func runningAnchorSpeedsReturnExactMET(speed: Double, expected: Double) {
        #expect(abs(met(.run, CardioInputs(speedKmh: speed)) - expected) < 0.001)
    }

    @Test(arguments: zip([3.0, 4.0, 5.0], [2.5, 3.0, 3.5]))
    func walkingAnchorSpeedsReturnExactMET(speed: Double, expected: Double) {
        #expect(abs(met(.walk, CardioInputs(speedKmh: speed)) - expected) < 0.001)
    }

    // MARK: - Interpolation between anchors

    @Test(arguments: zip(
        [4.0, 6.5, 9.0, 11.0, 15.0],
        [3.15, 5.9, 9.4, 11.5, 15.0]
    ))
    func treadmillInterpolatesBetweenAnchors(speed: Double, expected: Double) {
        #expect(abs(met(.treadmill, CardioInputs(speedKmh: speed)) - expected) < 0.001)
    }

    @Test func runningInterpolatesBetweenAnchors() {
        // 11 km/h sits halfway between (10, 10.5) and (12, 12.5).
        #expect(abs(met(.run, CardioInputs(speedKmh: 11)) - 11.5) < 0.001)
    }

    @Test func walkingInterpolatesBetweenAnchors() {
        // 3.5 km/h sits halfway between (3, 2.5) and (4, 3.0).
        #expect(abs(met(.walk, CardioInputs(speedKmh: 3.5)) - 2.75) < 0.001)
    }

    // MARK: - Clamping at the extremes

    @Test func speedsOutsideAnchorTablesClampToEndpointMET() {
        #expect(abs(met(.treadmill, CardioInputs(speedKmh: 1)) - 2.8) < 0.001)
        #expect(abs(met(.treadmill, CardioInputs(speedKmh: 25)) - 16.0) < 0.001)
        #expect(abs(met(.run, CardioInputs(speedKmh: 5)) - 8.3) < 0.001)
        #expect(abs(met(.run, CardioInputs(speedKmh: 20)) - 16.0) < 0.001)
        #expect(abs(met(.walk, CardioInputs(speedKmh: 2)) - 2.5) < 0.001)
        #expect(abs(met(.walk, CardioInputs(speedKmh: 7)) - 3.5) < 0.001)
    }

    // MARK: - Incline bonus

    @Test func inclineAddsHalfMETPerPercent() {
        // Treadmill 8 km/h = 8.3 MET; +2% incline adds 1.0.
        let inputs = CardioInputs(speedKmh: 8, inclinePercent: 2)
        #expect(abs(met(.treadmill, inputs) - 9.3) < 0.001)
        // Walking gets the same bonus: 5 km/h = 3.5 + 1.5 = 5.0.
        let walk = CardioInputs(speedKmh: 5, inclinePercent: 3)
        #expect(abs(met(.walk, walk) - 5.0) < 0.001)
    }

    @Test func inclineClampsAtFifteenPercent() {
        // 8.3 + 0.5 × 15 = 15.8 even when asked for 20%.
        let inputs = CardioInputs(speedKmh: 8, inclinePercent: 20)
        #expect(abs(met(.treadmill, inputs) - 15.8) < 0.001)
    }

    // MARK: - Threshold tables

    @Test(arguments: zip([59, 60, 100, 101], [4.0, 7.0, 7.0, 9.0]))
    func stairClimberThresholds(spm: Int, expected: Double) {
        #expect(abs(met(.stairClimber, CardioInputs(stepsPerMinute: spm)) - expected) < 0.001)
    }

    @Test(arguments: zip([1, 7, 8, 14, 15, 20], [4.6, 4.6, 6.0, 6.0, 8.5, 8.5]))
    func ellipticalThresholds(resistance: Int, expected: Double) {
        #expect(abs(met(.elliptical, CardioInputs(resistanceLevel: resistance)) - expected) < 0.001)
    }

    @Test(arguments: zip([21, 22, 26, 27], [4.8, 7.0, 7.0, 8.5]))
    func rowingThresholds(strokes: Int, expected: Double) {
        #expect(abs(met(.row, CardioInputs(strokesPerMinute: strokes)) - expected) < 0.001)
    }

    @Test(arguments: zip(
        [15.9, 16.0, 19.9, 20.0, 22.0, 22.1],
        [4.0, 6.0, 6.0, 8.0, 8.0, 10.0]
    ))
    func cyclingThresholds(speed: Double, expected: Double) {
        #expect(abs(met(.cycle, CardioInputs(speedKmh: speed)) - expected) < 0.001)
    }

    @Test func stationaryBikeWorkloadBoundaries() {
        // Workload = resistance × rpm; light < 300, moderate 300–900, vigorous > 900.
        #expect(abs(met(.stationaryBike, CardioInputs(resistanceLevel: 5, rpm: 59)) - 3.5) < 0.001)
        #expect(abs(met(.stationaryBike, CardioInputs(resistanceLevel: 5, rpm: 60)) - 6.8) < 0.001)
        #expect(abs(met(.stationaryBike, CardioInputs(resistanceLevel: 10, rpm: 90)) - 6.8) < 0.001)
        #expect(abs(met(.stationaryBike, CardioInputs(resistanceLevel: 10, rpm: 91)) - 10.0) < 0.001)
    }

    @Test func swimAndOtherKeepFlatMET() {
        #expect(abs(met(.swim, CardioInputs()) - 8.0) < 0.001)
        #expect(abs(met(.other, CardioInputs()) - 6.0) < 0.001)
    }

    // MARK: - Calories

    @Test func caloriesMultiplyMETWeightAndHours() {
        // Treadmill 8 km/h flat = 8.3 MET × 75 kg × 0.5 h = 311.25 kcal.
        let calories = CardioCalculator.calories(
            type: .treadmill,
            inputs: CardioInputs(speedKmh: 8),
            weightKg: 75,
            durationSeconds: 1800
        )
        #expect(abs(calories - 311.25) < 0.001)
    }

    @Test func nonPositiveDurationYieldsZeroCalories() {
        let inputs = CardioInputs(speedKmh: 8)
        #expect(CardioCalculator.calories(type: .treadmill, inputs: inputs, weightKg: 75, durationSeconds: 0) == 0)
        #expect(CardioCalculator.calories(type: .treadmill, inputs: inputs, weightKg: 75, durationSeconds: -60) == 0)
    }

    // MARK: - Pace and distance

    @Test func paceAndSpeedRoundTrip() {
        #expect(abs(CardioCalculator.pace(fromSpeedKmh: 10) - 6.0) < 0.001)
        #expect(abs(CardioCalculator.speedKmh(fromPace: 6.0) - 10) < 0.001)
        #expect(abs(CardioCalculator.speedKmh(fromPace: 5.0) - 12) < 0.001)
    }

    @Test func paceConversionClampsThroughSpeedRange() {
        // 2 km/h clamps to the 4 km/h floor → 15 min/km, never a divide blow-up.
        #expect(abs(CardioCalculator.pace(fromSpeedKmh: 2) - 15.0) < 0.001)
    }

    @Test func distanceIsSpeedTimesHours() {
        // 10 km/h × 31 min = 5.1667 km.
        let distance = CardioCalculator.distanceKm(speedKmh: 10, durationSeconds: 1860)
        #expect(abs(distance - 31.0 / 6.0) < 0.001)
        #expect(CardioCalculator.distanceKm(speedKmh: 10, durationSeconds: 0) == 0)
    }
}
