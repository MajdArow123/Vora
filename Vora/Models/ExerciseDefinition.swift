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

enum Equipment: String, CaseIterable, Identifiable {
    case barbell, dumbbell, machine, cable, bodyweight, kettlebell

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .barbell: "Barbell"
        case .dumbbell: "Dumbbell"
        case .machine: "Machine"
        case .cable: "Cable"
        case .bodyweight: "Bodyweight"
        case .kettlebell: "Kettlebell"
        }
    }
}

/// A library exercise. Not persisted — the bundled catalog lives in
/// ExerciseLibrary; logged exercises store name + muscle groups on
/// ExerciseLog.
struct ExerciseDefinition: Identifiable, Hashable {
    let name: String
    let muscleGroup: MuscleGroup
    let equipment: Equipment

    var id: String { name }
}
