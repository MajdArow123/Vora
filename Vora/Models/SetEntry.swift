//
//  SetEntry.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import Foundation
import SwiftData

@Model
final class SetEntry {
    @Attribute(.unique) var id: UUID
    var setNumber: Int
    var weightKg: Double
    var reps: Int
    var isCompleted: Bool
    /// Reps in reserve, 0–5: 0 means failure, 5 means five or more. nil
    /// means not logged, which is different from 0.
    var rir: Int?
    /// `SetType` raw value. nil on rows saved before SchemaV8, which are normal.
    var setTypeRawValue: String?
    /// `SetSide` raw value. nil when the set wasn't unilateral.
    var sideRawValue: String?

    var parent: ExerciseLog?

    init(
        id: UUID = UUID(),
        setNumber: Int,
        weightKg: Double,
        reps: Int,
        isCompleted: Bool = false,
        rir: Int? = nil,
        setType: SetType = .normal,
        side: SetSide? = nil
    ) {
        self.id = id
        self.setNumber = setNumber
        self.weightKg = weightKg
        self.reps = reps
        self.isCompleted = isCompleted
        self.rir = rir
        self.setTypeRawValue = setType == .normal ? nil : setType.rawValue
        self.sideRawValue = side?.rawValue
    }
}

extension SetEntry {
    var setType: SetType { SetType(stored: setTypeRawValue) }
    var side: SetSide? { sideRawValue.flatMap(SetSide.init(rawValue:)) }
    /// Logged RIR, else what the set type implies. Implied values are never
    /// stored, so `rir` stays nil when nothing was logged.
    var effectiveRIR: Int? { setType.effectiveRIR(logged: rir) }
}
