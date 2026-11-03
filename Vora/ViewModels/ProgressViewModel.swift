//
//  ProgressViewModel.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import Foundation
import Observation
import OSLog
import SwiftData

enum ChartRange: String, CaseIterable, Identifiable {
    case month = "1M"
    case quarter = "3M"
    case halfYear = "6M"
    case all = "All"

    var id: String { rawValue }

    /// Picker label — days for the short ranges, months beyond that.
    var displayName: String {
        switch self {
        case .month: "30D"
        case .quarter: "90D"
        case .halfYear: "6M"
        case .all: "All"
        }
    }

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
    private static let logger = Logger(subsystem: "com.majdarow.Vora", category: "Progress")

    private(set) var profile: UserProfile?
    /// Weigh-ins within the selected range, oldest first.
    private(set) var rangeWeights: [WeightEntry] = []
    /// All weigh-ins newest first, for the log list.
    private(set) var allWeightsDescending: [WeightEntry] = []
    /// The trend over all history; nil without weigh-ins.
    private(set) var weightTrend: WeightTrendSeries?
    /// The trend's days within the selected range, oldest first.
    private(set) var rangeTrendPoints: [WeightTrendSeries.Point] = []
    /// All weekly check-ins, oldest first.
    private(set) var allCheckIns: [ExpenditureCheckIn] = []
    /// Check-ins within the selected range, oldest first.
    private(set) var rangeCheckIns: [ExpenditureCheckIn] = []
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
        profile = fetchOrEmpty(FetchDescriptor<UserProfile>(), from: context).first

        allWeightsDescending = fetchOrEmpty(FetchDescriptor<WeightEntry>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        ), from: context)
        weightTrend = WeightTrendSeries(entries: allWeightsDescending, calendar: cal)
        allCheckIns = fetchOrEmpty(FetchDescriptor<ExpenditureCheckIn>(
            sortBy: [SortDescriptor(\.date)]
        ), from: context)
        fetchMeasurements(from: context)
        applyRange(now: now, calendar: cal)

        loadTraining(from: context, now: now, calendar: cal)
        loadWeeklyAverages(from: context, now: now, calendar: cal)
        loadSupplements(from: context, now: now, calendar: cal)
        daysTracked = TrackingStats.daysTracked(in: context, calendar: cal)
    }

    /// A failed fetch reads as no rows, so one bad query can't block Progress.
    private func fetchOrEmpty<Model: PersistentModel>(
        _ descriptor: FetchDescriptor<Model>,
        from context: ModelContext
    ) -> [Model] {
        do {
            return try context.fetch(descriptor)
        } catch {
            Self.logger.error("Failed to fetch \(String(describing: Model.self), privacy: .public): \(String(describing: error), privacy: .public)")
            return []
        }
    }

    func rangeChanged(now: Date = .now) {
        applyRange(now: now, calendar: .current)
    }

    private func applyRange(now: Date, calendar: Calendar) {
        guard let days = selectedRange.days,
              let cutoff = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: now))
        else {
            rangeWeights = allWeightsDescending.reversed()
            rangeTrendPoints = weightTrend?.points ?? []
            rangeCheckIns = allCheckIns
            return
        }
        rangeWeights = allWeightsDescending.filter { $0.date >= cutoff }.reversed()
        rangeTrendPoints = weightTrend?.points(onOrAfter: cutoff) ?? []
        rangeCheckIns = allCheckIns.filter { $0.date >= cutoff }
    }

    private func loadTraining(from context: ModelContext, now: Date, calendar: Calendar) {
        guard let windowStart = calendar.date(byAdding: .day, value: -40, to: calendar.startOfDay(for: now))
        else { return }
        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.date >= windowStart }
        )
        let dates = fetchOrEmpty(descriptor, from: context).map(\.date)

        weekDots = StreakCalculator.trailingWeek(sessionDates: dates, today: now, calendar: calendar)
        let restIndices = Set(
            fetchOrEmpty(FetchDescriptor<SplitDay>(), from: context)
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
        let active = fetchOrEmpty(supplementDescriptor, from: context)
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
        let logs = fetchOrEmpty(logDescriptor, from: context)

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
        let entries = fetchOrEmpty(descriptor, from: context)

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
        do {
            try context.save()
        } catch {
            Self.logger.error("Failed to delete measurement: \(String(describing: error), privacy: .public)")
            context.rollback()
        }
        fetchMeasurements(from: context)
    }

    private func fetchMeasurements(from context: ModelContext) {
        allMeasurementsDescending = fetchOrEmpty(FetchDescriptor<BodyMeasurement>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        ), from: context)
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

    enum GoalProjection: Equatable {
        case noGoal
        /// Too few weigh-ins, or none recently enough to trust the rate.
        case notEnoughData(loggedDays: Int, needed: Int)
        case notMovingTowardGoal
        case goalReached(goalKg: Double)
        case projected(goalKg: Double, date: Date)
    }

    /// Fewer weigh-ins than this give a rate that's mostly noise.
    static let minimumLoggedDays = 10
    /// How far back the trend's rate is measured. A weigh-in older than this
    /// also makes the rate stale.
    static let projectionWindowDays = 14
    /// A trend this close to the goal has reached it.
    static let goalReachedToleranceKg = 0.1
    /// Beyond two years the estimate is noise.
    static let maximumProjectionDays = 730.0

    var goalProjection: GoalProjection {
        Self.projectGoal(trend: weightTrend, goalWeightKg: profile?.goalWeightKg ?? 0)
    }

    /// Projects from the trend's rate over the last two weeks. The trend lags
    /// a steady change, so early projections run a little conservative.
    static func projectGoal(
        trend: WeightTrendSeries?,
        goalWeightKg: Double,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> GoalProjection {
        guard goalWeightKg > 0 else { return .noGoal }

        let loggedDays = trend?.result.loggedDayCount ?? 0
        let notEnoughData = GoalProjection.notEnoughData(loggedDays: loggedDays, needed: minimumLoggedDays)
        guard let trend, let lastDay = trend.lastDay, loggedDays >= minimumLoggedDays else { return notEnoughData }

        let today = calendar.startOfDay(for: now)
        guard let daysSinceLast = calendar.dateComponents([.day], from: lastDay, to: today).day,
              daysSinceLast <= projectionWindowDays,
              trend.result.loggedDays(inLast: projectionWindowDays + 1) >= 2,
              let ratePerDay = trend.result.ratePerDay(window: projectionWindowDays)
        else { return notEnoughData }

        let remaining = goalWeightKg - trend.currentKg
        guard abs(remaining) >= goalReachedToleranceKg else { return .goalReached(goalKg: goalWeightKg) }
        guard ratePerDay != 0, remaining / ratePerDay > 0 else { return .notMovingTowardGoal }

        let daysToGoal = remaining / ratePerDay
        guard daysToGoal <= maximumProjectionDays,
              let date = calendar.date(byAdding: .day, value: Int(daysToGoal.rounded()), to: lastDay)
        else { return .notMovingTowardGoal }

        return .projected(goalKg: goalWeightKg, date: max(date, today))
    }
}
