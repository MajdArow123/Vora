//
//  WeightField.swift
//  Vora
//
//  Created by Majd Arow on 2026-11-02.
//

import Foundation

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

    /// `kg` when it's a plausible body weight, otherwise nil.
    var bodyWeightKg: Double? {
        guard let kg, UnitConversion.bodyWeightRangeKg.contains(kg) else { return nil }
        return kg
    }
}
