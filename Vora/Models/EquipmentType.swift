//
//  EquipmentType.swift
//  Vora
//
//  Created by Majd Arow on 2026-08-10.
//

import Foundation

/// A piece of gym equipment an exercise can require and a gym profile can
/// offer. An exercise is available in a gym when its equipment set is a
/// subset of the gym's available equipment.
enum EquipmentType: String, Codable, CaseIterable, Identifiable {
    case barbell
    case dumbbell
    case machine
    case cable
    case smithMachine
    case kettlebell
    case resistanceBand
    case pullUpBar
    case bench
    case bodyweight

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .barbell: "Barbell"
        case .dumbbell: "Dumbbell"
        case .machine: "Machine"
        case .cable: "Cable"
        case .smithMachine: "Smith Machine"
        case .kettlebell: "Kettlebell"
        case .resistanceBand: "Resistance Band"
        case .pullUpBar: "Pull-Up Bar"
        case .bench: "Bench"
        case .bodyweight: "Bodyweight"
        }
    }

    var symbolName: String {
        switch self {
        case .barbell: "figure.strengthtraining.traditional"
        case .dumbbell: "dumbbell"
        case .machine: "gearshape.2"
        case .cable: "cable.connector"
        case .smithMachine: "arrow.up.and.down.square"
        case .kettlebell: "scalemass"
        case .resistanceBand: "figure.flexibility"
        case .pullUpBar: "figure.climbing"
        case .bench: "chair.lounge"
        case .bodyweight: "figure.arms.open"
        }
    }
}
