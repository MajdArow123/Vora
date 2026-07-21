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
}
