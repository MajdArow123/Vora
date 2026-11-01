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
/// stage that reaches it from the previous one to `stages`, e.g.
/// `MigrationStage.lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self)`.
nonisolated enum VoraMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}

/// The schema the app currently runs on. Always the last entry of
/// `VoraMigrationPlan.schemas`.
typealias CurrentSchema = SchemaV1
