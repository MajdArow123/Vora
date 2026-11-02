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
            WorkoutSession.self,
            ExerciseLog.self,
            SetEntry.self,
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
