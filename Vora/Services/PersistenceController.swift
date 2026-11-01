//
//  PersistenceController.swift
//  Vora
//
//  Created by Majd Arow on 2026-11-01.
//

import Foundation
import OSLog
import SwiftData

/// Builds the app's ModelContainer on the current versioned schema with
/// the migration plan applied. Never deletes or recreates a store: a
/// failure is thrown to the caller, which shows the recovery screen.
enum PersistenceController {
    static let logger = Logger(subsystem: "com.majdarow.Vora", category: "Persistence")

    static var schema: Schema {
        Schema(versionedSchema: CurrentSchema.self)
    }

    /// Where the default store lives. Matches the location every
    /// pre-versioning build used, so existing data is picked up as is.
    static var defaultStoreURL: URL {
        ModelConfiguration(schema: schema, isStoredInMemoryOnly: false).url
    }

    /// - Parameters:
    ///   - url: Store file to open; nil opens the default store.
    ///   - inMemory: Ignores `url` and opens a throwaway store.
    static func makeContainer(url: URL? = nil, inMemory: Bool = false) throws -> ModelContainer {
        let schema = schema
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        } else if let url {
            configuration = ModelConfiguration(schema: schema, url: url)
        } else {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        }

        return try ModelContainer(
            for: schema,
            migrationPlan: VoraMigrationPlan.self,
            configurations: [configuration]
        )
    }
}
