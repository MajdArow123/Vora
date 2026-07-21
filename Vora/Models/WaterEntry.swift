//
//  WaterEntry.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import Foundation
import SwiftData

@Model
final class WaterEntry {
    @Attribute(.unique) var id: UUID
    var date: Date
    var amountMl: Double

    init(
        id: UUID = UUID(),
        date: Date,
        amountMl: Double
    ) {
        self.id = id
        self.date = date
        self.amountMl = amountMl
    }
}
