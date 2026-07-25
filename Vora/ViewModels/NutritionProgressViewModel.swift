//
//  NutritionProgressViewModel.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-25.
//

import Foundation
import Observation
import SwiftData

struct DailyNutritionPoint: Identifiable {
    let day: Date
    let calories: Double
    let proteinG: Double

    var id: Date { day }
}

@Observable
final class NutritionProgressViewModel {
    private(set) var dailyPoints: [DailyNutritionPoint] = []
    private(set) var calorieTarget = 0
    private(set) var proteinTarget = 0

    var selectedRange: ChartRange = .month

    private var allEntries: [FoodEntry] = []

    // MARK: - Loading

    func load(from context: ModelContext, now: Date = .now) {
        let profile = try? context.fetch(FetchDescriptor<UserProfile>()).first
        calorieTarget = profile?.dailyCalorieTarget ?? 0
        proteinTarget = profile?.proteinTargetG ?? 0

        allEntries = (try? context.fetch(FetchDescriptor<FoodEntry>(
            sortBy: [SortDescriptor(\.date)]
        ))) ?? []
        recompute(now: now)
    }

    func rangeChanged(now: Date = .now) {
        recompute(now: now)
    }

    private func recompute(now: Date) {
        dailyPoints = Self.dailyTotals(entries: allEntries, range: selectedRange, now: now)
    }

    // MARK: - Aggregation

    /// Daily calorie and protein totals within the range, oldest first.
    /// Days with no entries are omitted rather than shown as zero,
    /// consistent with the weekly-averages philosophy.
    static func dailyTotals(
        entries: [FoodEntry],
        range: ChartRange,
        now: Date,
        calendar: Calendar = .current
    ) -> [DailyNutritionPoint] {
        let cutoff = StrengthProgressViewModel.cutoff(for: range, now: now, calendar: calendar)
        var byDay: [Date: (kcal: Double, protein: Double)] = [:]

        for entry in entries {
            if let cutoff, entry.date < cutoff { continue }
            let day = calendar.startOfDay(for: entry.date)
            var totals = byDay[day] ?? (0, 0)
            totals.kcal += entry.calories
            totals.protein += entry.proteinG
            byDay[day] = totals
        }

        return byDay
            .map { DailyNutritionPoint(day: $0.key, calories: $0.value.kcal, proteinG: $0.value.protein) }
            .sorted { $0.day < $1.day }
    }
}
