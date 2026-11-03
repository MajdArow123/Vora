//
//  RestActivityAttributes.swift
//  Vora
//
//  Created by Majd Arow on 2026-11-03.
//

import ActivityKit
import Foundation

/// The rest timer's Live Activity, shared by the app and the widget extension.
/// Everything lives in the content state, so a new rest updates the running
/// activity instead of needing another one. Text is formatted by the app in
/// the user's units: a free provisioning team has no App Group to read
/// settings through.
nonisolated struct RestActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var exerciseName: String
        var nextSetText: String
        var startDate: Date
        var endDate: Date

        /// For timer text and progress, which trap on an inverted range.
        var timerRange: ClosedRange<Date> {
            min(startDate, endDate)...endDate
        }
    }
}
