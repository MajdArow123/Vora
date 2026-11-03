//
//  CalorieCyclingService.swift
//  Vora
//
//  Created by Majd Arow on 2026-11-03.
//

import Foundation
import OSLog
import SwiftData

/// A day's targets, and what kind of day made them.
struct DayTargets: Equatable {
    let targets: MacroTargets
    /// nil when cycling isn't shaping this day: off, or it can't run.
    let kind: CalorieCycling.DayKind?
    /// Today's calories if a session starts, on a cycle-mode day that hasn't
    /// trained yet; nil otherwise.
    let ifTrainedCalories: Int?

    init(targets: MacroTargets, kind: CalorieCycling.DayKind? = nil, ifTrainedCalories: Int? = nil) {
        self.targets = targets
        self.kind = kind
        self.ifTrainedCalories = ifTrainedCalories
    }
}

extension UserProfile {
    /// The targets on the profile, which cycling averages to over a week.
    var baseTargets: MacroTargets {
        MacroTargets(calories: dailyCalorieTarget, proteinG: proteinTargetG, carbsG: carbsTargetG, fatG: fatTargetG)
    }
}

/// Works out a day's targets when calorie cycling is on. The profile always
/// keeps the base targets: nothing here writes.
enum CalorieCyclingService {
    private static let logger = Logger(subsystem: "com.majdarow.Vora", category: "CalorieCycling")

    /// How many weeks of sessions set a cycle's expected training days.
    private static let expectationWeeks = 4

    static func targets(
        on date: Date,
        profile: UserProfile,
        context: ModelContext,
        defaults: UserDefaults = .standard,
        activeSessionStart: () -> Date? = { SessionDraftStore().activeSessionStart() },
        now: Date = .now,
        calendar: Calendar = .current
    ) -> DayTargets {
        let base = DayTargets(targets: profile.baseTargets)
        // Unset reads as false, which is the setting's default.
        guard defaults.bool(forKey: CalorieCyclingSettings.storageKey) else { return base }
        do {
            return try cycled(
                on: date,
                profile: profile,
                context: context,
                activeSessionStart: activeSessionStart,
                now: now,
                calendar: calendar
            ) ?? base
        } catch {
            logger.error("Failed to work out today's targets: \(String(describing: error), privacy: .public)")
            return base
        }
    }

    /// nil when the day can't be cycled, which shows the base targets.
    private static func cycled(
        on date: Date,
        profile: UserProfile,
        context: ModelContext,
        activeSessionStart: () -> Date?,
        now: Date,
        calendar: Calendar
    ) throws -> DayTargets? {
        guard let floor = try floorCalories(profile: profile, context: context, now: now, calendar: calendar) else { return nil }

        let day = calendar.startOfDay(for: date)
        let dayIndex = (calendar.component(.weekday, from: day) + 5) % CalorieCycling.daysPerWeek
        let base = profile.baseTargets

        func calories(_ kinds: [CalorieCycling.DayKind], expected: Int) -> Int? {
            CalorieCycling.dayCalories(
                baseCalories: base.calories,
                floorCalories: floor,
                expectedTrainingDays: expected,
                kinds: kinds
            ).last
        }

        if try TrainingProgramService.activeCycle(context: context) == nil {
            let split = try context.fetch(FetchDescriptor<SplitDay>())
            var isRest: [Int: Bool] = [:]
            for row in split { isRest[row.dayIndex] = row.isRest }
            let week = (0..<CalorieCycling.daysPerWeek).compactMap { index in
                isRest[index].map { $0 ? CalorieCycling.DayKind.rest : .training }
            }
            guard week.count == CalorieCycling.daysPerWeek,
                  let total = calories(Array(week.prefix(dayIndex + 1)), expected: week.count { $0 == .training })
            else { return nil }
            return DayTargets(targets: CalorieCycling.scaled(base, toCalories: total), kind: week[dayIndex])
        }

        // A cycle has no plan for a future day, so those stay on the base.
        let today = calendar.startOfDay(for: now)
        guard day <= today,
              let weekStart = calendar.date(byAdding: .day, value: -dayIndex, to: day),
              let historyStart = calendar.date(byAdding: .day, value: -7 * expectationWeeks, to: weekStart),
              let dayEnd = calendar.date(byAdding: .day, value: 1, to: day)
        else { return nil }

        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.date >= historyStart && $0.date < dayEnd }
        ))
        var trainedDays = Set(sessions.filter { hasTrainingSet($0) }.map { calendar.startOfDay(for: $0.date) })
        if day == today, let started = activeSessionStart(), calendar.isDate(started, inSameDayAs: today) {
            trainedDays.insert(today)
        }

        // From before this week, so it's the same number all week long.
        let trainedBefore = trainedDays.count { $0 < weekStart }
        let expected = min(Int((Double(trainedBefore) / Double(expectationWeeks)).rounded()), CalorieCycling.daysPerWeek)

        var kinds: [CalorieCycling.DayKind] = []
        for offset in 0...dayIndex {
            guard let weekDay = calendar.date(byAdding: .day, value: offset, to: weekStart) else { return nil }
            kinds.append(trainedDays.contains(weekDay) ? .training : .rest)
        }
        guard let kind = kinds.last, let total = calories(kinds, expected: expected) else { return nil }

        var ifTrained: Int?
        if day == today, kind == .rest {
            kinds[dayIndex] = .training
            ifTrained = calories(kinds, expected: expected).flatMap { $0 > total ? $0 : nil }
        }
        return DayTargets(targets: CalorieCycling.scaled(base, toCalories: total), kind: kind, ifTrainedCalories: ifTrained)
    }

    /// Warm-ups alone don't make a training day, the same as for the cycle.
    private static func hasTrainingSet(_ session: WorkoutSession) -> Bool {
        session.exercises.contains { exercise in
            exercise.sets.contains { $0.isCompleted && $0.setType.countsAsTrainingSet }
        }
    }

    /// The same floor as the check-in's. nil with no weigh-ins, when the BMR
    /// isn't known: cycling stays off rather than guess at how low it may go.
    private static func floorCalories(profile: UserProfile, context: ModelContext, now: Date, calendar: Calendar) throws -> Int? {
        let entries = try context.fetch(FetchDescriptor<WeightEntry>(sortBy: [SortDescriptor(\.date)]))
        guard let trend = WeightTrendSeries(entries: entries, calendar: calendar) else { return nil }
        let age = calendar.dateComponents([.year], from: profile.dateOfBirth, to: now).year ?? 0
        let bmr = CalorieCalculator.bmr(
            weightKg: trend.currentKg,
            heightCm: profile.heightCm,
            age: age,
            sex: profile.biologicalSex
        )
        return Int((max(bmr, CalorieCalculator.minimumCalories) / 10).rounded(.up) * 10)
    }
}
