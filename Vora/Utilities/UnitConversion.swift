//
//  UnitConversion.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import Foundation

enum UnitConversion {
    static let cmPerInch = 2.54
    static let poundsPerKg = 2.20462

    static func pounds(fromKg kg: Double) -> Double {
        kg * poundsPerKg
    }

    static func kg(fromPounds pounds: Double) -> Double {
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

    static func weightText(kg: Double, units: UnitSystem) -> String {
        switch units {
        case .metric:
            return "\(Int(kg.rounded())) kg"
        case .imperial:
            return "\(Int(pounds(fromKg: kg).rounded())) lb"
        }
    }
}
