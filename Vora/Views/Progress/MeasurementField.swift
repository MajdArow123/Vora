//
//  MeasurementField.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-26.
//

import Foundation

/// The loggable body-measurement fields, driving the log form,
/// summary rows, and detail view from one source of truth.
enum MeasurementField: String, CaseIterable, Identifiable {
    case waist
    case hips
    case chest
    case leftArm
    case rightArm
    case leftThigh
    case rightThigh
    case neck
    case bodyFat

    var id: String { rawValue }

    static let generalTip = "For best accuracy: measure at the same time each week, preferably in the morning before eating. Use a flexible tape measure and measure twice to confirm."

    var label: String {
        switch self {
        case .waist: "Waist"
        case .hips: "Hips"
        case .chest: "Chest"
        case .leftArm: "Left arm"
        case .rightArm: "Right arm"
        case .leftThigh: "Left thigh"
        case .rightThigh: "Right thigh"
        case .neck: "Neck"
        case .bodyFat: "Body fat"
        }
    }

    var isPercent: Bool { self == .bodyFat }

    var keyPath: ReferenceWritableKeyPath<BodyMeasurement, Double?> {
        switch self {
        case .waist: \.waistCm
        case .hips: \.hipsCm
        case .chest: \.chestCm
        case .leftArm: \.leftArmCm
        case .rightArm: \.rightArmCm
        case .leftThigh: \.leftThighCm
        case .rightThigh: \.rightThighCm
        case .neck: \.neckCm
        case .bodyFat: \.bodyFatPercent
        }
    }

    var instruction: String {
        switch self {
        case .waist:
            "Measure at the narrowest point of your torso, usually just above your belly button. Stand relaxed, exhale naturally, and measure after exhaling. Do not suck in your stomach. Keep the tape horizontal and snug but not tight."
        case .hips:
            "Measure at the widest point of your hips and glutes, usually about 8 inches below your natural waist. Stand with feet together. Keep the tape horizontal all the way around."
        case .chest:
            "Measure at the fullest part of your chest, directly across your nipple line. Keep your arms relaxed at your sides. Breathe normally and measure after a normal exhale. Keep the tape horizontal."
        case .leftArm, .rightArm:
            "Measure at the midpoint between your shoulder and elbow (the widest part of your bicep). Measure with your arm relaxed at your side, not flexed. Keep the tape horizontal and snug."
        case .leftThigh, .rightThigh:
            "Measure at the midpoint between your hip and knee — usually about 6 inches above the knee. Stand with feet slightly apart and weight evenly distributed. Keep the tape horizontal."
        case .neck:
            "Measure just below your Adam's apple (larynx) at the narrowest part of your neck. Keep your head level and looking straight ahead. The tape should be snug but not tight."
        case .bodyFat:
            "This is an estimate from a body fat scale or calipers. For consistency, always measure at the same time of day — ideally morning before eating or drinking. Results vary by method and conditions."
        }
    }

    func unitLabel(for units: UnitSystem) -> String {
        if isPercent { return "%" }
        return units == .metric ? "cm" : "in"
    }

    /// Display text for a stored value (lengths stored in cm).
    func displayText(_ value: Double, units: UnitSystem) -> String {
        if isPercent { return String(format: "%.1f%%", value) }
        return UnitConversion.lengthText(cm: value, units: units)
    }

    /// The fields recorded on a measurement, in canonical order.
    static func recordedValues(_ measurement: BodyMeasurement) -> [(field: MeasurementField, value: Double)] {
        allCases.compactMap { field in
            guard let value = measurement[keyPath: field.keyPath] else { return nil }
            if field.isPercent && value <= 0 { return nil }
            return (field, value)
        }
    }

    /// "Waist 82.5 cm · Hips 96.0 cm · +2 more" — recorded fields only.
    static func summary(for measurement: BodyMeasurement, units: UnitSystem, limit: Int? = nil) -> String {
        let recorded = recordedValues(measurement)
        let shown = limit.map { Array(recorded.prefix($0)) } ?? recorded
        var parts = shown.map { "\($0.field.label) \($0.field.displayText($0.value, units: units))" }
        if let limit, recorded.count > limit {
            parts.append("+\(recorded.count - limit) more")
        }
        return parts.joined(separator: " · ")
    }
}
