//
//  CardioCalculator.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-25.
//

import Foundation

/// Machine-specific inputs for MET lookup. Fields irrelevant to the cardio
/// type are ignored; missing relevant fields fall back to moderate defaults.
struct CardioInputs {
    var speedKmh: Double?
    var inclinePercent: Double?
    var resistanceLevel: Int?
    var strokesPerMinute: Int?
    var stepsPerMinute: Int?
    var rpm: Int?
}

/// Pure MET and calorie math for machine-specific cardio
/// (kcal = MET × body weight kg × hours).
enum CardioCalculator {
    // MARK: - Input ranges (single source of truth for sliders and clamping)

    static let treadmillSpeedRange: ClosedRange<Double> = 1.0...25.0
    static let runningSpeedRange: ClosedRange<Double> = 4.0...25.0
    static let cyclingSpeedRange: ClosedRange<Double> = 5.0...60.0
    static let walkingSpeedRange: ClosedRange<Double> = 2.0...7.0
    static let inclineRange: ClosedRange<Double> = 0...15
    static let resistanceRange: ClosedRange<Int> = 1...20
    static let rpmRange: ClosedRange<Int> = 40...120
    static let stepsPerMinuteRange: ClosedRange<Int> = 30...180
    static let strokeRateRange: ClosedRange<Int> = 18...36

    /// Minutes per kilometre, mirroring `runningSpeedRange`.
    static let paceRange: ClosedRange<Double> =
        (60 / runningSpeedRange.upperBound)...(60 / runningSpeedRange.lowerBound)

    // MARK: - Defaults for missing inputs (match CardioLogViewModel)

    private static let defaultIncline = 0.0
    private static let defaultResistance = 8
    private static let defaultRPM = 80
    private static let defaultStepsPerMinute = 70
    private static let defaultStrokeRate = 24

    static func defaultSpeed(for type: CardioType) -> Double {
        switch type {
        case .run: 10
        case .cycle: 20
        case .walk: 5
        default: 8
        }
    }

    // MARK: - MET tables

    /// Treadmill extends the spec's running anchors past 12 km/h so fast
    /// treadmill runs aren't undercounted; clamped at 16 MET above 16 km/h.
    private static let treadmillAnchors: [(speed: Double, met: Double)] = [
        (3, 2.8), (5, 3.5), (8, 8.3), (10, 10.5), (12, 12.5), (14, 14.0), (16, 16.0),
    ]
    private static let runningAnchors: [(speed: Double, met: Double)] = [
        (8, 8.3), (10, 10.5), (12, 12.5), (14, 14.0), (16, 16.0),
    ]
    private static let walkingAnchors: [(speed: Double, met: Double)] = [
        (3, 2.5), (4, 3.0), (5, 3.5),
    ]

    // MARK: - API

    static func met(type: CardioType, inputs: CardioInputs) -> Double {
        switch type {
        case .treadmill:
            let speed = speed(inputs, type, treadmillSpeedRange)
            return interpolatedMET(speed: speed, anchors: treadmillAnchors)
                + inclineBonus(inputs)
        case .stairClimber:
            let spm = (inputs.stepsPerMinute ?? defaultStepsPerMinute)
                .clamped(to: stepsPerMinuteRange)
            return spm < 60 ? 4.0 : spm <= 100 ? 7.0 : 9.0
        case .elliptical:
            let resistance = (inputs.resistanceLevel ?? defaultResistance)
                .clamped(to: resistanceRange)
            return resistance <= 7 ? 4.6 : resistance <= 14 ? 6.0 : 8.5
        case .stationaryBike:
            let resistance = (inputs.resistanceLevel ?? defaultResistance)
                .clamped(to: resistanceRange)
            let rpm = (inputs.rpm ?? defaultRPM).clamped(to: rpmRange)
            let workload = Double(resistance * rpm)
            return workload < 300 ? 3.5 : workload <= 900 ? 6.8 : 10.0
        case .row:
            let strokes = (inputs.strokesPerMinute ?? defaultStrokeRate)
                .clamped(to: strokeRateRange)
            return strokes < 22 ? 4.8 : strokes <= 26 ? 7.0 : 8.5
        case .run:
            return interpolatedMET(
                speed: speed(inputs, type, runningSpeedRange),
                anchors: runningAnchors
            )
        case .cycle:
            let speed = speed(inputs, type, cyclingSpeedRange)
            if speed < 16 { return 4.0 }
            if speed < 20 { return 6.0 }
            if speed <= 22 { return 8.0 }
            return 10.0
        case .walk:
            return interpolatedMET(
                speed: speed(inputs, type, walkingSpeedRange),
                anchors: walkingAnchors
            ) + inclineBonus(inputs)
        case .swim:
            return 8.0
        case .other:
            return 6.0
        }
    }

    static func calories(
        type: CardioType,
        inputs: CardioInputs,
        weightKg: Double,
        durationSeconds: Int
    ) -> Double {
        guard durationSeconds > 0 else { return 0 }
        return met(type: type, inputs: inputs) * weightKg * Double(durationSeconds) / 3600
    }

    static func pace(fromSpeedKmh speed: Double) -> Double {
        60 / speed.clamped(to: runningSpeedRange)
    }

    static func speedKmh(fromPace pace: Double) -> Double {
        60 / pace.clamped(to: paceRange)
    }

    static func distanceKm(speedKmh: Double, durationSeconds: Int) -> Double {
        speedKmh * Double(max(durationSeconds, 0)) / 3600
    }

    // MARK: - Helpers

    private static func speed(
        _ inputs: CardioInputs,
        _ type: CardioType,
        _ range: ClosedRange<Double>
    ) -> Double {
        (inputs.speedKmh ?? defaultSpeed(for: type)).clamped(to: range)
    }

    /// +0.5 MET per 1% incline.
    private static func inclineBonus(_ inputs: CardioInputs) -> Double {
        0.5 * (inputs.inclinePercent ?? defaultIncline).clamped(to: inclineRange)
    }

    /// Linear interpolation between ascending anchors, clamped at the extremes.
    private static func interpolatedMET(
        speed: Double,
        anchors: [(speed: Double, met: Double)]
    ) -> Double {
        guard let first = anchors.first, let last = anchors.last else { return 0 }
        if speed <= first.speed { return first.met }
        if speed >= last.speed { return last.met }
        for (lower, upper) in zip(anchors, anchors.dropFirst()) where speed < upper.speed {
            let fraction = (speed - lower.speed) / (upper.speed - lower.speed)
            return lower.met + (upper.met - lower.met) * fraction
        }
        return last.met
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
