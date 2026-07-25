//
//  CardioLogViewModel.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import Foundation
import Observation
import SwiftData

@Observable
final class CardioLogViewModel {
    var type: CardioType = .treadmill
    var durationMinutes = 30

    // Machine inputs; each type reads only the fields relevant to it.
    var speedKmh: Double = 8
    var inclinePercent: Double = 0
    var resistanceLevel = 8
    var rpm = 80
    var stepsPerMinute = 70
    var strokesPerMinute = 24
    /// Running only: whether the user is entering pace instead of speed.
    var paceInputSelected = false

    private var bodyWeightKg: Double = 75

    private let healthKitService = HealthKitService()

    /// Switches the cardio type, resetting speed and incline to defaults
    /// suited to the new activity.
    func select(_ newType: CardioType) {
        type = newType
        inclinePercent = 0
        speedKmh = CardioCalculator.defaultSpeed(for: newType)
    }

    /// Minutes per kilometre, bridged to `speedKmh` (Running pace input).
    var paceMinPerKm: Double {
        get { CardioCalculator.pace(fromSpeedKmh: speedKmh) }
        set { speedKmh = CardioCalculator.speedKmh(fromPace: newValue) }
    }

    /// Auto-derived distance for speed-based types; nil for the rest.
    var distanceKm: Double? {
        switch type {
        case .treadmill, .run, .cycle, .walk:
            CardioCalculator.distanceKm(speedKmh: speedKmh, durationSeconds: durationMinutes * 60)
        default:
            nil
        }
    }

    func load(from context: ModelContext) {
        var descriptor = FetchDescriptor<WeightEntry>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        if let latest = try? context.fetch(descriptor).first {
            bodyWeightKg = latest.weightKg
        }
    }

    /// kcal = MET × body weight (kg) × duration (hours).
    var estimatedCalories: Double {
        CardioCalculator.calories(
            type: type,
            inputs: inputs,
            weightKg: bodyWeightKg,
            durationSeconds: durationMinutes * 60
        )
    }

    func save(in context: ModelContext) {
        let end = Date.now
        let seconds = durationMinutes * 60
        let start = end.addingTimeInterval(-Double(seconds))
        let calories = estimatedCalories

        let entry = CardioEntry(
            date: end,
            type: type,
            durationSeconds: seconds,
            estimatedCalories: calories
        )
        populateMachineFields(of: entry)
        context.insert(entry)
        do {
            try context.save()
        } catch {
            assertionFailure("Failed to save cardio entry: \(error)")
        }

        let service = healthKitService
        let cardioType = type
        Task {
            await service.saveCardioWorkout(type: cardioType, start: start, end: end, calories: calories)
        }
    }

    // MARK: - Machine fields

    /// Only the fields relevant to the current type; the rest stay nil.
    private var inputs: CardioInputs {
        switch type {
        case .treadmill:
            CardioInputs(speedKmh: speedKmh, inclinePercent: inclinePercent)
        case .stairClimber:
            CardioInputs(stepsPerMinute: stepsPerMinute)
        case .elliptical:
            CardioInputs(resistanceLevel: resistanceLevel)
        case .stationaryBike:
            CardioInputs(resistanceLevel: resistanceLevel, rpm: rpm)
        case .row:
            CardioInputs(strokesPerMinute: strokesPerMinute)
        case .run, .cycle:
            CardioInputs(speedKmh: speedKmh)
        case .walk:
            CardioInputs(speedKmh: speedKmh, inclinePercent: inclinePercent)
        case .swim, .other:
            CardioInputs()
        }
    }

    private func populateMachineFields(of entry: CardioEntry) {
        switch type {
        case .treadmill:
            entry.speedKmh = speedKmh
            entry.inclinePercent = inclinePercent
            entry.distanceKm = distanceKm
        case .stairClimber:
            entry.stepsPerMinute = stepsPerMinute
        case .elliptical:
            entry.resistanceLevel = resistanceLevel
        case .stationaryBike:
            entry.resistanceLevel = resistanceLevel
            entry.rpm = rpm
        case .row:
            entry.strokesPerMinute = strokesPerMinute
        case .run:
            entry.speedKmh = speedKmh
            entry.distanceKm = distanceKm
            entry.pace = paceMinPerKm
        case .cycle:
            entry.speedKmh = speedKmh
            entry.distanceKm = distanceKm
        case .walk:
            entry.speedKmh = speedKmh
            if inclinePercent > 0 { entry.inclinePercent = inclinePercent }
            entry.distanceKm = distanceKm
        case .swim, .other:
            break
        }
    }
}
