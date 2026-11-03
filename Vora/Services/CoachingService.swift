//
//  CoachingService.swift
//  Vora
//
//  Created by Majd Arow on 2026-11-03.
//

import Foundation
import OSLog
import SwiftData

/// Reads the store into the plain values `CoachingEngine` works on. Nothing
/// here writes; docs/COACHING.md explains the rules.
enum CoachingService {
    private static let logger = Logger(subsystem: "com.majdarow.Vora", category: "Coaching")

    /// Days of check-ins the trends compare: this one and the one before.
    private static let checkInSpacingDays = 7

    /// The strength trend as of yesterday, and as it stood a week before. Worked
    /// out from sessions each time rather than stored, so skipped check-ins
    /// still count and deleting a session corrects it. Today is left out, as
    /// in the expenditure window.
    static func strengthTrends(
        context: ModelContext,
        now: Date,
        calendar: Calendar
    ) throws -> (current: CoachingEngine.StrengthTrend, previous: CoachingEngine.StrengthTrend) {
        let today = calendar.startOfDay(for: now)
        let lookback = CoachingEngine.strengthWindowDays + checkInSpacingDays
        guard let start = calendar.date(byAdding: .day, value: -lookback, to: today) else {
            return (.notEnoughData(usableLifts: 0), .notEnoughData(usableLifts: 0))
        }
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.date >= start && $0.date < today }
        ))
        let sets = strengthSets(from: sessions, start: start, calendar: calendar)
        let lastDay = lookback - 1
        return (
            CoachingEngine.strengthTrend(sets: sets, asOfDay: lastDay),
            CoachingEngine.strengthTrend(sets: sets, asOfDay: lastDay - checkInSpacingDays)
        )
    }

    static func strengthSets(from sessions: [WorkoutSession], start: Date, calendar: Calendar) -> [CoachingEngine.StrengthSet] {
        sessions.flatMap { session -> [CoachingEngine.StrengthSet] in
            guard let offset = calendar.dateComponents(
                [.day],
                from: start,
                to: calendar.startOfDay(for: session.date)
            ).day else { return [] }
            return session.exercises.flatMap { exercise in
                exercise.sets.filter(\.isCompleted).map { set in
                    CoachingEngine.StrengthSet(
                        exerciseKey: exercise.matchKey,
                        dayOffset: offset,
                        weightKg: set.weightKg,
                        reps: set.reps,
                        setType: set.setType
                    )
                }
            }
        }
    }

    /// Whole percent below expenditure when the user is in a meaningful
    /// deficit right now. nil without a recent check-in estimate: with no
    /// measured expenditure there's nothing to compare against, and it never
    /// guesses from the goal.
    static func deficitPercent(
        context: ModelContext,
        now: Date = .now,
        calendar: Calendar = .current
    ) throws -> Int? {
        let today = calendar.startOfDay(for: now)
        guard let oldestEstimate = calendar.date(byAdding: .day, value: -CoachingEngine.deficitEstimateMaxAgeDays, to: today),
              let windowStart = calendar.date(byAdding: .day, value: -CoachingEngine.deficitWindowDays, to: today)
        else { return nil }

        var descriptor = FetchDescriptor<ExpenditureCheckIn>(
            predicate: #Predicate { $0.date >= oldestEstimate && $0.date <= today },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        guard let estimate = try context.fetch(descriptor).first?.estimateKcal else { return nil }

        let food = try context.fetch(FetchDescriptor<FoodEntry>(
            predicate: #Predicate { $0.date >= windowStart && $0.date < today }
        ))
        let totals = Dictionary(grouping: food) { calendar.startOfDay(for: $0.date) }
            .mapValues { $0.reduce(0) { $0 + $1.calories } }
        return CoachingEngine.deficitPercent(loggedDays: Array(totals.values), expenditure: estimate)
    }

    /// `deficitPercent` for a session about to start: a failed read means no
    /// deficit context, which is how progression has always worked.
    static func deficitPercentOrNil(context: ModelContext, now: Date = .now, calendar: Calendar = .current) -> Int? {
        do {
            return try deficitPercent(context: context, now: now, calendar: calendar)
        } catch {
            logger.error("Failed to read the deficit: \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}
