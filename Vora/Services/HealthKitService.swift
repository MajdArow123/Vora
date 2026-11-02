//
//  HealthKitService.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import Foundation
import HealthKit
import OSLog

/// What identifies a workout Vora wrote to HealthKit. No HealthKit ID is
/// stored on sessions, so deletion matches on activity and times.
struct HealthWorkoutMatch: Equatable {
    let activityType: HKWorkoutActivityType
    let start: Date
    let end: Date

    /// nil for an empty interval: `saveWorkout` never writes those.
    init?(activityType: HKWorkoutActivityType, start: Date, end: Date) {
        guard end > start else { return nil }
        self.activityType = activityType
        self.start = start
        self.end = end
    }

    /// A session's `date` is when it started.
    init?(session: WorkoutSession) {
        self.init(
            activityType: .traditionalStrengthTraining,
            start: session.date,
            end: session.date.addingTimeInterval(TimeInterval(session.durationSeconds))
        )
    }

    /// A cardio entry's `date` is when it ended.
    init?(cardio: CardioEntry) {
        self.init(
            activityType: HealthKitService.activity(for: cardio.type),
            start: cardio.date.addingTimeInterval(-TimeInterval(cardio.durationSeconds)),
            end: cardio.date
        )
    }
}

enum HealthWorkoutDeletionResult: Equatable {
    case deleted
    case noMatch
    case ambiguous
}

/// A HealthKit workout reduced to the values matching needs.
struct HealthWorkoutCandidate: Equatable {
    let id: UUID
    let activityType: HKWorkoutActivityType
    let start: Date
    let end: Date
}

enum HealthWorkoutMatcher {
    /// Sessions saved before draft recovery wrote `end: .now` just after
    /// finishing, so stored and written end times can differ slightly.
    static let tolerance: TimeInterval = 5

    enum Selection: Equatable {
        case match(UUID)
        case none
        case ambiguous
    }

    /// Deleting from HealthKit can't be undone, so this only selects a
    /// workout when exactly one fits.
    static func select(candidates: [HealthWorkoutCandidate], match: HealthWorkoutMatch) -> Selection {
        let fits = candidates.filter {
            $0.activityType == match.activityType
                && abs($0.start.timeIntervalSince(match.start)) <= tolerance
                && abs($0.end.timeIntervalSince(match.end)) <= tolerance
        }
        switch fits.count {
        case 0: return .none
        case 1: return .match(fits[0].id)
        default: return .ambiguous
        }
    }
}

protocol HealthWorkoutDeleting {
    func deleteWorkout(matching match: HealthWorkoutMatch) async throws -> HealthWorkoutDeletionResult
}

final class HealthKitService: HealthWorkoutDeleting {
    private static let logger = Logger(subsystem: "com.majdarow.Vora", category: "HealthKit")

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

    // MARK: - Workout deletes

    /// Deletes the one workout Vora wrote that fits `match`, with the
    /// energy sample saved alongside it. HealthKit only lets an app delete
    /// its own data; a denied read shows up here as `.noMatch`.
    func deleteWorkout(matching match: HealthWorkoutMatch) async throws -> HealthWorkoutDeletionResult {
        guard HKHealthStore.isHealthDataAvailable() else { return .noMatch }

        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForObjects(from: HKSource.default()),
            HKQuery.predicateForWorkouts(with: match.activityType),
            HKQuery.predicateForSamples(
                withStart: match.start.addingTimeInterval(-HealthWorkoutMatcher.tolerance),
                end: match.end.addingTimeInterval(HealthWorkoutMatcher.tolerance),
                options: [.strictStartDate, .strictEndDate]
            ),
        ])
        let workouts = try await HKSampleQueryDescriptor(
            predicates: [.workout(predicate)],
            sortDescriptors: []
        ).result(for: healthStore)

        let candidates = workouts.map {
            HealthWorkoutCandidate(
                id: $0.uuid,
                activityType: $0.workoutActivityType,
                start: $0.startDate,
                end: $0.endDate
            )
        }
        switch HealthWorkoutMatcher.select(candidates: candidates, match: match) {
        case .none:
            return .noMatch
        case .ambiguous:
            return .ambiguous
        case .match(let id):
            guard let workout = workouts.first(where: { $0.uuid == id }) else { return .noMatch }
            do {
                _ = try await healthStore.deleteObjects(
                    of: HKQuantityType(.activeEnergyBurned),
                    predicate: HKQuery.predicateForObjects(from: workout)
                )
            } catch {
                // The workout is still worth removing without its energy sample.
                Self.logger.error("Failed to delete workout energy sample: \(String(describing: error), privacy: .public)")
            }
            try await healthStore.delete(workout)
            return .deleted
        }
    }

    static func activity(for type: CardioType) -> HKWorkoutActivityType {
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
