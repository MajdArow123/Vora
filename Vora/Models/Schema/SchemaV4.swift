//
//  SchemaV4.swift
//  Vora
//
//  Created by Majd Arow on 2026-11-02.
//

import Foundation
import SwiftData

/// Replaces `SetEntry.rpe`, which nothing ever wrote, with the optional
/// `SetEntry.rir`, and adds the optional `healthKitWorkoutID` to
/// WorkoutSession and CardioEntry. Models a later version changed are frozen
/// below (see docs/MIGRATIONS.md).
nonisolated enum SchemaV4: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(4, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            UserProfile.self,
            FoodEntry.self,
            CustomFood.self,
            SchemaV4.WorkoutSession.self,
            SchemaV4.ExerciseLog.self,
            SchemaV4.SetEntry.self,
            WeightEntry.self,
            BodyMeasurement.self,
            WaterEntry.self,
            CardioEntry.self,
            SplitDay.self,
            SavedMeal.self,
            SavedMealItem.self,
            Recipe.self,
            RecipeIngredient.self,
            Supplement.self,
            SupplementLog.self,
            SchemaV4.GymProfile.self,
            WorkoutTemplate.self,
            TemplateExercise.self,
        ]
    }
}

// Verbatim copies of the live workout cluster as of SchemaV4. Do not edit.
extension SchemaV4 {
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

    @Model
    final class ExerciseLog {
        @Attribute(.unique) var id: UUID
        var exerciseName: String
        /// Permanent ExerciseLibrary ID. nil for custom exercises, and for
        /// pre-V2 rows until ExerciseIDBackfill fills them.
        var exerciseId: String?
        var muscleGroups: [String]
        var orderIndex: Int

        @Relationship(deleteRule: .cascade, inverse: \SetEntry.parent)
        var sets: [SetEntry]

        var parent: WorkoutSession?

        init(
            id: UUID = UUID(),
            exerciseName: String,
            exerciseId: String? = nil,
            muscleGroups: [String] = [],
            orderIndex: Int,
            sets: [SetEntry] = []
        ) {
            self.id = id
            self.exerciseName = exerciseName
            self.exerciseId = exerciseId
            self.muscleGroups = muscleGroups
            self.orderIndex = orderIndex
            self.sets = sets
        }
    }

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
}

// Verbatim copy of the live GymProfile as of SchemaV4. Do not edit. It has
// no relationships, so nothing else joins it.
extension SchemaV4 {
    @Model
    final class GymProfile {
        var name: String
        var preset: GymPreset
        /// Raw values persisted as a plain string array so the schema stays a
        /// lightweight, additive change. Unknown values from future app
        /// versions are dropped on read rather than crashing.
        private var equipmentRawValues: [String]
        var isActive: Bool
        var createdAt: Date

        var availableEquipment: Set<EquipmentType> {
            get { Set(equipmentRawValues.compactMap(EquipmentType.init(rawValue:))) }
            set { equipmentRawValues = newValue.map(\.rawValue).sorted() }
        }

        init(
            name: String,
            preset: GymPreset,
            availableEquipment: Set<EquipmentType>? = nil,
            isActive: Bool = false,
            createdAt: Date = .now
        ) {
            self.name = name
            self.preset = preset
            self.equipmentRawValues = (availableEquipment ?? preset.defaultEquipment)
                .map(\.rawValue)
                .sorted()
            self.isActive = isActive
            self.createdAt = createdAt
        }

        /// Applies a preset, replacing the equipment with the preset's
        /// defaults as a starting point for further edits.
        func applyPreset(_ newPreset: GymPreset) {
            preset = newPreset
            if newPreset != .custom {
                availableEquipment = newPreset.defaultEquipment
            }
        }

        /// Replaces the equipment set. Hand-editing away from the preset's
        /// defaults flips the preset to custom; matching them again keeps it.
        func updateEquipment(_ newValue: Set<EquipmentType>) {
            availableEquipment = newValue
            if preset != .custom, newValue != preset.defaultEquipment {
                preset = .custom
            }
        }
    }
}
