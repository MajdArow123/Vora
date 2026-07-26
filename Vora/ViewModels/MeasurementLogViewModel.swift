//
//  MeasurementLogViewModel.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-26.
//

import Foundation
import Observation
import SwiftData

@Observable
final class MeasurementLogViewModel {
    var texts: [MeasurementField: String] = [:]
    var notes = ""
    private(set) var units: UnitSystem = .metric

    func load(from context: ModelContext) {
        units = (try? context.fetch(FetchDescriptor<UserProfile>()).first)?.preferredUnits ?? .metric
    }

    /// Parsed value in storage units (cm for lengths, raw for percent),
    /// nil when empty, unparseable, or out of range. Imperial length
    /// input is interpreted as inches.
    func parsedValue(for field: MeasurementField) -> Double? {
        let raw = (texts[field] ?? "")
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(raw) else { return nil }
        if field.isPercent {
            return (2...80).contains(value) ? value : nil
        }
        let cm = units == .imperial ? UnitConversion.cm(fromInches: value) : value
        return (5...300).contains(cm) ? cm : nil
    }

    /// Non-empty but unparseable or out of range.
    func fieldIsInvalid(_ field: MeasurementField) -> Bool {
        let raw = (texts[field] ?? "").trimmingCharacters(in: .whitespaces)
        return !raw.isEmpty && parsedValue(for: field) == nil
    }

    var hasAnyValue: Bool {
        MeasurementField.allCases.contains { parsedValue(for: $0) != nil }
    }

    var canSave: Bool {
        hasAnyValue && !MeasurementField.allCases.contains { fieldIsInvalid($0) }
    }

    func save(in context: ModelContext) {
        let measurement = BodyMeasurement(date: .now)
        for field in MeasurementField.allCases {
            measurement[keyPath: field.keyPath] = parsedValue(for: field)
        }
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        measurement.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
        context.insert(measurement)
        try? context.save()
    }
}
