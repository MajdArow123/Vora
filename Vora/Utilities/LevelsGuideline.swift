//
//  LevelsGuideline.swift
//  Vora
//
//  Created by Majd Arow on 2026-11-02.
//

import Foundation

/// The optional reference band on Levels: roughly 10–20 sets a week is a common
/// hypertrophy guideline. It's a reference point, not a target, and needs vary
/// by person and muscle.
///
/// To remove it: delete this file and `LevelsGuidelineBand` in LevelsView.swift,
/// plus the footnote there. Nothing else depends on it.
enum LevelsGuideline {
    static let weeklySets = 10.0...20.0

    /// Per muscle so a muscle can get its own band, or none (nil).
    static func band(for muscle: Muscle) -> ClosedRange<Double>? {
        weeklySets
    }

    static let footnote = "Shaded: 10–20 sets a week, a common hypertrophy guideline, not a prescription."
}
