//
//  ExpenditureCheckIn.swift
//  Vora
//
//  Created by Majd Arow on 2026-11-02.
//

import Foundation
import SwiftData

/// One completed weekly check-in. A skipped check-in is still saved: Skip
/// declines the targets, not the estimate, so it stays on the chart and is
/// next week's starting point.
@Model
final class ExpenditureCheckIn {
    @Attribute(.unique) var id: UUID
    /// The start of the check-in day this row answers.
    var date: Date
    var estimateKcal: Double
    var rawEstimateKcal: Double
    var avgIntakeKcal: Double
    var slopeKgPerDay: Double
    var daysUsed: Int
    var applied: Bool
    /// The targets written to the profile; nil when skipped.
    var appliedCalories: Int?
    var appliedProteinG: Int?
    var appliedCarbsG: Int?
    var appliedFatG: Int?

    init(
        id: UUID = UUID(),
        date: Date,
        estimateKcal: Double,
        rawEstimateKcal: Double,
        avgIntakeKcal: Double,
        slopeKgPerDay: Double,
        daysUsed: Int,
        applied: Bool,
        appliedCalories: Int? = nil,
        appliedProteinG: Int? = nil,
        appliedCarbsG: Int? = nil,
        appliedFatG: Int? = nil
    ) {
        self.id = id
        self.date = date
        self.estimateKcal = estimateKcal
        self.rawEstimateKcal = rawEstimateKcal
        self.avgIntakeKcal = avgIntakeKcal
        self.slopeKgPerDay = slopeKgPerDay
        self.daysUsed = daysUsed
        self.applied = applied
        self.appliedCalories = appliedCalories
        self.appliedProteinG = appliedProteinG
        self.appliedCarbsG = appliedCarbsG
        self.appliedFatG = appliedFatG
    }
}
