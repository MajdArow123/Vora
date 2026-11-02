//
//  WorkoutDeletionService.swift
//  Vora
//
//  Created by Majd Arow on 2026-11-02.
//

import Foundation
import OSLog
import SwiftData

/// Deletes workouts in two steps, local first: HealthKit can't block the
/// local delete, and a failed local delete never touches HealthKit.
struct WorkoutDeletionService {
    private static let logger = Logger(subsystem: "com.majdarow.Vora", category: "Workout")

    private let health: any HealthWorkoutDeleting

    init(health: any HealthWorkoutDeleting = HealthKitService()) {
        self.health = health
    }

    /// Deletes the session and, by cascade, its exercises and sets. Returns
    /// what to remove from HealthKit. `save` is injectable so tests can
    /// simulate a failed save.
    func delete(
        _ session: WorkoutSession,
        context: ModelContext,
        save: (ModelContext) throws -> Void = { try $0.save() }
    ) throws -> HealthWorkoutTarget? {
        let target = HealthWorkoutTarget(session: session)
        try deleteModel(session, context: context, save: save)
        return target
    }

    /// Deletes the entry. Returns what to remove from HealthKit.
    func delete(
        _ entry: CardioEntry,
        context: ModelContext,
        save: (ModelContext) throws -> Void = { try $0.save() }
    ) throws -> HealthWorkoutTarget? {
        let target = HealthWorkoutTarget(cardio: entry)
        try deleteModel(entry, context: context, save: save)
        return target
    }

    /// Best-effort: every outcome but `.deleted` is logged and nothing is
    /// thrown, because the local delete has already happened. Returns nil
    /// when there was nothing to look for or the attempt failed.
    @discardableResult
    func removeFromHealth(_ target: HealthWorkoutTarget?) async -> HealthWorkoutDeletionResult? {
        guard let target else { return nil }
        do {
            let result: HealthWorkoutDeletionResult
            switch target {
            case .id(let id):
                result = try await health.deleteWorkout(id: id)
            case .match(let match):
                result = try await health.deleteWorkout(matching: match)
            }
            switch result {
            case .deleted:
                break
            case .noMatch:
                Self.logger.info("No HealthKit workout matched a deleted workout")
            case .ambiguous:
                Self.logger.warning("Several HealthKit workouts matched a deleted workout; left them in place")
            }
            return result
        } catch {
            Self.logger.error("Failed to delete HealthKit workout: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Deletes through a separate context, so a failed save leaves the
    /// caller's context and its pending changes untouched. Don't undo this
    /// with `rollback()` instead: rolling back a cascading delete traps
    /// inside SwiftData (ModelSnapshot: "Unexpected backing data").
    private func deleteModel(
        _ model: some PersistentModel,
        context: ModelContext,
        save: (ModelContext) throws -> Void
    ) throws {
        let deletionContext = ModelContext(context.container)
        deletionContext.autosaveEnabled = false
        deletionContext.delete(deletionContext.model(for: model.persistentModelID))
        try save(deletionContext)
    }
}
