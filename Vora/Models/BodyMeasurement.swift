//
//  BodyMeasurement.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-26.
//

import Foundation
import SwiftData

@Model
final class BodyMeasurement {
    @Attribute(.unique) var id: UUID
    var date: Date
    var waistCm: Double?
    var hipsCm: Double?
    var chestCm: Double?
    var leftArmCm: Double?
    var rightArmCm: Double?
    var leftThighCm: Double?
    var rightThighCm: Double?
    var neckCm: Double?
    var bodyFatPercent: Double?
    var notes: String?

    init(
        id: UUID = UUID(),
        date: Date = .now,
        waistCm: Double? = nil,
        hipsCm: Double? = nil,
        chestCm: Double? = nil,
        leftArmCm: Double? = nil,
        rightArmCm: Double? = nil,
        leftThighCm: Double? = nil,
        rightThighCm: Double? = nil,
        neckCm: Double? = nil,
        bodyFatPercent: Double? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.date = date
        self.waistCm = waistCm
        self.hipsCm = hipsCm
        self.chestCm = chestCm
        self.leftArmCm = leftArmCm
        self.rightArmCm = rightArmCm
        self.leftThighCm = leftThighCm
        self.rightThighCm = rightThighCm
        self.neckCm = neckCm
        self.bodyFatPercent = bodyFatPercent
        self.notes = notes
    }
}
