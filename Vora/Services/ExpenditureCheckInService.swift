//
//  ExpenditureCheckInService.swift
//  Vora
//
//  Created by Majd Arow on 2026-11-02.
//

import Foundation
import SwiftData

/// What the weekly check-in would change if the user taps Apply.
struct ExpenditureProposal: Equatable {
    /// The start of the check-in day this answers.
    let checkInDate: Date
    /// The estimate before this check-in: the last one, or the formula's.
    let previousEstimate: Double
    let result: ExpenditureEstimator.Result
    let currentTargets: MacroTargets
    let proposedTargets: ExpenditureTargets
    /// The floor `proposedTargets` is held at, when it is.
    let floorCalories: Double
}

enum WeeklyCheckInState: Equatable {
    case notDue
    case needsMoreData(intakeDays: Int, neededIntakeDays: Int, weighIns: Int, neededWeighIns: Int)
    case ready(ExpenditureProposal)
}

/// Reads the store for the estimator and writes the user's answer. Targets
/// only ever change through `apply`.
enum ExpenditureCheckInService {
    /// The most recent check-in day on or before `now`.
    static func checkInDay(for weekday: CheckInWeekday, now: Date, calendar: Calendar) -> Date? {
        let today = calendar.startOfDay(for: now)
        let daysSince = (calendar.component(.weekday, from: today) - weekday.rawValue + 7) % 7
        return calendar.date(byAdding: .day, value: -daysSince, to: today)
    }

    /// A check-in stays open until the next check-in day, so a missed Monday
    /// doesn't lose the week. "Not enough data" shows on the day itself only,
    /// so new users don't see it all week. The window is the 21 complete days
    /// before today: today's log is still partial.
    static func state(
        context: ModelContext,
        weekday: CheckInWeekday,
        now: Date = .now,
        calendar: Calendar = .current
    ) throws -> WeeklyCheckInState {
        let today = calendar.startOfDay(for: now)
        guard let checkInDate = checkInDay(for: weekday, now: now, calendar: calendar),
              let windowStart = calendar.date(byAdding: .day, value: -ExpenditureEstimator.defaultWindowDays, to: today),
              let profile = try context.fetch(FetchDescriptor<UserProfile>()).first
        else { return .notDue }

        var latestDescriptor = FetchDescriptor<ExpenditureCheckIn>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        latestDescriptor.fetchLimit = 1
        let latest = try context.fetch(latestDescriptor).first
        if let latest, latest.date >= checkInDate { return .notDue }

        let weights = try context.fetch(FetchDescriptor<WeightEntry>(
            predicate: #Predicate { $0.date < today },
            sortBy: [SortDescriptor(\.date)]
        ))
        let food = try context.fetch(FetchDescriptor<FoodEntry>(
            predicate: #Predicate { $0.date >= windowStart && $0.date < today }
        ))

        let intake = intakeDays(from: food, windowStart: windowStart, calendar: calendar)
        let recentWeights = weightDays(from: weights.filter { $0.date >= windowStart }, windowStart: windowStart, calendar: calendar)

        // The profile stores no weight, so with no weigh-ins there's no
        // formula TDEE, and no estimate could run anyway.
        guard let trend = WeightTrendSeries(entries: weights, calendar: calendar) else {
            let logged = intake.compactMap(\.kcal).count
            return needsMoreData(intakeDays: logged, weighIns: 0, isCheckInDay: checkInDate == today)
        }

        let age = calendar.dateComponents([.year], from: profile.dateOfBirth, to: now).year ?? 0
        let bmr = CalorieCalculator.bmr(
            weightKg: trend.currentKg,
            heightCm: profile.heightCm,
            age: age,
            sex: profile.biologicalSex
        )
        let formula = bmr * profile.activityLevel.multiplier
        let result = ExpenditureEstimator.estimate(ExpenditureEstimator.Input(
            intake: intake,
            weights: recentWeights,
            formulaTDEE: formula,
            previousEstimate: latest?.estimateKcal,
            lastDayOffset: ExpenditureEstimator.defaultWindowDays - 1
        ))

        if case .notEnoughData(let intakeDays, _, let weighIns, _) = result.reason {
            return needsMoreData(intakeDays: intakeDays, weighIns: weighIns, isCheckInDay: checkInDate == today)
        }

        return .ready(ExpenditureProposal(
            checkInDate: checkInDate,
            previousEstimate: latest?.estimateKcal ?? formula,
            result: result,
            currentTargets: MacroTargets(
                calories: profile.dailyCalorieTarget,
                proteinG: profile.proteinTargetG,
                carbsG: profile.carbsTargetG,
                fatG: profile.fatTargetG
            ),
            proposedTargets: CalorieCalculator.targets(
                fromExpenditure: result.estimate,
                weightKg: trend.currentKg,
                goal: profile.goalType,
                bmr: bmr
            ),
            floorCalories: max(bmr, CalorieCalculator.minimumCalories)
        ))
    }

    /// Saves the check-in and writes its targets to the profile. A second
    /// answer for the same day changes nothing.
    static func apply(_ proposal: ExpenditureProposal, context: ModelContext) throws {
        guard try !hasCheckIn(on: proposal.checkInDate, context: context) else { return }
        let targets = proposal.proposedTargets
        if let profile = try context.fetch(FetchDescriptor<UserProfile>()).first {
            profile.dailyCalorieTarget = targets.calories
            profile.proteinTargetG = targets.proteinG
            profile.carbsTargetG = targets.carbsG
            profile.fatTargetG = targets.fatG
        }
        try record(proposal, applied: true, context: context)
    }

    /// Saves the check-in and leaves the targets alone.
    static func skip(_ proposal: ExpenditureProposal, context: ModelContext) throws {
        guard try !hasCheckIn(on: proposal.checkInDate, context: context) else { return }
        try record(proposal, applied: false, context: context)
    }

    private static func needsMoreData(intakeDays: Int, weighIns: Int, isCheckInDay: Bool) -> WeeklyCheckInState {
        guard isCheckInDay else { return .notDue }
        return .needsMoreData(
            intakeDays: intakeDays,
            neededIntakeDays: ExpenditureEstimator.minimumIntakeDays,
            weighIns: weighIns,
            neededWeighIns: ExpenditureEstimator.minimumWeighIns
        )
    }

    private static func hasCheckIn(on date: Date, context: ModelContext) throws -> Bool {
        try context.fetchCount(FetchDescriptor<ExpenditureCheckIn>(predicate: #Predicate { $0.date == date })) > 0
    }

    private static func record(_ proposal: ExpenditureProposal, applied: Bool, context: ModelContext) throws {
        let result = proposal.result
        let targets = proposal.proposedTargets
        context.insert(ExpenditureCheckIn(
            date: proposal.checkInDate,
            estimateKcal: result.estimate,
            rawEstimateKcal: result.rawEstimate ?? result.estimate,
            avgIntakeKcal: result.averageIntake ?? 0,
            slopeKgPerDay: result.slopeKgPerDay ?? 0,
            daysUsed: result.daysUsed,
            applied: applied,
            appliedCalories: applied ? targets.calories : nil,
            appliedProteinG: applied ? targets.proteinG : nil,
            appliedCarbsG: applied ? targets.carbsG : nil,
            appliedFatG: applied ? targets.fatG : nil
        ))
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    /// One entry per window day; a day with no food logged is nil.
    private static func intakeDays(
        from entries: [FoodEntry],
        windowStart: Date,
        calendar: Calendar
    ) -> [ExpenditureEstimator.IntakeDay] {
        var totals: [Int: Double] = [:]
        for entry in entries {
            guard let offset = dayOffset(of: entry.date, from: windowStart, calendar: calendar) else { continue }
            totals[offset, default: 0] += entry.calories
        }
        return (0..<ExpenditureEstimator.defaultWindowDays).map { offset in
            ExpenditureEstimator.IntakeDay(dayOffset: offset, kcal: totals[offset])
        }
    }

    private static func weightDays(
        from entries: [WeightEntry],
        windowStart: Date,
        calendar: Calendar
    ) -> [ExpenditureEstimator.WeightDay] {
        entries.compactMap { entry in
            dayOffset(of: entry.date, from: windowStart, calendar: calendar).map {
                ExpenditureEstimator.WeightDay(dayOffset: $0, weightKg: entry.weightKg)
            }
        }
    }

    /// Counts calendar days, so a daylight saving change can't shift a day.
    private static func dayOffset(of date: Date, from start: Date, calendar: Calendar) -> Int? {
        calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: date)).day
    }
}
