//
//  RIRScale.swift
//  Vora
//
//  Created by Majd Arow on 2026-11-02.
//

import Foundation

/// The reps-in-reserve scale shared by logged sets and template targets:
/// 0 means failure and the top value means that many or more.
enum RIRScale {
    static let range = TemplateExerciseSpec.Limits.rir

    /// `value` if it's on the scale, otherwise nil.
    static func validated(_ value: Int?) -> Int? {
        guard let value, range.contains(value) else { return nil }
        return value
    }

    /// "2", or "5+" at the top of the scale.
    static func text(_ value: Int) -> String {
        value >= range.upperBound ? "\(range.upperBound)+" : "\(value)"
    }

    /// For VoiceOver: "failure", "2 reps in reserve", "5 or more reps in reserve".
    static func spokenText(_ value: Int) -> String {
        if value <= range.lowerBound { return "failure" }
        if value >= range.upperBound { return "\(range.upperBound) or more reps in reserve" }
        return value == 1 ? "1 rep in reserve" : "\(value) reps in reserve"
    }
}
