//
//  VoraMigrationPlan.swift
//  Vora
//
//  Created by Majd Arow on 2026-11-01.
//

import Foundation
import SwiftData

/// Ordered history of every schema version and the stages between them.
/// Adding a version means appending it to `schemas` and appending the
/// stage that reaches it from the previous one to `stages`.
nonisolated enum VoraMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self, SchemaV3.self, SchemaV4.self]
    }

    static var stages: [MigrationStage] {
        [
            // Adds the optional ExerciseLog.exerciseId; values are filled
            // after opening by ExerciseIDBackfill.
            .lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self),
            // Adds the WorkoutTemplate and TemplateExercise entities; saved
            // UserDefaults templates are moved in after opening by
            // TemplateDefaultsMigration.
            .lightweight(fromVersion: SchemaV2.self, toVersion: SchemaV3.self),
            // Drops SetEntry.rpe, never written by any build (evidence in
            // docs/MIGRATIONS.md), and adds the optional SetEntry.rir and
            // healthKitWorkoutID on WorkoutSession and CardioEntry.
            .lightweight(fromVersion: SchemaV3.self, toVersion: SchemaV4.self),
        ]
    }
}

/// The schema the app currently runs on. Always the last entry of
/// `VoraMigrationPlan.schemas`.
typealias CurrentSchema = SchemaV4
