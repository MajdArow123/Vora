//
//  WeightImportService.swift
//  Vora
//
//  Created by Majd Arow on 2026-11-02.
//

import Foundation
import OSLog
import SwiftData

/// Copies smart-scale weigh-ins from HealthKit into `WeightEntry`, read-only
/// on the HealthKit side. An imported entry takes its sample's UUID as its
/// `id`, which is what makes a re-import a no-op without a source field.
struct WeightImportService {
    /// A per-device preference, off until the user turns it on.
    static let enabledKey = "vora.importHealthWeight"
    private static let fullHistoryImportedKey = "vora.importHealthWeight.fullHistoryImported"

    /// After the first import, later ones re-read this many days.
    static let trailingDays = 30
    /// A reading this close on the same day is the same weigh-in, allowing
    /// for a hand-typed value or another app's rounding.
    static let sameWeighInToleranceKg = 0.25

    private static let logger = Logger(subsystem: "com.majdarow.Vora", category: "WeightImport")

    private let reader: any HealthBodyMassReading
    private let defaults: UserDefaults

    init(reader: any HealthBodyMassReading = HealthKitService(), defaults: UserDefaults = .standard) {
        self.reader = reader
        self.defaults = defaults
    }

    /// Imports new samples and returns how many. Failures are logged and
    /// import nothing: the app works the same without them.
    @discardableResult
    func sync(context: ModelContext, now: Date = .now, calendar: Calendar = .current) async -> Int {
        guard defaults.bool(forKey: Self.enabledKey) else {
            // Turning it back on reads full history again, covering the gap.
            defaults.removeObject(forKey: Self.fullHistoryImportedKey)
            return 0
        }

        let since = defaults.bool(forKey: Self.fullHistoryImportedKey)
            ? calendar.date(byAdding: .day, value: -Self.trailingDays, to: calendar.startOfDay(for: now))
            : nil

        let samples: [HealthBodyMassSample]
        let existing: [WeightEntry]
        do {
            samples = try await reader.bodyMassSamples(since: since)
            existing = try context.fetch(FetchDescriptor<WeightEntry>())
        } catch {
            // HealthKit also refuses reads while the device is locked.
            Self.logger.error("Weight import read failed: \(String(describing: error), privacy: .public)")
            return 0
        }

        let imports = Self.samplesToImport(
            samples,
            existing: existing.map { HealthBodyMassSample(id: $0.id, date: $0.date, kg: $0.weightKg) },
            calendar: calendar
        )
        for sample in imports {
            context.insert(WeightEntry(id: sample.id, date: sample.date, weightKg: sample.kg))
        }
        do {
            try context.save()
        } catch {
            Self.logger.error("Weight import save failed: \(String(describing: error), privacy: .public)")
            context.rollback()
            return 0
        }

        // A denied read also returns nothing, so an empty result stays
        // eligible for a full read once access is granted.
        if !samples.isEmpty {
            defaults.set(true, forKey: Self.fullHistoryImportedKey)
        }
        return imports.count
    }

    /// Drops samples already stored, implausible weights, and any that repeat
    /// a same-day weigh-in, whether it's a Vora entry or an earlier sample.
    static func samplesToImport(
        _ samples: [HealthBodyMassSample],
        existing: [HealthBodyMassSample],
        calendar: Calendar
    ) -> [HealthBodyMassSample] {
        var knownIDs = Set(existing.map(\.id))
        var weightsByDay = Dictionary(grouping: existing) { calendar.startOfDay(for: $0.date) }
            .mapValues { $0.map(\.kg) }

        return samples.filter { sample in
            guard knownIDs.insert(sample.id).inserted,
                  UnitConversion.bodyWeightRangeKg.contains(sample.kg)
            else { return false }

            let day = calendar.startOfDay(for: sample.date)
            let sameWeighIn = weightsByDay[day, default: []].contains {
                abs($0 - sample.kg) <= sameWeighInToleranceKg
            }
            guard !sameWeighIn else { return false }

            weightsByDay[day, default: []].append(sample.kg)
            return true
        }
    }
}
