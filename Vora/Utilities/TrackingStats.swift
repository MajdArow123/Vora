//
//  TrackingStats.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import Foundation
import SwiftData

enum TrackingStats {
    /// Number of distinct calendar days with at least one logged food,
    /// water, weight, or workout entry.
    static func daysTracked(in context: ModelContext, calendar: Calendar = .current) -> Int {
        var days = Set<Date>()

        func collect<T: PersistentModel>(_ type: T.Type, _ date: (T) -> Date) {
            var descriptor = FetchDescriptor<T>()
            descriptor.propertiesToFetch = []
            let items = (try? context.fetch(descriptor)) ?? []
            for item in items {
                days.insert(calendar.startOfDay(for: date(item)))
            }
        }

        collect(FoodEntry.self) { $0.date }
        collect(WaterEntry.self) { $0.date }
        collect(WeightEntry.self) { $0.date }
        collect(WorkoutSession.self) { $0.date }
        return days.count
    }
}
