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

/// A library exercise. Not persisted — the bundled catalog lives in
/// ExerciseLibrary; logged exercises store name + muscle groups on
/// ExerciseLog.
struct ExerciseDefinition: Identifiable, Hashable {
    let name: String
    let muscleGroup: MuscleGroup
    let equipment: Set<EquipmentType>

    var id: String { name }

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
