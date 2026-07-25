//
//  HealthKitService.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import Foundation
import HealthKit

final class HealthKitService {
    private let healthStore = HKHealthStore()

    private var sampleTypes: Set<HKSampleType> {
        [
            HKQuantityType(.bodyMass),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.stepCount),
            HKWorkoutType.workoutType(),
        ]
    }

    /// Requests read/write access to weight, active energy, steps, and
    /// workouts. Vora is fully functional without HealthKit: denial and
    /// unavailability are both absorbed silently.
    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }

        do {
            try await healthStore.requestAuthorization(
                toShare: sampleTypes,
                read: sampleTypes
            )
        } catch {
            // Authorization UI failed or was unavailable — proceed without HealthKit.
        }
    }

    // MARK: - Workout writes (best-effort, silent on failure)

    func saveStrengthWorkout(start: Date, end: Date) async {
        await saveWorkout(activity: .traditionalStrengthTraining, start: start, end: end, calories: nil)
    }

    func saveCardioWorkout(type: CardioType, start: Date, end: Date, calories: Double) async {
        await saveWorkout(activity: Self.activity(for: type), start: start, end: end, calories: calories)
    }

    private func saveWorkout(
        activity: HKWorkoutActivityType,
        start: Date,
        end: Date,
        calories: Double?
    ) async {
        guard HKHealthStore.isHealthDataAvailable(), end > start else { return }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = activity
        let builder = HKWorkoutBuilder(healthStore: healthStore, configuration: configuration, device: .local())

        do {
            try await builder.beginCollection(at: start)
            if let calories, calories > 0 {
                let sample = HKQuantitySample(
                    type: HKQuantityType(.activeEnergyBurned),
                    quantity: HKQuantity(unit: .kilocalorie(), doubleValue: calories),
                    start: start,
                    end: end
                )
                try await builder.addSamples([sample])
            }
            try await builder.endCollection(at: end)
            try await builder.finishWorkout()
        } catch {
            // Not authorized or store unavailable — Vora works without HealthKit.
        }
    }

    private static func activity(for type: CardioType) -> HKWorkoutActivityType {
        switch type {
        case .treadmill: .running
        case .stairClimber: .stairClimbing
        case .elliptical: .elliptical
        case .stationaryBike: .cycling
        case .run: .running
        case .walk: .walking
        case .cycle: .cycling
        case .row: .rowing
        case .swim: .swimming
        case .other: .other
        }
    }
}
