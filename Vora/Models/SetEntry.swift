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
    /// Rate of perceived exertion, 1–10. 0 means not set.
    var rpe: Int

    var parent: ExerciseLog?

    init(
        id: UUID = UUID(),
        setNumber: Int,
        weightKg: Double,
        reps: Int,
        isCompleted: Bool = false,
        rpe: Int = 0
    ) {
        self.id = id
        self.setNumber = setNumber
        self.weightKg = weightKg
        self.reps = reps
        self.isCompleted = isCompleted
        self.rpe = rpe
    }
}
