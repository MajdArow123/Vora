//
//  TemplateDefaultsMigration.swift
//  Vora
//
//  Created by Majd Arow on 2026-11-01.
//

import Foundation
import OSLog
import SwiftData

/// Moves templates saved in UserDefaults before SchemaV3 into
/// WorkoutTemplate rows. Runs after the store opens; idempotent, so it is
/// safe to run on every launch. The UserDefaults key is removed only after
/// the rows are saved, so a failure leaves the old data for the next try.
enum TemplateDefaultsMigration {
    /// The pre-V3 dictionary: `"<TrainingSplit.rawValue>.<dayIndex>"` →
    /// exercise names in order.
    static let storageKey = "vora.workoutTemplates"

    struct Outcome: Equatable {
        /// Templates created from UserDefaults entries.
        var migrated = 0
        /// Entries skipped because the slot already had a template.
        var skippedExisting = 0
        /// Entries whose key or value could not be read.
        var invalid = 0
        var removedKey = false
    }

    private static let logger = Logger(subsystem: "com.majdarow.Vora", category: "Persistence")

    /// - Parameter save: Persists the inserted rows; injectable so tests
    ///   can simulate a failed save.
    static func run(
        in context: ModelContext,
        defaults: UserDefaults,
        save: (ModelContext) throws -> Void = { try $0.save() }
    ) throws -> Outcome {
        var outcome = Outcome()
        guard let stored = defaults.object(forKey: storageKey) else { return outcome }
        guard let entries = stored as? [String: Any] else {
            // Unreadable by every build, but never destroy data we could
            // not interpret.
            logger.error("Saved templates are not a dictionary; leaving them in place")
            outcome.invalid = 1
            return outcome
        }

        for key in entries.keys.sorted() {
            guard let (split, dayIndex) = slot(fromKey: key),
                  let names = entries[key] as? [String]
            else {
                logger.error("Skipping unreadable saved template \(key, privacy: .public)")
                outcome.invalid += 1
                continue
            }
            if try WorkoutTemplateService.template(for: split, dayIndex: dayIndex, context: context) != nil {
                outcome.skippedExisting += 1
                continue
            }
            context.insert(makeTemplate(split: split, dayIndex: dayIndex, names: names))
            outcome.migrated += 1
        }

        do {
            try save(context)
        } catch {
            context.rollback()
            throw error
        }
        defaults.removeObject(forKey: storageKey)
        outcome.removedKey = true
        return outcome
    }

    static func slot(fromKey key: String) -> (TrainingSplit, Int)? {
        let parts = key.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let split = TrainingSplit(rawValue: String(parts[0])),
              let dayIndex = Int(parts[1]),
              WorkoutTemplateService.dayIndices.contains(dayIndex)
        else { return nil }
        return (split, dayIndex)
    }

    /// Library names (current or legacy aliases) become IDs; anything else
    /// is kept as a custom exercise. Blank names are dropped.
    private static func makeTemplate(split: TrainingSplit, dayIndex: Int, names: [String]) -> WorkoutTemplate {
        let template = WorkoutTemplate(
            split: split,
            dayIndex: dayIndex,
            name: WorkoutTemplateService.defaultName(for: split, dayIndex: dayIndex)
        )
        let trimmed = names
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        template.exercises = trimmed.enumerated().map { index, name in
            let definition = ExerciseLibrary.legacyDefinition(lowercasedName: name.lowercased())
            return TemplateExercise(
                exerciseId: definition?.id,
                customName: definition == nil ? name : nil,
                orderIndex: index
            )
        }
        return template
    }
}
