//
//  WeightEntry.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import Foundation
import SwiftData

@Model
final class WeightEntry {
    @Attribute(.unique) var id: UUID
    var date: Date
    var weightKg: Double
    /// Body fat percentage. 0 means not recorded.
    var bodyFatPercent: Double

    init(
        id: UUID = UUID(),
        date: Date,
        weightKg: Double,
        bodyFatPercent: Double = 0
    ) {
        self.id = id
        self.date = date
        self.weightKg = weightKg
        self.bodyFatPercent = bodyFatPercent
    }
}
