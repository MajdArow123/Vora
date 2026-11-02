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
    /// UUID of the workout written to HealthKit. nil when none was written,
    /// and for rows saved before SchemaV4; deletion then matches on times.
    var healthKitWorkoutID: UUID?

    @Relationship(deleteRule: .cascade, inverse: \ExerciseLog.parent)
    var exercises: [ExerciseLog]

    init(
        id: UUID = UUID(),
        date: Date,
        sessionName: String,
        durationSeconds: Int = 0,
        totalVolumeKg: Double = 0,
        notes: String = "",
        healthKitWorkoutID: UUID? = nil,
        exercises: [ExerciseLog] = []
    ) {
        self.id = id
        self.date = date
        self.sessionName = sessionName
        self.durationSeconds = durationSeconds
        self.totalVolumeKg = totalVolumeKg
        self.notes = notes
        self.healthKitWorkoutID = healthKitWorkoutID
        self.exercises = exercises
    }
}
