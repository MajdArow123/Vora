//
//  SplitDay.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import Foundation
import SwiftData

/// One day of the user's weekly training structure. Seven rows
/// (dayIndex 0 = Monday … 6 = Sunday) are seeded from the chosen
/// TrainingSplit template and edited via the split builder.
@Model
final class SplitDay {
    @Attribute(.unique) var id: UUID
    var dayIndex: Int
    var title: String
    var muscleGroups: [String]
    var isRest: Bool

    init(
        id: UUID = UUID(),
        dayIndex: Int,
        title: String,
        muscleGroups: [String] = [],
        isRest: Bool = false
    ) {
        self.id = id
        self.dayIndex = dayIndex
        self.title = title
        self.muscleGroups = muscleGroups
        self.isRest = isRest
    }

    static let dayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
}

struct SplitDayTemplate {
    let title: String
    let muscleGroups: [String]
    let isRest: Bool

    static func rest() -> SplitDayTemplate {
        SplitDayTemplate(title: "Rest", muscleGroups: [], isRest: true)
    }

    static func day(_ title: String, _ muscleGroups: [String]) -> SplitDayTemplate {
        SplitDayTemplate(title: title, muscleGroups: muscleGroups, isRest: false)
    }
}

extension TrainingSplit {
    /// Monday-first weekly template for each built-in split; custom
    /// starts as a blank week the builder fills in.
    var weeklyTemplate: [SplitDayTemplate] {
        let upper = ["chest", "back", "shoulders", "biceps", "triceps"]
        let lower = ["quads", "hamstrings", "glutes", "calves"]
        let push = ["chest", "shoulders", "triceps"]
        let pull = ["back", "biceps"]
        let legs = ["quads", "hamstrings", "glutes", "calves"]
        let full = ["chest", "back", "shoulders", "quads", "hamstrings", "core"]

        switch self {
        case .upperLower:
            return [
                .day("Upper", upper), .day("Lower", lower), .rest(),
                .day("Upper", upper), .day("Lower", lower), .rest(), .rest(),
            ]
        case .ppl:
            return [
                .day("Push", push), .day("Pull", pull), .day("Legs", legs),
                .day("Push", push), .day("Pull", pull), .day("Legs", legs), .rest(),
            ]
        case .fullBody:
            return [
                .day("Full Body", full), .rest(), .day("Full Body", full),
                .rest(), .day("Full Body", full), .rest(), .rest(),
            ]
        case .custom:
            return Array(repeating: .rest(), count: 7)
        }
    }
}
