//
//  SchemaV3.swift
//  Vora
//
//  Created by Majd Arow on 2026-11-01.
//

import Foundation
import SwiftData

/// Adds WorkoutTemplate and TemplateExercise, replacing the UserDefaults
/// template dictionary. No V2 model gained a relationship to the new ones.
/// Saved UserDefaults templates are moved in after the store opens by
/// `TemplateDefaultsMigration`. Models a later version changed are frozen
/// below (see docs/MIGRATIONS.md).
nonisolated enum SchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            UserProfile.self,
            FoodEntry.self,
            CustomFood.self,
            SchemaV3.WorkoutSession.self,
            SchemaV3.ExerciseLog.self,
            SchemaV3.SetEntry.self,
            WeightEntry.self,
            BodyMeasurement.self,
            WaterEntry.self,
            SchemaV3.CardioEntry.self,
            SplitDay.self,
            SavedMeal.self,
            SavedMealItem.self,
            Recipe.self,
            RecipeIngredient.self,
            Supplement.self,
            SupplementLog.self,
            SchemaV3.GymProfile.self,
            WorkoutTemplate.self,
            TemplateExercise.self,
        ]
    }
}

// MARK: - Frozen V3 models

// Verbatim copies of the live classes as of SchemaV3. Do not edit.
// The workout cluster is frozen together because its relationships
// reference one another; CardioEntry has no relationships.
extension SchemaV3 {
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

    @Model
    final class CardioEntry {
        @Attribute(.unique) var id: UUID
        var date: Date
        var type: CardioType
        var durationSeconds: Int
        var estimatedCalories: Double

        // Machine-specific stats. All optional so pre-existing rows migrate
        // untouched; only the fields relevant to `type` are ever populated.
        var speedKmh: Double?
        var inclinePercent: Double?
        var resistanceLevel: Int?
        var strokesPerMinute: Int?
        var stepsPerMinute: Int?
        var rpm: Int?
        var distanceKm: Double?
        /// Minutes per kilometre.
        var pace: Double?

        init(
            id: UUID = UUID(),
            date: Date,
            type: CardioType,
            durationSeconds: Int,
            estimatedCalories: Double,
            speedKmh: Double? = nil,
            inclinePercent: Double? = nil,
            resistanceLevel: Int? = nil,
            strokesPerMinute: Int? = nil,
            stepsPerMinute: Int? = nil,
            rpm: Int? = nil,
            distanceKm: Double? = nil,
            pace: Double? = nil
        ) {
            self.id = id
            self.date = date
            self.type = type
            self.durationSeconds = durationSeconds
            self.estimatedCalories = estimatedCalories
            self.speedKmh = speedKmh
            self.inclinePercent = inclinePercent
            self.resistanceLevel = resistanceLevel
            self.strokesPerMinute = strokesPerMinute
            self.stepsPerMinute = stepsPerMinute
            self.rpm = rpm
            self.distanceKm = distanceKm
            self.pace = pace
        }
    }
}

// Verbatim copy of the live GymProfile as of SchemaV3. Do not edit. It has
// no relationships, so nothing else joins it.
extension SchemaV3 {
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
