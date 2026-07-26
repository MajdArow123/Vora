//
//  ProgressViewModel.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import Foundation
import Observation
import SwiftData

enum ChartRange: String, CaseIterable, Identifiable {
    case month = "1M"
    case quarter = "3M"
    case halfYear = "6M"
    case all = "All"

    var id: String { rawValue }

    var days: Int? {
        switch self {
        case .month: 30
        case .quarter: 90
        case .halfYear: 180
        case .all: nil
        }
    }
}

/// A dated scalar sample for secondary trend charts (body fat, waist).
struct MetricPoint: Identifiable {
    let id: UUID
    let date: Date
    let value: Double
}

struct WeeklyAverage: Identifiable {
    let label: String
    let average: Double
    let target: Int
    let unit: String

    var id: String { label }
}

@Observable
final class ProgressViewModel {
    private(set) var profile: UserProfile?
    /// Weigh-ins within the selected range, oldest first.
    private(set) var rangeWeights: [WeightEntry] = []
    /// All weigh-ins newest first, for the log list.
    private(set) var allWeightsDescending: [WeightEntry] = []
    /// All body measurements newest first.
    private(set) var allMeasurementsDescending: [BodyMeasurement] = []
    private(set) var weekDots: [Bool] = []
    private(set) var streakDays = 0
    private(set) var daysTracked = 0
    private(set) var weeklyAverages: [WeeklyAverage] = []
    private(set) var hasActiveSupplements = false
    private(set) var supplementStreakDays = 0
    /// All-supplements-taken flags for the trailing 7 days, oldest first.
    private(set) var supplementWeekDots: [Bool] = []
    /// Percentage of days this month on which every supplement was taken.
    private(set) var supplementMonthPercent = 0

    var selectedRange: ChartRange = .month

    // MARK: - Loading

    func load(from context: ModelContext, now: Date = .now) {
        let cal = Calendar.current
        profile = try? context.fetch(FetchDescriptor<UserProfile>()).first

        allWeightsDescending = (try? context.fetch(FetchDescriptor<WeightEntry>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        ))) ?? []
        fetchMeasurements(from: context)
        applyRange(now: now, calendar: cal)

        loadTraining(from: context, now: now, calendar: cal)
        loadWeeklyAverages(from: context, now: now, calendar: cal)
        loadSupplements(from: context, now: now, calendar: cal)
        daysTracked = TrackingStats.daysTracked(in: context, calendar: cal)
    }

    func rangeChanged(now: Date = .now) {
        applyRange(now: now, calendar: .current)
    }

    private func applyRange(now: Date, calendar: Calendar) {
        guard let days = selectedRange.days,
              let cutoff = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: now))
        else {
            rangeWeights = allWeightsDescending.reversed()
            return
        }
        rangeWeights = allWeightsDescending.filter { $0.date >= cutoff }.reversed()
    }

    private func loadTraining(from context: ModelContext, now: Date, calendar: Calendar) {
        guard let windowStart = calendar.date(byAdding: .day, value: -40, to: calendar.startOfDay(for: now))
        else { return }
        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.date >= windowStart }
        )
        let dates = ((try? context.fetch(descriptor)) ?? []).map(\.date)

        weekDots = StreakCalculator.trailingWeek(sessionDates: dates, today: now, calendar: calendar)
        let restIndices = Set(
            ((try? context.fetch(FetchDescriptor<SplitDay>())) ?? [])
                .filter(\.isRest)
                .map(\.dayIndex)
        )
        streakDays = StreakCalculator.adherenceStreak(
            sessionDates: dates,
            restDayIndices: restIndices,
            today: now,
            calendar: calendar
        )
    }

    private func loadSupplements(from context: ModelContext, now: Date, calendar: Calendar) {
        let supplementDescriptor = FetchDescriptor<Supplement>(
            predicate: #Predicate { $0.isActive }
        )
        let active = (try? context.fetch(supplementDescriptor)) ?? []
        hasActiveSupplements = !active.isEmpty
        guard hasActiveSupplements else {
            supplementStreakDays = 0
            supplementWeekDots = []
            supplementMonthPercent = 0
            return
        }

        let todayStart = calendar.startOfDay(for: now)
        // Cover both the 40-day streak window and the whole current month.
        let monthStart = calendar.dateInterval(of: .month, for: now)?.start ?? todayStart
        let streakStart = calendar.date(byAdding: .day, value: -40, to: todayStart) ?? todayStart
        let windowStart = min(monthStart, streakStart)
        guard let todayEnd = calendar.date(byAdding: .day, value: 1, to: todayStart) else { return }

        let logDescriptor = FetchDescriptor<SupplementLog>(
            predicate: #Predicate { $0.date >= windowStart && $0.date < todayEnd }
        )
        let logs = (try? context.fetch(logDescriptor)) ?? []

        let qualifying = StreakCalculator.qualifyingSupplementDays(
            logs: logs.map { (supplementID: $0.supplementID, date: $0.date) },
            activeSupplements: active.map { (id: $0.id, createdAt: $0.createdAt) },
            calendar: calendar
        )
        supplementStreakDays = StreakCalculator.foodStreak(qualifyingDays: qualifying, today: now, calendar: calendar)
        supplementWeekDots = StreakCalculator.trailingWeek(sessionDates: Array(qualifying), today: now, calendar: calendar)
        supplementMonthPercent = StreakCalculator.monthlyConsistency(
            qualifyingDays: qualifying,
            earliestCreatedAt: active.map(\.createdAt).min(),
            today: now,
            calendar: calendar
        )
    }

    /// Averages over the trailing 7 days, counting only days that have
    /// at least one food entry so untracked days do not drag values down.
    private func loadWeeklyAverages(from context: ModelContext, now: Date, calendar: Calendar) {
        let todayStart = calendar.startOfDay(for: now)
        guard let weekAgo = calendar.date(byAdding: .day, value: -6, to: todayStart),
              let todayEnd = calendar.date(byAdding: .day, value: 1, to: todayStart)
        else { return }

        let descriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate { $0.date >= weekAgo && $0.date < todayEnd }
        )
        let entries = (try? context.fetch(descriptor)) ?? []

        var byDay: [Date: (kcal: Double, p: Double, c: Double, f: Double)] = [:]
        for entry in entries {
            let day = calendar.startOfDay(for: entry.date)
            var totals = byDay[day] ?? (0, 0, 0, 0)
            totals.kcal += entry.calories
            totals.p += entry.proteinG
            totals.c += entry.carbsG
            totals.f += entry.fatG
            byDay[day] = totals
        }

        let dayCount = Double(max(byDay.count, 1))
        let sums = byDay.values.reduce((kcal: 0.0, p: 0.0, c: 0.0, f: 0.0)) {
            ($0.kcal + $1.kcal, $0.p + $1.p, $0.c + $1.c, $0.f + $1.f)
        }

        weeklyAverages = [
            WeeklyAverage(label: "Calories", average: sums.kcal / dayCount, target: profile?.dailyCalorieTarget ?? 0, unit: "kcal"),
            WeeklyAverage(label: "Protein", average: sums.p / dayCount, target: profile?.proteinTargetG ?? 0, unit: "g"),
            WeeklyAverage(label: "Carbs", average: sums.c / dayCount, target: profile?.carbsTargetG ?? 0, unit: "g"),
            WeeklyAverage(label: "Fat", average: sums.f / dayCount, target: profile?.fatTargetG ?? 0, unit: "g"),
        ]
    }

    // MARK: - Body measurements

    var unitSystem: UnitSystem { profile?.preferredUnits ?? .metric }

    var latestMeasurement: BodyMeasurement? { allMeasurementsDescending.first }

    /// Waist samples oldest first, all time.
    var waistPoints: [MetricPoint] {
        allMeasurementsDescending.reversed().compactMap { measurement in
            guard let waist = measurement.waistCm else { return nil }
            return MetricPoint(id: measurement.id, date: measurement.date, value: waist)
        }
    }

    func deleteMeasurement(_ measurement: BodyMeasurement, in context: ModelContext) {
        context.delete(measurement)
        try? context.save()
        fetchMeasurements(from: context)
    }

    private func fetchMeasurements(from context: ModelContext) {
        allMeasurementsDescending = (try? context.fetch(FetchDescriptor<BodyMeasurement>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        ))) ?? []
    }

    // MARK: - Body fat

    /// True once any weigh-in ever recorded a body fat percentage.
    var hasAnyBodyFat: Bool {
        allWeightsDescending.contains { ($0.bodyFatPercent ?? 0) > 0 }
    }

    /// Body fat samples within the selected range, oldest first.
    var bodyFatPoints: [MetricPoint] {
        rangeWeights.compactMap { entry in
            guard let bodyFat = entry.bodyFatPercent, bodyFat > 0 else { return nil }
            return MetricPoint(id: entry.id, date: entry.date, value: bodyFat)
        }
    }

    // MARK: - Weight log

    /// Delta vs the previous (older) entry, nil for the oldest.
    func delta(for entry: WeightEntry) -> Double? {
        guard let index = allWeightsDescending.firstIndex(where: { $0.id == entry.id }),
              index + 1 < allWeightsDescending.count
        else { return nil }
        return entry.weightKg - allWeightsDescending[index + 1].weightKg
    }

    // MARK: - Goal projection

    struct GoalProjection {
        let goalWeightKg: Double
        let projectedDate: Date
    }

    /// Linear projection from the trend across the last 14 days of
    /// weigh-ins. Requires a goal weight, at least two entries spanning
    /// three days, and a trend actually moving toward the goal.
    var goalProjection: GoalProjection? {
        Self.projectGoal(
            weightsAscending: allWeightsDescending.reversed(),
            goalWeightKg: profile?.goalWeightKg ?? 0
        )
    }

    static func projectGoal(
        weightsAscending: [WeightEntry],
        goalWeightKg: Double,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> GoalProjection? {
        guard goalWeightKg > 0,
              let cutoff = calendar.date(byAdding: .day, value: -14, to: now)
        else { return nil }

        let recent = weightsAscending.filter { $0.date >= cutoff }
        guard let first = recent.first, let last = recent.last else { return nil }

        let spanDays = last.date.timeIntervalSince(first.date) / 86_400
        guard spanDays >= 3 else { return nil }

        let ratePerDay = (last.weightKg - first.weightKg) / spanDays
        let remaining = goalWeightKg - last.weightKg
        guard ratePerDay != 0, remaining / ratePerDay > 0 else { return nil }

        let daysToGoal = remaining / ratePerDay
        // Cap projections at two years out; beyond that the estimate is noise.
        guard daysToGoal <= 730,
              let date = calendar.date(byAdding: .day, value: Int(daysToGoal.rounded()), to: now)
        else { return nil }

        return GoalProjection(goalWeightKg: goalWeightKg, projectedDate: date)
    }
}
