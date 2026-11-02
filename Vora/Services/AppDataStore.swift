//
//  AppDataStore.swift
//  Vora
//
//  Created by Majd Arow on 2026-11-01.
//

import Foundation
import Observation
import OSLog
import SwiftData

/// Owns opening the persistent store at launch. A failure leaves the
/// store untouched and moves to `.failed` so the app can offer Retry
/// and Export instead of crashing.
@Observable
final class AppDataStore {
    enum State {
        case loading
        case ready(ModelContainer)
        /// Technical description of why the store could not be opened.
        case failed(String)
    }

    private(set) var state: State = .loading

    private let open: () throws -> ModelContainer
    private let backfillExerciseIDs: (ModelContext) throws -> Int
    private let migrateTemplates: (ModelContext) throws -> TemplateDefaultsMigration.Outcome
    private let backfillGymInventories: (ModelContext) throws -> Int

    init(
        open: @escaping () throws -> ModelContainer = { try PersistenceController.makeContainer() },
        backfillExerciseIDs: @escaping (ModelContext) throws -> Int = { try ExerciseIDBackfill.run(in: $0) },
        migrateTemplates: @escaping (ModelContext) throws -> TemplateDefaultsMigration.Outcome = {
            try TemplateDefaultsMigration.run(in: $0, defaults: .standard)
        },
        backfillGymInventories: @escaping (ModelContext) throws -> Int = { try GymInventoryBackfill.run(in: $0) }
    ) {
        self.open = open
        self.backfillExerciseIDs = backfillExerciseIDs
        self.migrateTemplates = migrateTemplates
        self.backfillGymInventories = backfillGymInventories
    }

    var container: ModelContainer? {
        if case .ready(let container) = state { return container }
        return nil
    }

    /// Opens the store and runs the launch-time data repairs. No-op once
    /// a container is ready.
    func load() {
        guard container == nil else { return }
        state = .loading

        do {
            let container = try open()
            #if DEBUG
            DemoSeeder.seedIfRequested(container: container)
            #endif
            GymProfileService.ensureDefaultProfile(context: ModelContext(container))
            runExerciseIDBackfill(in: container)
            runTemplateMigration(in: container)
            runGymInventoryBackfill(in: container)
            state = .ready(container)
        } catch {
            PersistenceController.logger.error(
                "Failed to open the data store: \(String(describing: error), privacy: .public)"
            )
            state = .failed(String(describing: error))
        }
    }

    /// Never blocks launch: rows left unfilled still match through the
    /// name fallback in ExerciseIdentity, and the next launch retries.
    private func runExerciseIDBackfill(in container: ModelContainer) {
        do {
            let filled = try backfillExerciseIDs(ModelContext(container))
            if filled > 0 {
                PersistenceController.logger.info("Backfilled exercise IDs on \(filled, privacy: .public) logs")
            }
        } catch {
            PersistenceController.logger.error(
                "Exercise ID backfill failed: \(String(describing: error), privacy: .public)"
            )
        }
    }

    /// Never blocks launch: until it succeeds the app shows the built-in
    /// default templates, and the UserDefaults data stays for the next try.
    private func runTemplateMigration(in container: ModelContainer) {
        do {
            let outcome = try migrateTemplates(ModelContext(container))
            if outcome.removedKey || outcome.invalid > 0 {
                PersistenceController.logger.info(
                    """
                    Template migration: \(outcome.migrated, privacy: .public) migrated, \
                    \(outcome.skippedExisting, privacy: .public) already present, \
                    \(outcome.invalid, privacy: .public) unreadable, \
                    key removed: \(outcome.removedKey, privacy: .public)
                    """
                )
            }
        } catch {
            PersistenceController.logger.error(
                "Template migration failed: \(String(describing: error), privacy: .public)"
            )
        }
    }

    /// Never blocks launch: an unfilled gym shows an empty plate calculator
    /// until a later launch fills it.
    private func runGymInventoryBackfill(in container: ModelContainer) {
        do {
            let filled = try backfillGymInventories(ModelContext(container))
            if filled > 0 {
                PersistenceController.logger.info("Filled loading inventory on \(filled, privacy: .public) gyms")
            }
        } catch {
            PersistenceController.logger.error(
                "Gym inventory backfill failed: \(String(describing: error), privacy: .public)"
            )
        }
    }

    func retry() {
        load()
    }
}
