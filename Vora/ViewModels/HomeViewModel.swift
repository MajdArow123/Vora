//
//  HomeViewModel.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import Foundation
import Observation
import SwiftData

@Observable
final class HomeViewModel {
    private(set) var profile: UserProfile?
    private(set) var todayFood: [FoodEntry] = []
    private(set) var todayWater: [WaterEntry] = []
    private(set) var todaySplitDay: SplitDay?
    private(set) var hasTrainedToday = false
    /// Last 7 days of weigh-ins, oldest first.
    private(set) var weekWeights: [WeightEntry] = []
    /// Trained flags for the trailing 7 days, oldest first.
    private(set) var weekDots: [Bool] = []
    private(set) var streakDays = 0
    /// Fully-logged-food flags (3+ meal slots) for the trailing 7 days, oldest first.
    private(set) var foodWeekDots: [Bool] = []
    private(set) var foodStreakDays = 0
    private(set) var daysTracked = 0
    private(set) var insight: Insight?
    /// Active supplements sorted by the user's order.
    private(set) var activeSupplements: [Supplement] = []
    private(set) var takenSupplementIDs: Set<UUID> = []
    private(set) var supplementStreakDays = 0
    /// Untaken morning / pre-workout supplement names, in user order —
    /// feeds the "supplement missed" insight.
    private(set) var untakenEarlySupplementNames: [String] = []

    private let defaults: UserDefaults
    private let insightDateKey = "vora.insight.date"
    private let insightPayloadKey = "vora.insight.payload"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Loading

    func load(from context: ModelContext, now: Date = .now) {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: now)
        guard let todayEnd = cal.date(byAdding: .day, value: 1, to: todayStart) else { return }

        profile = try? context.fetch(FetchDescriptor<UserProfile>()).first

        let foodDescriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate { $0.date >= todayStart && $0.date < todayEnd }
        )
        todayFood = (try? context.fetch(foodDescriptor)) ?? []

        let waterDescriptor = FetchDescriptor<WaterEntry>(
            predicate: #Predicate { $0.date >= todayStart && $0.date < todayEnd },
            sortBy: [SortDescriptor(\.date)]
        )
        todayWater = (try? context.fetch(waterDescriptor)) ?? []

        let todayIndex = (cal.component(.weekday, from: now) + 5) % 7
        let splitDescriptor = FetchDescriptor<SplitDay>(
            predicate: #Predicate { $0.dayIndex == todayIndex }
        )
        todaySplitDay = try? context.fetch(splitDescriptor).first

        loadWeights(from: context, todayStart: todayStart, calendar: cal)
        loadTraining(from: context, now: now, todayEnd: todayEnd, calendar: cal)
        loadFoodStreak(from: context, now: now, todayEnd: todayEnd, calendar: cal)
        loadSupplements(from: context, now: now, todayStart: todayStart, todayEnd: todayEnd, calendar: cal)
        daysTracked = TrackingStats.daysTracked(in: context, calendar: cal)
        loadInsight(now: now, calendar: cal)
    }

    private func loadWeights(from context: ModelContext, todayStart: Date, calendar: Calendar) {
        guard let weekAgo = calendar.date(byAdding: .day, value: -6, to: todayStart) else { return }
        let descriptor = FetchDescriptor<WeightEntry>(
            predicate: #Predicate { $0.date >= weekAgo },
            sortBy: [SortDescriptor(\.date)]
        )
        weekWeights = (try? context.fetch(descriptor)) ?? []
    }

    private func loadTraining(from context: ModelContext, now: Date, todayEnd: Date, calendar: Calendar) {
        // 40 days of sessions covers the longest streak milestone (30)
        // plus headroom, without fetching all history.
        guard let windowStart = calendar.date(byAdding: .day, value: -40, to: todayEnd) else { return }
        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.date >= windowStart && $0.date < todayEnd },
            sortBy: [SortDescriptor(\.date)]
        )
        let sessions = (try? context.fetch(descriptor)) ?? []
        let dates = sessions.map(\.date)

        hasTrainedToday = sessions.contains { calendar.isDate($0.date, inSameDayAs: now) }
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

    private func loadFoodStreak(from context: ModelContext, now: Date, todayEnd: Date, calendar: Calendar) {
        // Same 40-day window tradeoff as loadTraining.
        guard let windowStart = calendar.date(byAdding: .day, value: -40, to: todayEnd) else { return }
        let descriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate { $0.date >= windowStart && $0.date < todayEnd }
        )
        let entries = (try? context.fetch(descriptor)) ?? []
        let qualifying = StreakCalculator.qualifyingFoodDays(
            entries: entries.map { (date: $0.date, slot: $0.mealSlot) },
            calendar: calendar
        )
        foodWeekDots = StreakCalculator.trailingWeek(sessionDates: Array(qualifying), today: now, calendar: calendar)
        foodStreakDays = StreakCalculator.foodStreak(qualifyingDays: qualifying, today: now, calendar: calendar)
    }

    private func loadSupplements(
        from context: ModelContext,
        now: Date,
        todayStart: Date,
        todayEnd: Date,
        calendar: Calendar
    ) {
        let supplementDescriptor = FetchDescriptor<Supplement>(
            predicate: #Predicate { $0.isActive },
            sortBy: [SortDescriptor(\.orderIndex)]
        )
        activeSupplements = (try? context.fetch(supplementDescriptor)) ?? []

        // Same 40-day window tradeoff as loadTraining.
        guard let windowStart = calendar.date(byAdding: .day, value: -40, to: todayEnd) else { return }
        let logDescriptor = FetchDescriptor<SupplementLog>(
            predicate: #Predicate { $0.date >= windowStart && $0.date < todayEnd }
        )
        let logs = (try? context.fetch(logDescriptor)) ?? []

        takenSupplementIDs = Set(logs.filter { $0.date >= todayStart }.map(\.supplementID))
        untakenEarlySupplementNames = activeSupplements
            .filter { ($0.timing == .morning || $0.timing == .preWorkout) && !takenSupplementIDs.contains($0.id) }
            .map(\.name)

        let qualifying = StreakCalculator.qualifyingSupplementDays(
            logs: logs.map { (supplementID: $0.supplementID, date: $0.date) },
            activeSupplements: activeSupplements.map { (id: $0.id, createdAt: $0.createdAt) },
            calendar: calendar
        )
        supplementStreakDays = StreakCalculator.foodStreak(qualifyingDays: qualifying, today: now, calendar: calendar)
    }

    // MARK: - Insight

    private func loadInsight(now: Date, calendar: Calendar) {
        let todayKey = Self.dayKey(for: now, calendar: calendar)

        if defaults.string(forKey: insightDateKey) == todayKey,
           let data = defaults.data(forKey: insightPayloadKey),
           let stored = try? JSONDecoder().decode(Insight.self, from: data) {
            insight = stored
            return
        }

        // Exclude yesterday's rule; an older stored insight is stale and
        // does not constrain today.
        var lastRule: InsightRule?
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           defaults.string(forKey: insightDateKey) == Self.dayKey(for: yesterday, calendar: calendar),
           let data = defaults.data(forKey: insightPayloadKey),
           let stored = try? JSONDecoder().decode(Insight.self, from: data) {
            lastRule = stored.rule
        }

        let generated = InsightEngine.generate(from: insightInput(now: now, calendar: calendar), excluding: lastRule)
        insight = generated
        defaults.set(todayKey, forKey: insightDateKey)
        defaults.set(try? JSONEncoder().encode(generated), forKey: insightPayloadKey)
    }

    private func insightInput(now: Date, calendar: Calendar) -> InsightInput {
        InsightInput(
            date: now,
            hour: calendar.component(.hour, from: now),
            proteinConsumedG: totalProtein,
            proteinTargetG: profile?.proteinTargetG ?? 0,
            caloriesConsumed: totalCalories,
            calorieTarget: profile?.dailyCalorieTarget ?? 0,
            isScheduledWorkoutDay: todaySplitDay.map { !$0.isRest } ?? false,
            hasTrainedToday: hasTrainedToday,
            streakDays: streakDays,
            consecutiveDailyWeightsKg: Self.consecutiveDailyWeights(from: weekWeights, calendar: calendar),
            daysTracked: daysTracked,
            untakenEarlySupplementNames: untakenEarlySupplementNames,
            supplementStreakDays: supplementStreakDays
        )
    }

    private static func dayKey(for date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }

    /// Latest weigh-in per day for the unbroken run of consecutive
    /// calendar days ending at the most recent entry, oldest first.
    static func consecutiveDailyWeights(from entries: [WeightEntry], calendar: Calendar) -> [Double] {
        var latestPerDay: [Date: Double] = [:]
        for entry in entries {
            latestPerDay[calendar.startOfDay(for: entry.date)] = entry.weightKg
        }
        guard var day = latestPerDay.keys.max() else { return [] }

        var run: [Double] = []
        while let weight = latestPerDay[day] {
            run.insert(weight, at: 0)
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return run
    }

    // MARK: - Derived totals

    var totalCalories: Double { todayFood.reduce(0) { $0 + $1.calories } }
    var totalProtein: Double { todayFood.reduce(0) { $0 + $1.proteinG } }
    var totalCarbs: Double { todayFood.reduce(0) { $0 + $1.carbsG } }
    var totalFat: Double { todayFood.reduce(0) { $0 + $1.fatG } }

    /// Meal slots with at least one entry today — feeds the AI meal-type
    /// computation ("suggest a snack once lunch is logged").
    var todayMealSlots: Set<MealSlot> { Set(todayFood.map(\.mealSlot)) }

    var remainingMacros: RemainingMacros {
        RemainingMacros(
            calories: (profile?.dailyCalorieTarget ?? 0) - Int(totalCalories.rounded()),
            proteinG: (profile?.proteinTargetG ?? 0) - Int(totalProtein.rounded()),
            carbsG: (profile?.carbsTargetG ?? 0) - Int(totalCarbs.rounded()),
            fatG: (profile?.fatTargetG ?? 0) - Int(totalFat.rounded())
        )
    }

    var dailyTargets: MacroTargets {
        MacroTargets(
            calories: profile?.dailyCalorieTarget ?? 0,
            proteinG: profile?.proteinTargetG ?? 0,
            carbsG: profile?.carbsTargetG ?? 0,
            fatG: profile?.fatTargetG ?? 0
        )
    }

    /// What's left of one slot's share of the daily targets — what the AI
    /// suggestion should fill for that meal.
    func mealRemaining(for slot: MealSlot) -> RemainingMacros {
        MealAllocation.remaining(
            for: slot,
            daily: dailyTargets,
            slotConsumed: todayFood
                .filter { $0.mealSlot == slot }
                .map { ($0.calories, $0.proteinG, $0.carbsG, $0.fatG) }
        )
    }

    var waterTotalMl: Double { todayWater.reduce(0) { $0 + $1.amountMl } }
    var waterTargetMl: Double { profile?.waterTargetMl ?? 3500 }
    var glassCount: Int { Int((waterTotalMl / FoodDiaryViewModel.glassMl).rounded(.down)) }

    var latestWeight: WeightEntry? { weekWeights.last }

    var supplementsTakenCount: Int {
        activeSupplements.filter { takenSupplementIDs.contains($0.id) }.count
    }

    /// Change between the first and last weigh-in of the trailing week.
    var weekWeightDeltaKg: Double? {
        guard let first = weekWeights.first, let last = weekWeights.last,
              first.id != last.id else { return nil }
        return last.weightKg - first.weightKg
    }

    // MARK: - Water mutations (mirrors the Food tab)

    func addGlass(context: ModelContext) {
        context.insert(WaterEntry(date: .now, amountMl: FoodDiaryViewModel.glassMl))
        try? context.save()
        load(from: context)
    }

    func removeGlass(context: ModelContext) {
        guard let latest = todayWater.last else { return }
        context.delete(latest)
        try? context.save()
        load(from: context)
    }

    // MARK: - Supplement mutations

    /// Toggles today's taken state. Returns true when the supplement was
    /// just marked taken, so the caller can fire haptics.
    @discardableResult
    func toggleSupplement(_ supplement: Supplement, context: ModelContext, now: Date = .now) -> Bool {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: now)
        guard let todayEnd = cal.date(byAdding: .day, value: 1, to: todayStart) else { return false }

        let supplementID = supplement.id
        let markedTaken: Bool
        if takenSupplementIDs.contains(supplementID) {
            let descriptor = FetchDescriptor<SupplementLog>(
                predicate: #Predicate {
                    $0.supplementID == supplementID && $0.date >= todayStart && $0.date < todayEnd
                }
            )
            ((try? context.fetch(descriptor)) ?? []).forEach { context.delete($0) }
            markedTaken = false
        } else {
            context.insert(SupplementLog(
                supplementID: supplementID,
                supplementName: supplement.name,
                dose: supplement.dose,
                date: todayStart,
                takenAt: now
            ))
            markedTaken = true
        }
        try? context.save()
        load(from: context, now: now)
        // Taken state changes today's reminder condition.
        NotificationService.shared.refreshAll(context: context, now: now)
        return markedTaken
    }
}
