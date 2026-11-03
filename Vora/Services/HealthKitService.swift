//
//  HealthKitService.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import Foundation
import HealthKit
import OSLog

/// What to remove from HealthKit for a deleted workout. Rows with a stored
/// ID use it; a stored ID that HealthKit can't find never falls back to
/// matching, so a different workout in the same window is never deleted.
enum HealthWorkoutTarget: Equatable {
    case id(UUID)
    case match(HealthWorkoutMatch)

    /// nil when there is no ID and the session could not have been written.
    init?(session: WorkoutSession) {
        if let id = session.healthKitWorkoutID {
            self = .id(id)
        } else if let match = HealthWorkoutMatch(session: session) {
            self = .match(match)
        } else {
            return nil
        }
    }

    /// nil when there is no ID and the entry could not have been written.
    init?(cardio: CardioEntry) {
        if let id = cardio.healthKitWorkoutID {
            self = .id(id)
        } else if let match = HealthWorkoutMatch(cardio: cardio) {
            self = .match(match)
        } else {
            return nil
        }
    }
}

/// What identifies a workout Vora wrote to HealthKit when no ID was stored
/// (rows saved before SchemaV4, or whose ID write didn't complete).
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
    func deleteWorkout(id: UUID) async throws -> HealthWorkoutDeletionResult
    func deleteWorkout(matching match: HealthWorkoutMatch) async throws -> HealthWorkoutDeletionResult
}

/// Both return the written workout's UUID, or nil if nothing was written.
protocol HealthWorkoutWriting {
    func saveStrengthWorkout(start: Date, end: Date) async -> UUID?
    func saveCardioWorkout(type: CardioType, start: Date, end: Date, calories: Double) async -> UUID?
}

/// The HealthKit write behind `HealthWorkoutWriting`. Separate so tests can
/// exercise `HealthKitService`'s guards without reaching the real store.
protocol HealthWorkoutRecording {
    func record(activity: HKWorkoutActivityType, start: Date, end: Date, calories: Double?) async throws -> UUID?
}

private struct HealthStoreWorkoutRecorder: HealthWorkoutRecording {
    let healthStore: HKHealthStore

    func record(activity: HKWorkoutActivityType, start: Date, end: Date, calories: Double?) async throws -> UUID? {
        guard HKHealthStore.isHealthDataAvailable() else { return nil }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = activity
        let builder = HKWorkoutBuilder(healthStore: healthStore, configuration: configuration, device: .local())

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
        return try await builder.finishWorkout()?.uuid
    }
}

/// A body weight read from HealthKit, reduced to the values import needs.
struct HealthBodyMassSample: Equatable {
    let id: UUID
    let date: Date
    let kg: Double
}

protocol HealthBodyMassReading {
    /// Body weights written by other apps, oldest first; everything when
    /// `since` is nil.
    func bodyMassSamples(since: Date?) async throws -> [HealthBodyMassSample]
}

final class HealthKitService: HealthWorkoutDeleting, HealthWorkoutWriting, HealthBodyMassReading {
    private static let logger = Logger(subsystem: "com.majdarow.Vora", category: "HealthKit")

    private lazy var healthStore = HKHealthStore()
    private lazy var recorder: any HealthWorkoutRecording = HealthStoreWorkoutRecorder(healthStore: healthStore)

    init(recorder: (any HealthWorkoutRecording)? = nil) {
        if let recorder {
            self.recorder = recorder
        }
    }

    /// Workouts, with the calories saved alongside cardio. Body mass is
    /// read-only: Vora never writes it.
    static let shareTypes: Set<HKSampleType> = [
        HKQuantityType(.activeEnergyBurned),
        HKWorkoutType.workoutType(),
    ]

    /// Body mass for the weight import, and workouts to find the ones Vora
    /// saved when they're deleted.
    static let readTypes: Set<HKSampleType> = [
        HKQuantityType(.bodyMass),
        HKWorkoutType.workoutType(),
    ]

    /// Requests write access to workouts and read access to body weight.
    /// Vora is fully functional without HealthKit: denial and unavailability
    /// are both absorbed.
    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }

        do {
            try await healthStore.requestAuthorization(
                toShare: Self.shareTypes,
                read: Self.readTypes
            )
        } catch {
            // Authorization UI failed or was unavailable — proceed without HealthKit.
            Self.logger.info("HealthKit authorization failed: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Body mass reads

    /// Excludes Vora's own samples. HealthKit hides whether read access was
    /// denied, so denial reads as no samples.
    func bodyMassSamples(since: Date?) async throws -> [HealthBodyMassSample] {
        guard HKHealthStore.isHealthDataAvailable() else { return [] }

        var predicates: [NSPredicate] = [
            NSCompoundPredicate(notPredicateWithSubpredicate: HKQuery.predicateForObjects(from: HKSource.default())),
        ]
        if let since {
            predicates.append(HKQuery.predicateForSamples(withStart: since, end: nil, options: .strictStartDate))
        }
        let samples = try await HKSampleQueryDescriptor(
            predicates: [.quantitySample(
                type: HKQuantityType(.bodyMass),
                predicate: NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
            )],
            sortDescriptors: [SortDescriptor(\.startDate)]
        ).result(for: healthStore)

        return samples.map {
            HealthBodyMassSample(
                id: $0.uuid,
                date: $0.startDate,
                kg: $0.quantity.doubleValue(for: .gramUnit(with: .kilo))
            )
        }
    }

    // MARK: - Workout writes (best-effort, logged on failure)

    func saveStrengthWorkout(start: Date, end: Date) async -> UUID? {
        await saveWorkout(activity: .traditionalStrengthTraining, start: start, end: end, calories: nil)
    }

    func saveCardioWorkout(type: CardioType, start: Date, end: Date, calories: Double) async -> UUID? {
        await saveWorkout(activity: Self.activity(for: type), start: start, end: end, calories: calories)
    }

    private func saveWorkout(
        activity: HKWorkoutActivityType,
        start: Date,
        end: Date,
        calories: Double?
    ) async -> UUID? {
        guard end > start else { return nil }

        do {
            return try await recorder.record(activity: activity, start: start, end: end, calories: calories)
        } catch {
            // Not authorized or store unavailable — Vora works without HealthKit.
            Self.logger.info("Workout not written to HealthKit: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    // MARK: - Workout deletes

    /// Deletes the workout Vora wrote with this UUID, with the energy
    /// sample saved alongside it. A workout already removed from HealthKit,
    /// or a denied read, shows up as `.noMatch`.
    func deleteWorkout(id: UUID) async throws -> HealthWorkoutDeletionResult {
        guard HKHealthStore.isHealthDataAvailable() else { return .noMatch }

        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForObjects(from: HKSource.default()),
            HKQuery.predicateForObject(with: id),
        ])
        let workouts = try await HKSampleQueryDescriptor(
            predicates: [.workout(predicate)],
            sortDescriptors: []
        ).result(for: healthStore)

        guard let workout = workouts.first else { return .noMatch }
        try await delete(workout)
        return .deleted
    }

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
            try await delete(workout)
            return .deleted
        }
    }

    private func delete(_ workout: HKWorkout) async throws {
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
