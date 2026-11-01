//
//  Muscle.swift
//  Vora
//
//  Created by Majd Arow on 2026-08-10.
//

import Foundation

/// Fine-grained anatomical muscle, used for the body diagram and
/// per-exercise primary/secondary tagging. Distinct from the coarse
/// `MuscleGroup` categories used for filtering and split planning.
enum Muscle: String, Codable, CaseIterable, Identifiable {
    case chest
    case frontDelts
    case sideDelts
    case rearDelts
    case biceps
    case triceps
    case forearms
    case lats
    case traps
    case upperBack
    case lowerBack
    case abs
    case obliques
    case glutes
    case quads
    case hamstrings
    case calves

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chest: "Chest"
        case .frontDelts: "Front Delts"
        case .sideDelts: "Side Delts"
        case .rearDelts: "Rear Delts"
        case .biceps: "Biceps"
        case .triceps: "Triceps"
        case .forearms: "Forearms"
        case .lats: "Lats"
        case .traps: "Traps"
        case .upperBack: "Upper Back"
        case .lowerBack: "Lower Back"
        case .abs: "Abs"
        case .obliques: "Obliques"
        case .glutes: "Glutes"
        case .quads: "Quads"
        case .hamstrings: "Hamstrings"
        case .calves: "Calves"
        }
    }
}
