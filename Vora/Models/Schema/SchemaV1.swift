//
//  SchemaV1.swift
//  Vora
//
//  Created by Majd Arow on 2026-11-01.
//

import Foundation
import SwiftData

/// The schema every store shipped before versioning was introduced.
/// Models unchanged since then are shared with later versions; models a
/// later version changed (and every model whose relationships reference
/// them) are frozen below as verbatim nested copies, so this version
/// keeps describing exactly what V1 stores contain (see
/// docs/MIGRATIONS.md).
nonisolated enum SchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            UserProfile.self,
            FoodEntry.self,
            CustomFood.self,
            SchemaV1.WorkoutSession.self,
            SchemaV1.ExerciseLog.self,
            SchemaV1.SetEntry.self,
            WeightEntry.self,
            BodyMeasurement.self,
            WaterEntry.self,
            SchemaV1.CardioEntry.self,
            SplitDay.self,
            SavedMeal.self,
            SavedMealItem.self,
            Recipe.self,
            RecipeIngredient.self,
            Supplement.self,
            SupplementLog.self,
            SchemaV1.GymProfile.self,
        ]
    }
}

// MARK: - Frozen V1 models

// Verbatim copies of the live classes as of SchemaV1. Do not edit.
// Frozen together because their relationships reference one another.
extension SchemaV1 {
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
        var muscleGroups: [String]
        var orderIndex: Int

        @Relationship(deleteRule: .cascade, inverse: \SetEntry.parent)
        var sets: [SetEntry]

        var parent: WorkoutSession?

        init(
            id: UUID = UUID(),
            exerciseName: String,
            muscleGroups: [String] = [],
            orderIndex: Int,
            sets: [SetEntry] = []
        ) {
            self.id = id
            self.exerciseName = exerciseName
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

    // Frozen alone: it has no relationships.
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

// Verbatim copy of the live GymProfile as of SchemaV1. Do not edit. It has
// no relationships, so nothing else joins it.
extension SchemaV1 {
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
