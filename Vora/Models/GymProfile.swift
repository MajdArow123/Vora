//
//  GymProfile.swift
//  Vora
//
//  Created by Majd Arow on 2026-08-10.
//

import Foundation
import SwiftData

enum GymPreset: String, Codable, CaseIterable, Identifiable {
    case commercial
    case homeDumbbells
    case hotel
    case bodyweightOnly
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .commercial: "Commercial Gym"
        case .homeDumbbells: "Home (Dumbbells)"
        case .hotel: "Hotel Gym"
        case .bodyweightOnly: "Bodyweight Only"
        case .custom: "Custom"
        }
    }

    /// Equipment a preset seeds into a profile. Custom seeds nothing —
    /// it is what a profile becomes once the user hand-edits the toggles.
    var defaultEquipment: Set<EquipmentType> {
        switch self {
        case .commercial: Set(EquipmentType.allCases)
        case .homeDumbbells: [.dumbbell, .bench, .bodyweight, .pullUpBar]
        case .hotel: [.dumbbell, .machine, .cable, .bench, .bodyweight]
        case .bodyweightOnly: [.bodyweight, .pullUpBar]
        case .custom: []
        }
    }
}

/// A gym the user trains at, described by the equipment on hand. Exactly
/// one profile is active at a time (enforced by GymProfileService); the
/// active profile drives exercise availability filtering.
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
