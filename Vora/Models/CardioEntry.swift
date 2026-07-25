//
//  CardioEntry.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import Foundation
import SwiftData

enum CardioType: String, Codable, CaseIterable, Identifiable {
    // Raw values of the original cases must never change:
    // they are persisted as strings in existing CardioEntry rows.
    case treadmill
    case stairClimber
    case elliptical
    case stationaryBike
    case run
    case walk
    case cycle
    case row
    case swim
    case other

    var id: String { rawValue }

    /// Cases shown in the log picker, in display order.
    static let loggableCases: [CardioType] = [
        .treadmill, .stairClimber, .elliptical, .stationaryBike,
        .row, .run, .cycle, .walk, .swim, .other,
    ]

    var displayName: String {
        switch self {
        case .treadmill: "Treadmill"
        case .stairClimber: "Stair Climber"
        case .elliptical: "Elliptical"
        case .stationaryBike: "Stationary Bike"
        case .run: "Running"
        case .walk: "Walking"
        case .cycle: "Cycling"
        case .row: "Rowing Machine"
        case .swim: "Swim"
        case .other: "Other"
        }
    }

    var iconName: String {
        switch self {
        case .treadmill: Self.treadmillIcon
        case .stairClimber: "figure.stair.stepper"
        case .elliptical: "figure.elliptical"
        case .stationaryBike: "figure.indoor.cycle"
        case .run: "figure.run"
        case .walk: "figure.walk"
        case .cycle: "figure.outdoor.cycle"
        case .row: "figure.rower"
        case .swim: "figure.pool.swim"
        case .other: "heart.circle"
        }
    }

    // figure.run.treadmill ships with SF Symbols 6 (iOS 18).
    private static var treadmillIcon: String {
        guard #available(iOS 18.0, *) else { return "figure.run" }
        return "figure.run.treadmill"
    }
}

@Model
final class CardioEntry {
    @Attribute(.unique) var id: UUID
    var date: Date
    var type: CardioType
    var durationSeconds: Int
    var estimatedCalories: Double

    // Machine-specific stats. All optional so pre-existing rows migrate
    // untouched; only the fields relevant to `type` are ever populated.
    var speedKmh: Double?
    var inclinePercent: Double?
    var resistanceLevel: Int?
    var strokesPerMinute: Int?
    var stepsPerMinute: Int?
    var rpm: Int?
    var distanceKm: Double?
    /// Minutes per kilometre.
    var pace: Double?

    init(
        id: UUID = UUID(),
        date: Date,
        type: CardioType,
        durationSeconds: Int,
        estimatedCalories: Double,
        speedKmh: Double? = nil,
        inclinePercent: Double? = nil,
        resistanceLevel: Int? = nil,
        strokesPerMinute: Int? = nil,
        stepsPerMinute: Int? = nil,
        rpm: Int? = nil,
        distanceKm: Double? = nil,
        pace: Double? = nil
    ) {
        self.id = id
        self.date = date
        self.type = type
        self.durationSeconds = durationSeconds
        self.estimatedCalories = estimatedCalories
        self.speedKmh = speedKmh
        self.inclinePercent = inclinePercent
        self.resistanceLevel = resistanceLevel
        self.strokesPerMinute = strokesPerMinute
        self.stepsPerMinute = stepsPerMinute
        self.rpm = rpm
        self.distanceKm = distanceKm
        self.pace = pace
    }
}

extension CardioEntry {
    /// Machine stats plus duration, " · "-joined,
    /// e.g. "8.5 km/h · 2% incline · 30 min" or "85 spm · 20 min".
    /// Entries without machine data reduce to just the duration.
    var statsLine: String {
        var parts: [String] = []
        switch type {
        case .treadmill, .walk:
            if let speedKmh { parts.append("\(Self.num(speedKmh)) km/h") }
            if let inclinePercent, inclinePercent > 0 {
                parts.append("\(Self.num(inclinePercent))% incline")
            }
        case .stairClimber:
            if let stepsPerMinute { parts.append("\(stepsPerMinute) spm") }
        case .elliptical:
            if let resistanceLevel { parts.append("Level \(resistanceLevel)") }
        case .stationaryBike:
            if let resistanceLevel { parts.append("Level \(resistanceLevel)") }
            if let rpm { parts.append("\(rpm) rpm") }
        case .row:
            if let strokesPerMinute { parts.append("\(strokesPerMinute) spm") }
        case .run, .cycle:
            if let speedKmh { parts.append("\(Self.num(speedKmh)) km/h") }
            if let distanceKm { parts.append("\(Self.num(distanceKm)) km") }
        case .swim, .other:
            break
        }
        parts.append("\(durationSeconds / 60) min")
        return parts.joined(separator: " · ")
    }

    private static func num(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }
}
