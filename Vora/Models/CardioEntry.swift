//
//  CardioEntry.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import Foundation
import SwiftData

enum CardioType: String, Codable, CaseIterable, Identifiable {
    case run
    case walk
    case cycle
    case row
    case swim
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .run: "Run"
        case .walk: "Walk"
        case .cycle: "Cycle"
        case .row: "Row"
        case .swim: "Swim"
        case .other: "Other"
        }
    }

    var iconName: String {
        switch self {
        case .run: "figure.run"
        case .walk: "figure.walk"
        case .cycle: "figure.outdoor.cycle"
        case .row: "figure.rower"
        case .swim: "figure.pool.swim"
        case .other: "heart.circle"
        }
    }

    /// Metabolic equivalent used for calorie estimation
    /// (kcal = MET × body weight kg × hours).
    var met: Double {
        switch self {
        case .run: 9.8
        case .walk: 3.5
        case .cycle: 7.5
        case .row: 7.0
        case .swim: 8.0
        case .other: 6.0
        }
    }
}

@Model
final class CardioEntry {
    @Attribute(.unique) var id: UUID
    var date: Date
    var type: CardioType
    var durationSeconds: Int
    var estimatedCalories: Double

    init(
        id: UUID = UUID(),
        date: Date,
        type: CardioType,
        durationSeconds: Int,
        estimatedCalories: Double
    ) {
        self.id = id
        self.date = date
        self.type = type
        self.durationSeconds = durationSeconds
        self.estimatedCalories = estimatedCalories
    }
}
