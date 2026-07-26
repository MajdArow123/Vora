//
//  SupplementLog.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-26.
//

import Foundation
import SwiftData

@Model
final class SupplementLog {
    @Attribute(.unique) var id: UUID
    /// Plain reference rather than a relationship, so logs survive the
    /// supplement being deactivated without cascade concerns.
    var supplementID: UUID
    /// Name and dose are snapshotted at log time — history stays accurate
    /// even if the supplement is later renamed or re-dosed.
    var supplementName: String
    var dose: String
    /// Calendar day the supplement was taken, stored as start of day.
    var date: Date
    var takenAt: Date

    init(
        id: UUID = UUID(),
        supplementID: UUID,
        supplementName: String,
        dose: String,
        date: Date,
        takenAt: Date = .now
    ) {
        self.id = id
        self.supplementID = supplementID
        self.supplementName = supplementName
        self.dose = dose
        self.date = date
        self.takenAt = takenAt
    }
}
