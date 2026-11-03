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

/// Which split or cycle day a session came from, so a fix can save to its
/// template and finishing can advance the cycle.
nonisolated struct TemplateSlot: Codable, Equatable {
    var splitRawValue: String
    var dayIndex: Int
    /// Set for a cycle day; older drafts and weekly slots decode as nil.
    var cycleDayID: UUID?

    init(split: TrainingSplit, dayIndex: Int) {
        self.splitRawValue = split.rawValue
        self.dayIndex = dayIndex
    }

    init(cycleDayID: UUID) {
        self.splitRawValue = "cycle"
        self.dayIndex = -1
        self.cycleDayID = cycleDayID
    }
}

/// Codable snapshot of an in-progress session, written to disk so a
/// killed app can resume the workout. Weights are kilograms.
nonisolated struct ActiveSessionDraft: Codable, Equatable {
    /// Version 2 added `Set.rir`. Version 3 added recommendations and the
    /// template slot. Version 4 added set types, sides and superset groups.
    /// Version 5 added the slot's cycle day. Older drafts decode as they are,
    /// with none of them.
    static let currentVersion = 5
    static let readableVersions = 1...currentVersion

    struct Exercise: Codable, Equatable {
        /// Library ID; nil for custom exercises.
        var exerciseId: String?
        /// Set only for custom exercises.
        var customName: String?
        var muscleGroups: [String]
        var restSeconds: Int
        var targets: TemplateTargets?
        var sets: [Set]
        var predictedE1RMKg: Double?
        var daysSinceLastSession: Int?
        var supersetGroup: Int?
    }

    struct Set: Codable, Equatable {
        var weightKg: Double?
        var reps: Int?
        var isCompleted: Bool
        var rir: Int?
        var recommendation: Recommendation?
        var plannedRecommendation: Recommendation?
        /// nil means normal.
        var setType: SetType?
        var side: SetSide?
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
    var templateSlot: TemplateSlot?
}
