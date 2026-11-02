//
//  GymProfile.swift
//  Vora
//
//  Created by Majd Arow on 2026-08-10.
//

import Foundation
import SwiftData

nonisolated enum GymPreset: String, Codable, CaseIterable, Identifiable {
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
    /// Nil until the user's units are known (see GymInventoryBackfill).
    /// Once written, these change only when the user edits them: a later
    /// switch of `preferredUnits` affects display, never the gym's plates.
    private var storedBars: [GymBar]?
    private var storedPlates: [PlateStock]?
    private var storedDumbbellIncrementKg: Double?
    private var storedMachineIncrementKg: Double?

    var availableEquipment: Set<EquipmentType> {
        get { Set(equipmentRawValues.compactMap(EquipmentType.init(rawValue:))) }
        set { equipmentRawValues = newValue.map(\.rawValue).sorted() }
    }

    /// The gym's loading inventory, or nil if it hasn't been filled yet.
    var loadingInventory: LoadingInventory? {
        guard let storedBars, let storedPlates,
              let storedDumbbellIncrementKg, let storedMachineIncrementKg
        else { return nil }
        return LoadingInventory(
            bars: storedBars,
            plates: storedPlates,
            dumbbellIncrementKg: storedDumbbellIncrementKg,
            machineIncrementKg: storedMachineIncrementKg
        )
    }

    /// Pass `inventoryUnits` when the user's units are known; without them
    /// the inventory stays nil until the backfill or onboarding fills it.
    init(
        name: String,
        preset: GymPreset,
        availableEquipment: Set<EquipmentType>? = nil,
        isActive: Bool = false,
        createdAt: Date = .now,
        inventoryUnits: UnitSystem? = nil
    ) {
        self.name = name
        self.preset = preset
        self.equipmentRawValues = (availableEquipment ?? preset.defaultEquipment)
            .map(\.rawValue)
            .sorted()
        self.isActive = isActive
        self.createdAt = createdAt
        if let inventoryUnits {
            updateInventory(preset.defaultInventory(units: inventoryUnits, equipment: self.availableEquipment))
        }
    }

    /// Applies a preset, replacing the equipment and inventory with the
    /// preset's defaults as a starting point for further edits. Custom keeps
    /// both, as it is what a profile becomes once hand-edited.
    func applyPreset(_ newPreset: GymPreset, units: UnitSystem) {
        preset = newPreset
        if newPreset == .custom {
            fillInventoryIfNeeded(units: units)
        } else {
            availableEquipment = newPreset.defaultEquipment
            updateInventory(newPreset.defaultInventory(units: units, equipment: availableEquipment))
        }
    }

    func updateInventory(_ inventory: LoadingInventory) {
        storedBars = inventory.bars
        storedPlates = inventory.plates
        storedDumbbellIncrementKg = inventory.dumbbellIncrementKg
        storedMachineIncrementKg = inventory.machineIncrementKg
    }

    /// Writes the preset's defaults into whichever fields are still nil.
    /// Returns whether anything was written.
    @discardableResult
    func fillInventoryIfNeeded(units: UnitSystem) -> Bool {
        guard loadingInventory == nil else { return false }
        let defaults = preset.defaultInventory(units: units, equipment: availableEquipment)
        storedBars = storedBars ?? defaults.bars
        storedPlates = storedPlates ?? defaults.plates
        storedDumbbellIncrementKg = storedDumbbellIncrementKg ?? defaults.dumbbellIncrementKg
        storedMachineIncrementKg = storedMachineIncrementKg ?? defaults.machineIncrementKg
        return true
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
