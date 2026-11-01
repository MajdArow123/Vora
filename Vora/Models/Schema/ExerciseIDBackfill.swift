//
//  ExerciseIDBackfill.swift
//  Vora
//
//  Created by Majd Arow on 2026-11-01.
//

import Foundation
import SwiftData

/// Fills `ExerciseLog.exerciseId` for rows saved before SchemaV2 by
/// resolving their stored name against the library. Runs after the store
/// opens; idempotent, so running it on every launch is cheap once done.
enum ExerciseIDBackfill {
    /// Returns how many rows were filled. Custom exercises (names not in
    /// the library) keep a nil ID and never count.
    @discardableResult
    static func run(in context: ModelContext) throws -> Int {
        let descriptor = FetchDescriptor<ExerciseLog>(
            predicate: #Predicate { $0.exerciseId == nil }
        )
        var filled = 0
        for log in try context.fetch(descriptor) {
            guard let definition = ExerciseLibrary.legacyDefinition(
                lowercasedName: log.exerciseName.lowercased()
            ) else { continue }
            log.exerciseId = definition.id
            filled += 1
        }
        if filled > 0 {
            try context.save()
        }
        return filled
    }
}
