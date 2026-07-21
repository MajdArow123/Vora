//
//  WorkoutSession.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import Foundation
import SwiftData

@Model
final class WorkoutSession {
    @Attribute(.unique) var id: UUID
    var date: Date
    var sessionName: String
    var durationSeconds: Int
    var totalVolumeKg: Double
    var notes: String

    @Relationship(deleteRule: .cascade, inverse: \ExerciseLog.parent)
    var exercises: [ExerciseLog]

    init(
        id: UUID = UUID(),
        date: Date,
        sessionName: String,
        durationSeconds: Int = 0,
        totalVolumeKg: Double = 0,
        notes: String = "",
        exercises: [ExerciseLog] = []
    ) {
        self.id = id
        self.date = date
        self.sessionName = sessionName
        self.durationSeconds = durationSeconds
        self.totalVolumeKg = totalVolumeKg
        self.notes = notes
        self.exercises = exercises
    }
}
