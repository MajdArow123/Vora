//
//  LoadingInventoryDraft.swift
//  Vora
//
//  Created by Majd Arow on 2026-11-02.
//

import Foundation

/// Editable text form of a `LoadingInventory`, in the user's display unit.
struct LoadingInventoryDraft: Equatable {
    /// A typed weight. Holds the exact kg behind untouched text, so a 25 kg
    /// plate shown as 55.12 lb still saves as 25 kg.
    struct WeightField: Equatable {
        var text: String
        private let source: Source?
        private let units: UnitSystem

        private struct Source: Equatable {
            let text: String
            let kg: Double
        }

        init(kg: Double?, units: UnitSystem) {
            self.units = units
            if let kg {
                let text = UnitConversion.weightNumberText(kg: kg, units: units)
                self.text = text
                self.source = Source(text: text, kg: kg)
            } else {
                self.text = ""
                self.source = nil
            }
        }

        /// Nil unless the field holds a positive weight.
        var kg: Double? {
            if let source, source.text == text { return source.kg }
            guard let parsed = UnitConversion.parseWeight(text, units: units), parsed > 0 else { return nil }
            return parsed
        }

        /// Like `kg`, but also accepts 0.
        var kgAllowingZero: Double? {
            if let source, source.text == text { return source.kg }
            guard let parsed = UnitConversion.parseWeight(text, units: units), parsed >= 0 else { return nil }
            return parsed
        }
    }

    struct BarRow: Identifiable, Equatable {
        let id: UUID
        var name: String
        var weight: WeightField
        let kind: BarKind

        init(id: UUID = UUID(), name: String, weight: WeightField, kind: BarKind = .free) {
            self.id = id
            self.name = name
            self.weight = weight
            self.kind = kind
        }

        var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

        var bar: GymBar? {
            let kg = kind == .smith ? weight.kgAllowingZero : weight.kg
            guard !trimmedName.isEmpty, let kg else { return nil }
            return GymBar(name: trimmedName, weightKg: kg, kind: kind)
        }

        func isShown(for equipment: Set<EquipmentType>) -> Bool {
            switch kind {
            case .free: equipment.contains(.barbell)
            case .smith: equipment.contains(.smithMachine)
            }
        }
    }

    struct PlateRow: Identifiable, Equatable {
        let id: UUID
        var weight: WeightField
        var pairCount: Int

        init(id: UUID = UUID(), weight: WeightField, pairCount: Int) {
            self.id = id
            self.weight = weight
            self.pairCount = pairCount
        }

        var plate: PlateStock? {
            guard let kg = weight.kg, Self.pairRange.contains(pairCount) else { return nil }
            return PlateStock(weightKg: kg, pairCount: pairCount)
        }

        static let pairRange = 1...20
    }

    let units: UnitSystem
    var bars: [BarRow]
    var plates: [PlateRow]
    var dumbbellIncrement: WeightField
    var machineIncrement: WeightField
    private let original: LoadingInventory

    init(inventory: LoadingInventory, units: UnitSystem) {
        self.units = units
        self.original = inventory
        self.bars = inventory.bars.map {
            BarRow(name: $0.name, weight: WeightField(kg: $0.weightKg, units: units), kind: $0.kind)
        }
        self.plates = inventory.plates.map {
            PlateRow(weight: WeightField(kg: $0.weightKg, units: units), pairCount: $0.pairCount)
        }
        self.dumbbellIncrement = WeightField(kg: inventory.dumbbellIncrementKg, units: units)
        self.machineIncrement = WeightField(kg: inventory.machineIncrementKg, units: units)
    }

    /// Free bars can be added and removed only with a barbell.
    static func showsFreeBarActions(for equipment: Set<EquipmentType>) -> Bool {
        equipment.contains(.barbell)
    }

    static func showsBarsAndPlates(for equipment: Set<EquipmentType>) -> Bool {
        !equipment.isDisjoint(with: [.barbell, .smithMachine])
    }

    static func showsDumbbellStep(for equipment: Set<EquipmentType>) -> Bool {
        equipment.contains(.dumbbell)
    }

    static func showsMachineStep(for equipment: Set<EquipmentType>) -> Bool {
        !equipment.isDisjoint(with: [.machine, .cable])
    }

    /// The inventory to save, or nil while a section the user can see has an
    /// invalid value. Hidden sections can't block saving: their invalid rows
    /// are dropped and their invalid steps keep the original value. A Smith
    /// bar is only ever saved for a gym with a Smith machine.
    func inventory(for equipment: Set<EquipmentType>) -> LoadingInventory? {
        let validBars = bars
            .filter { $0.kind != .smith || equipment.contains(.smithMachine) }
            .compactMap(\.bar)
        let validPlates = plates.compactMap(\.plate)

        guard bars.allSatisfy({ !$0.isShown(for: equipment) || $0.bar != nil }) else { return nil }
        if Self.showsBarsAndPlates(for: equipment), validPlates.count != plates.count { return nil }
        if Self.showsDumbbellStep(for: equipment), dumbbellIncrement.kg == nil { return nil }
        if Self.showsMachineStep(for: equipment), machineIncrement.kg == nil { return nil }

        return LoadingInventory(
            bars: validBars,
            plates: validPlates,
            dumbbellIncrementKg: dumbbellIncrement.kg ?? original.dumbbellIncrementKg,
            machineIncrementKg: machineIncrement.kg ?? original.machineIncrementKg
        )
    }

    /// A gym gaining a barbell with nothing to load gets the standard bars
    /// and plates. Anything the user has already entered stays.
    mutating func seedBarbellIfEmpty() {
        let standard = LoadingInventoryDraft(inventory: .standard(units: units), units: units)
        if !bars.contains(where: { $0.kind == .free }) {
            bars.insert(contentsOf: standard.bars, at: 0)
        }
        seedPlatesIfEmpty(from: standard)
    }

    /// A gym gaining a Smith machine gets a default Smith bar, and standard
    /// plates if it has none. Anything the user has already entered stays.
    mutating func seedSmithIfMissing() {
        if !bars.contains(where: { $0.kind == .smith }) {
            let bar = LoadingInventory.smithBar(units: units)
            bars.append(BarRow(
                name: bar.name,
                weight: WeightField(kg: bar.weightKg, units: units),
                kind: .smith
            ))
        }
        seedPlatesIfEmpty(from: LoadingInventoryDraft(inventory: .standard(units: units), units: units))
    }

    private mutating func seedPlatesIfEmpty(from standard: LoadingInventoryDraft) {
        if plates.isEmpty {
            plates = standard.plates
        }
    }

    mutating func addBar() {
        bars.append(BarRow(name: "", weight: WeightField(kg: nil, units: units)))
    }

    mutating func addPlate() {
        plates.append(PlateRow(weight: WeightField(kg: nil, units: units), pairCount: 1))
    }
}
