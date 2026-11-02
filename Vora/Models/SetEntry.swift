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

    var parent: ExerciseLog?

    init(
        id: UUID = UUID(),
        setNumber: Int,
        weightKg: Double,
        reps: Int,
        isCompleted: Bool = false,
        rir: Int? = nil
    ) {
        self.id = id
        self.setNumber = setNumber
        self.weightKg = weightKg
        self.reps = reps
        self.isCompleted = isCompleted
        self.rir = rir
    }
}
