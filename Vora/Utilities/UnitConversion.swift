//
//  UnitConversion.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import Foundation

enum UnitConversion {
    static let cmPerInch = 2.54
    nonisolated static let poundsPerKg = 2.20462

    static func pounds(fromKg kg: Double) -> Double {
        kg * poundsPerKg
    }

    nonisolated static func kg(fromPounds pounds: Double) -> Double {
        pounds / poundsPerKg
    }

    static func feetAndInches(fromCm cm: Double) -> (feet: Int, inches: Int) {
        let totalInches = Int((cm / cmPerInch).rounded())
        return (totalInches / 12, totalInches % 12)
    }

    static func cm(fromFeet feet: Int, inches: Int) -> Double {
        Double(feet * 12 + inches) * cmPerInch
    }

    static func inches(fromCm cm: Double) -> Double {
        cm / cmPerInch
    }

    static func cm(fromInches inches: Double) -> Double {
        inches * cmPerInch
    }

    /// Body-measurement length with one decimal, e.g. "82.5 cm" / "32.5 in".
    static func lengthText(cm: Double, units: UnitSystem) -> String {
        switch units {
        case .metric:
            return String(format: "%.1f cm", cm)
        case .imperial:
            return String(format: "%.1f in", inches(fromCm: cm))
        }
    }

    static func heightText(cm: Double, units: UnitSystem) -> String {
        switch units {
        case .metric:
            return "\(Int(cm.rounded())) cm"
        case .imperial:
            let (feet, inches) = feetAndInches(fromCm: cm)
            return "\(feet) ft \(inches) in"
        }
    }

    // MARK: - Lifted weight

    /// A lifted weight in the user's unit, unrounded so lb input converts
    /// to kg and back without drift.
    static func displayWeight(kg: Double, units: UnitSystem) -> Double {
        switch units {
        case .metric: kg
        case .imperial: pounds(fromKg: kg)
        }
    }

    static func kg(fromDisplayWeight value: Double, units: UnitSystem) -> Double {
        switch units {
        case .metric: value
        case .imperial: kg(fromPounds: value)
        }
    }

    /// Parses typed weight in the user's unit (dot or comma decimal) and
    /// returns kilograms; nil for blank or non-numeric input.
    static func parseWeight(_ text: String, units: UnitSystem) -> Double? {
        let normalized = text
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value.isFinite else { return nil }
        return kg(fromDisplayWeight: value, units: units)
    }

    /// The number alone in the user's unit, up to two decimals with
    /// trailing zeros trimmed: "82.5", "102.25", "225".
    static func weightNumberText(kg: Double, units: UnitSystem) -> String {
        displayWeight(kg: kg, units: units).formatted(weightNumberStyle)
    }

    /// Lifted weight with its unit, e.g. "82.5 kg" / "225 lb".
    static func liftWeightText(kg: Double, units: UnitSystem) -> String {
        "\(weightNumberText(kg: kg, units: units)) \(weightUnitSymbol(units))"
    }

    /// Training volume rounded to a whole number, e.g. "4520 kg".
    static func volumeText(kg: Double, units: UnitSystem) -> String {
        "\(Int(displayWeight(kg: kg, units: units).rounded())) \(weightUnitSymbol(units))"
    }

    static func weightUnitSymbol(_ units: UnitSystem) -> String {
        switch units {
        case .metric: "kg"
        case .imperial: "lb"
        }
    }

    /// Unit name for VoiceOver, e.g. "kilograms".
    static func spokenWeightUnit(_ units: UnitSystem) -> String {
        switch units {
        case .metric: "kilograms"
        case .imperial: "pounds"
        }
    }

    private static let weightNumberStyle = FloatingPointFormatStyle<Double>(locale: Locale(identifier: "en_US_POSIX"))
        .precision(.fractionLength(0...2))
        .rounded(rule: .toNearestOrAwayFromZero)
        .grouping(.never)

    // MARK: - Body weight

    static func weightText(kg: Double, units: UnitSystem) -> String {
        switch units {
        case .metric:
            return "\(Int(kg.rounded())) kg"
        case .imperial:
            return "\(Int(pounds(fromKg: kg).rounded())) lb"
        }
    }
}
