//
//  ActiveSessionDraft.swift
//  Vora
//
//  Created by Majd Arow on 2026-11-01.
//

import Foundation

/// Template targets carried by a session exercise, mirroring
/// `TemplateExerciseSpec`. Nil on exercises added mid-session.
nonisolated struct TemplateTargets: Codable, Equatable {
    var targetSets: Int
    var repRangeMin: Int
    var repRangeMax: Int
    var targetRIR: Int?

    var repRange: ClosedRange<Int> {
        repRangeMin...max(repRangeMin, repRangeMax)
    }
}

/// Codable snapshot of an in-progress session, written to disk so a
/// killed app can resume the workout. Weights are kilograms.
nonisolated struct ActiveSessionDraft: Codable, Equatable {
    static let currentVersion = 1

    struct Exercise: Codable, Equatable {
        /// Library ID; nil for custom exercises.
        var exerciseId: String?
        /// Set only for custom exercises.
        var customName: String?
        var muscleGroups: [String]
        var restSeconds: Int
        var targets: TemplateTargets?
        var sets: [Set]
    }

    struct Set: Codable, Equatable {
        var weightKg: Double?
        var reps: Int?
        var isCompleted: Bool
    }

    var version = Self.currentVersion
    var sessionName: String
    var startDate: Date
    /// When this snapshot was written; drives expiry and the
    /// interruption gap on resume.
    var savedAt: Date
    var restEndDate: Date?
    /// Interruption time already excluded from the session's duration.
    var excludedSeconds: TimeInterval
    var exercises: [Exercise]
}
