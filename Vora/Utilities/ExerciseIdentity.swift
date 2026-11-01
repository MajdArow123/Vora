//
//  ExerciseIdentity.swift
//  Vora
//
//  Created by Majd Arow on 2026-11-01.
//

import Foundation
import SwiftData

/// How logged exercises are matched across sessions. Library exercises
/// match on their permanent ID, so renaming one keeps its history;
/// custom exercises (no library entry) match on their lowercased name.
enum ExerciseIdentity {
    static let customPrefix = "custom:"

    /// The stored ID, else the library ID for a legacy name, else a
    /// name-based custom key. Rows saved before IDs existed resolve to the
    /// same key as rows saved with one.
    static func key(exerciseId: String?, name: String) -> String {
        if let exerciseId { return exerciseId }
        let lowercased = name.lowercased()
        if let definition = ExerciseLibrary.legacyDefinition(lowercasedName: lowercased) {
            return definition.id
        }
        return customPrefix + lowercased
    }

    /// The library's current name for library exercises (including
    /// legacy rows saved under an older spelling), otherwise the name
    /// stored with the log.
    static func displayName(exerciseId: String?, name: String) -> String {
        ExerciseLibrary.definition(id: key(exerciseId: exerciseId, name: name))?.name ?? name
    }

    /// Library ID for a name chosen in the picker or a template; nil for
    /// custom names.
    static func libraryID(forName name: String) -> String? {
        ExerciseLibrary.definition(named: name)?.id
    }
}

extension ExerciseLog {
    var matchKey: String {
        ExerciseIdentity.key(exerciseId: exerciseId, name: exerciseName)
    }

    var displayName: String {
        ExerciseIdentity.displayName(exerciseId: exerciseId, name: exerciseName)
    }
}

extension ExerciseIdentity {
    /// Sessions that may contain the exercise, newest first: those with a
    /// log carrying `exerciseId`, plus those with any log that has no ID
    /// (legacy or custom rows). Callers confirm matches by `matchKey`.
    static func candidateSessions(exerciseId: String?) -> FetchDescriptor<WorkoutSession> {
        let target = exerciseId
        return FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { session in
                session.exercises.contains { log in
                    log.exerciseId == target || log.exerciseId == nil
                }
            },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
    }
}
