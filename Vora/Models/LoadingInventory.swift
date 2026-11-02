//
//  LoadingInventory.swift
//  Vora
//
//  Created by Majd Arow on 2026-11-02.
//

import Foundation

/// What a bar belongs to. Raw values are persisted and never change.
nonisolated enum BarKind: String, Codable {
    case free
    /// A Smith machine's bar. Its weight can be 0 when counterbalanced.
    case smith
}

/// A bar a gym has. Persisted inside GymProfile; field names never change.
nonisolated struct GymBar: Codable, Hashable {
    var name: String
    var weightKg: Double
    var kind: BarKind = .free
}

/// Plates of one weight. A pair loads one plate on each side of the bar.
/// Persisted inside GymProfile; field names never change.
nonisolated struct PlateStock: Codable, Hashable {
    var weightKg: Double
    var pairCount: Int
}

/// What a gym can load, as plain values. All weights are in kg, including
/// lb plates, whose exact kg value comes from `UnitConversion`.
nonisolated struct LoadingInventory: Equatable {
    var bars: [GymBar]
    var plates: [PlateStock]
    var dumbbellIncrementKg: Double
    var machineIncrementKg: Double

    /// A fully equipped gym's bars, plates and steps in the given unit.
    static func standard(units: UnitSystem) -> LoadingInventory {
        switch units {
        case .metric:
            LoadingInventory(
                bars: [
                    GymBar(name: "Olympic Bar", weightKg: 20),
                    GymBar(name: "Women's Bar", weightKg: 15),
                    GymBar(name: "EZ Bar", weightKg: 10),
                ],
                plates: [
                    PlateStock(weightKg: 25, pairCount: 8),
                    PlateStock(weightKg: 20, pairCount: 2),
                    PlateStock(weightKg: 15, pairCount: 2),
                    PlateStock(weightKg: 10, pairCount: 2),
                    PlateStock(weightKg: 5, pairCount: 2),
                    PlateStock(weightKg: 2.5, pairCount: 2),
                    PlateStock(weightKg: 1.25, pairCount: 2),
                ],
                dumbbellIncrementKg: 2.5,
                machineIncrementKg: 5
            )
        case .imperial:
            LoadingInventory(
                bars: [
                    GymBar(name: "Olympic Bar", weightKg: UnitConversion.kg(fromPounds: 45)),
                    GymBar(name: "Women's Bar", weightKg: UnitConversion.kg(fromPounds: 35)),
                    GymBar(name: "EZ Bar", weightKg: UnitConversion.kg(fromPounds: 25)),
                ],
                plates: [
                    PlateStock(weightKg: UnitConversion.kg(fromPounds: 45), pairCount: 8),
                    PlateStock(weightKg: UnitConversion.kg(fromPounds: 35), pairCount: 2),
                    PlateStock(weightKg: UnitConversion.kg(fromPounds: 25), pairCount: 2),
                    PlateStock(weightKg: UnitConversion.kg(fromPounds: 10), pairCount: 2),
                    PlateStock(weightKg: UnitConversion.kg(fromPounds: 5), pairCount: 2),
                    PlateStock(weightKg: UnitConversion.kg(fromPounds: 2.5), pairCount: 2),
                ],
                dumbbellIncrementKg: UnitConversion.kg(fromPounds: 5),
                machineIncrementKg: UnitConversion.kg(fromPounds: 10)
            )
        }
    }

    /// The same steps with no bars or plates, for gyms without a barbell.
    static func withoutBarbell(units: UnitSystem) -> LoadingInventory {
        var inventory = standard(units: units)
        inventory.bars = []
        inventory.plates = []
        return inventory
    }

    static func smithBar(units: UnitSystem) -> GymBar {
        switch units {
        case .metric: GymBar(name: "Smith bar", weightKg: 15, kind: .smith)
        case .imperial: GymBar(name: "Smith bar", weightKg: UnitConversion.kg(fromPounds: 35), kind: .smith)
        }
    }

    /// The equipment a plate calculator loads for an exercise needing this
    /// equipment; nil if it isn't plate-loaded.
    static func plateLoadedEquipment(in equipment: Set<EquipmentType>) -> EquipmentType? {
        if equipment.contains(.barbell) { return .barbell }
        if equipment.contains(.smithMachine) { return .smithMachine }
        return nil
    }

    /// The bars that can load this equipment.
    func bars(for equipment: EquipmentType) -> [GymBar] {
        switch equipment {
        case .barbell: bars.filter { $0.kind == .free }
        case .smithMachine: bars.filter { $0.kind == .smith }
        default: []
        }
    }

    /// Adds a default Smith bar when the equipment has a Smith machine and
    /// this inventory has no Smith bar yet.
    func addingSmithBar(ifIn equipment: Set<EquipmentType>, units: UnitSystem) -> LoadingInventory {
        guard equipment.contains(.smithMachine), bars(for: .smithMachine).isEmpty else { return self }
        var inventory = self
        inventory.bars.append(Self.smithBar(units: units))
        return inventory
    }
}

nonisolated extension GymPreset {
    /// What a preset writes into a gym with this equipment. Custom matches
    /// commercial, so a gym that gains a barbell by hand still has something
    /// to load. Only a gym with a Smith machine gets a Smith bar.
    func defaultInventory(units: UnitSystem, equipment: Set<EquipmentType>) -> LoadingInventory {
        let base: LoadingInventory = switch self {
        case .commercial, .custom: .standard(units: units)
        case .homeDumbbells, .hotel, .bodyweightOnly: .withoutBarbell(units: units)
        }
        return base.addingSmithBar(ifIn: equipment, units: units)
    }
}
