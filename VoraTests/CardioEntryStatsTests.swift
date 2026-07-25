//
//  CardioEntryStatsTests.swift
//  VoraTests
//
//  Created by Majd Arow on 2026-07-25.
//

import Foundation
import Testing
@testable import Vora

struct CardioEntryStatsTests {
    private func entry(
        _ type: CardioType,
        durationSeconds: Int,
        speedKmh: Double? = nil,
        inclinePercent: Double? = nil,
        resistanceLevel: Int? = nil,
        strokesPerMinute: Int? = nil,
        stepsPerMinute: Int? = nil,
        rpm: Int? = nil,
        distanceKm: Double? = nil
    ) -> CardioEntry {
        CardioEntry(
            date: .now,
            type: type,
            durationSeconds: durationSeconds,
            estimatedCalories: 0,
            speedKmh: speedKmh,
            inclinePercent: inclinePercent,
            resistanceLevel: resistanceLevel,
            strokesPerMinute: strokesPerMinute,
            stepsPerMinute: stepsPerMinute,
            rpm: rpm,
            distanceKm: distanceKm
        )
    }

    @Test func treadmillShowsSpeedInclineAndDuration() {
        let entry = entry(.treadmill, durationSeconds: 1800, speedKmh: 8.5, inclinePercent: 2)
        #expect(entry.statsLine == "8.5 km/h · 2% incline · 30 min")
    }

    @Test func treadmillOmitsZeroIncline() {
        let entry = entry(.treadmill, durationSeconds: 1800, speedKmh: 8.5, inclinePercent: 0)
        #expect(entry.statsLine == "8.5 km/h · 30 min")
    }

    @Test func runningShowsSpeedDistanceAndDuration() {
        let entry = entry(.run, durationSeconds: 1860, speedKmh: 10, distanceKm: 5.2)
        #expect(entry.statsLine == "10 km/h · 5.2 km · 31 min")
    }

    @Test func stairClimberShowsStepRate() {
        let entry = entry(.stairClimber, durationSeconds: 1200, stepsPerMinute: 85)
        #expect(entry.statsLine == "85 spm · 20 min")
    }

    @Test func ellipticalShowsResistanceLevel() {
        let entry = entry(.elliptical, durationSeconds: 2400, resistanceLevel: 12)
        #expect(entry.statsLine == "Level 12 · 40 min")
    }

    @Test func stationaryBikeShowsResistanceAndCadence() {
        let entry = entry(.stationaryBike, durationSeconds: 2400, resistanceLevel: 12, rpm: 85)
        #expect(entry.statsLine == "Level 12 · 85 rpm · 40 min")
    }

    @Test func rowingShowsStrokeRate() {
        let entry = entry(.row, durationSeconds: 1500, strokesPerMinute: 24)
        #expect(entry.statsLine == "24 spm · 25 min")
    }

    @Test func fractionalValuesRoundToOneDecimal() {
        // A stored distance of 5.1667 km displays as "5.2".
        let entry = entry(.run, durationSeconds: 1860, speedKmh: 10.0, distanceKm: 31.0 / 6.0)
        #expect(entry.statsLine == "10 km/h · 5.2 km · 31 min")
    }

    @Test func legacyEntryWithoutMachineDataShowsDurationOnly() {
        let entry = entry(.run, durationSeconds: 1860)
        #expect(entry.statsLine == "31 min")
    }

    @Test func swimShowsDurationOnly() {
        let entry = entry(.swim, durationSeconds: 1800)
        #expect(entry.statsLine == "30 min")
    }
}
