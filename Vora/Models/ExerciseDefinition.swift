//
//  ExerciseDefinition.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import Foundation

enum MuscleGroup: String, CaseIterable, Identifiable {
    case chest, back, shoulders, biceps, triceps
    case quads, hamstrings, glutes, calves, core

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chest: "Chest"
        case .back: "Back"
        case .shoulders: "Shoulders"
        case .biceps: "Biceps"
        case .triceps: "Triceps"
        case .quads: "Quads"
        case .hamstrings: "Hamstrings"
        case .glutes: "Glutes"
        case .calves: "Calves"
        case .core: "Core"
        }
    }
}

/// Whether an exercise works several joints at once. Drives the default
/// rest between sets.
enum ExerciseMechanics: String, CaseIterable {
    case compound
    case isolation
}

/// A library exercise. Not persisted — the bundled catalog lives in
/// ExerciseLibrary; logged exercises store name + muscle groups on
/// ExerciseLog.
struct ExerciseDefinition: Identifiable, Hashable {
    /// Permanent slug identity, persisted on ExerciseLog.exerciseId.
    /// Never derive it from `name` or change it once shipped: renaming
    /// an exercise only changes `name`.
    let id: String
    let name: String
    let muscleGroup: MuscleGroup
    let mechanics: ExerciseMechanics
    let equipment: Set<EquipmentType>
    /// Muscles the exercise is programmed to train.
    let primaryMuscles: Set<Muscle>
    /// Muscles that assist without being the target; never overlaps
    /// `primaryMuscles`.
    let secondaryMuscles: Set<Muscle>
    /// Short imperative form pointers, shown in the exercise detail view.
    let techniqueCues: [String]
    /// Kept only so logged history and old templates still resolve; never
    /// offered in the exercise picker.
    var isLegacyOnly = false

    /// Everything the exercise needs must be on offer for it to count as
    /// doable in a given gym.
    func isAvailable(with availableEquipment: Set<EquipmentType>) -> Bool {
        equipment.isSubset(of: availableEquipment)
    }

    var equipmentText: String {
        equipment
            .map(\.displayName)
            .sorted()
            .joined(separator: " · ")
    }
}
