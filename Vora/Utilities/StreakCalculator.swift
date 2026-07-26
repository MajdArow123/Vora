//
//  StreakCalculator.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import Foundation

enum StreakCalculator {
    /// Consecutive days (ending today) on which the user kept to their
    /// split: every scheduled training day has a logged session, and rest
    /// days carry the streak through. Today only counts once trained —
    /// an untrained scheduled day today pauses the streak rather than
    /// breaking it.
    ///
    /// - Parameters:
    ///   - sessionDates: dates of all logged workout sessions.
    ///   - restDayIndices: Monday-based day indices (0 = Monday) that are
    ///     rest days in the user's split. An empty set treats every day
    ///     as a training day.
    static func adherenceStreak(
        sessionDates: [Date],
        restDayIndices: Set<Int>,
        today: Date = .now,
        calendar: Calendar = .current
    ) -> Int {
        let trainedDays = Set(sessionDates.map { calendar.startOfDay(for: $0) })
        var streak = 0
        var day = calendar.startOfDay(for: today)

        // Today is a grace day: it extends the streak when trained but
        // never breaks it.
        if trainedDays.contains(day) {
            streak += 1
        }
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else {
            return streak
        }
        day = yesterday

        while true {
            let dayIndex = (calendar.component(.weekday, from: day) + 5) % 7
            let kept = trainedDays.contains(day) || restDayIndices.contains(dayIndex)
            guard kept else { break }
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return streak
    }

    /// Days on which the user tracked a real day of eating: at least
    /// three distinct meal slots have an entry. Returns start-of-day
    /// dates.
    static func qualifyingFoodDays(
        entries: [(date: Date, slot: MealSlot)],
        calendar: Calendar = .current
    ) -> Set<Date> {
        var slotsByDay: [Date: Set<MealSlot>] = [:]
        for entry in entries {
            slotsByDay[calendar.startOfDay(for: entry.date), default: []].insert(entry.slot)
        }
        return Set(slotsByDay.filter { $0.value.count >= 3 }.keys)
    }

    /// Consecutive fully-logged food days ending today. Mirrors
    /// `adherenceStreak`'s grace-day rule — today extends the streak
    /// once it qualifies but never breaks it — with no rest days.
    ///
    /// - Parameter qualifyingDays: start-of-day dates from
    ///   `qualifyingFoodDays(entries:calendar:)`.
    static func foodStreak(
        qualifyingDays: Set<Date>,
        today: Date = .now,
        calendar: Calendar = .current
    ) -> Int {
        var streak = 0
        var day = calendar.startOfDay(for: today)
        if qualifyingDays.contains(day) {
            streak += 1
        }
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else {
            return streak
        }
        day = yesterday

        while qualifyingDays.contains(day) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return streak
    }

    /// Days on which every supplement that existed by that day was taken.
    /// A day only qualifies when at least one supplement was required, and
    /// supplements added later never retroactively break earlier days.
    /// Returns start-of-day dates.
    ///
    /// - Parameters:
    ///   - logs: supplement id + calendar day of every taken-log.
    ///   - activeSupplements: id + creation date of the currently active
    ///     supplements — deactivated ones drop out of every requirement.
    static func qualifyingSupplementDays(
        logs: [(supplementID: UUID, date: Date)],
        activeSupplements: [(id: UUID, createdAt: Date)],
        calendar: Calendar = .current
    ) -> Set<Date> {
        guard !activeSupplements.isEmpty else { return [] }
        var takenByDay: [Date: Set<UUID>] = [:]
        for log in logs {
            takenByDay[calendar.startOfDay(for: log.date), default: []].insert(log.supplementID)
        }
        let requirements = activeSupplements.map {
            (id: $0.id, startDay: calendar.startOfDay(for: $0.createdAt))
        }
        return Set(takenByDay.filter { day, takenIDs in
            let required = requirements.filter { $0.startDay <= day }.map(\.id)
            return !required.isEmpty && required.allSatisfy(takenIDs.contains)
        }.keys)
    }

    /// Percentage (0–100) of days this month on which all supplements were
    /// taken. The window starts at the later of the month start and the
    /// earliest supplement's creation day, so a user who added their first
    /// supplement mid-month is not penalised for the days before it.
    static func monthlyConsistency(
        qualifyingDays: Set<Date>,
        earliestCreatedAt: Date?,
        today: Date = .now,
        calendar: Calendar = .current
    ) -> Int {
        guard let earliestCreatedAt,
              let monthStart = calendar.dateInterval(of: .month, for: today)?.start else {
            return 0
        }
        let windowStart = max(monthStart, calendar.startOfDay(for: earliestCreatedAt))
        let todayStart = calendar.startOfDay(for: today)
        guard windowStart <= todayStart,
              let days = calendar.dateComponents([.day], from: windowStart, to: todayStart).day else {
            return 0
        }
        let windowDays = days + 1
        let qualified = qualifyingDays.filter { $0 >= windowStart && $0 <= todayStart }.count
        return min(100, Int((Double(qualified) / Double(windowDays) * 100).rounded()))
    }

    /// Trained / not-trained flags for the trailing 7 days, oldest first
    /// (index 6 is today). Drives the streak dot views.
    static func trailingWeek(
        sessionDates: [Date],
        today: Date = .now,
        calendar: Calendar = .current
    ) -> [Bool] {
        let trainedDays = Set(sessionDates.map { calendar.startOfDay(for: $0) })
        let todayStart = calendar.startOfDay(for: today)
        return (0..<7).map { offset in
            guard let day = calendar.date(byAdding: .day, value: offset - 6, to: todayStart) else {
                return false
            }
            return trainedDays.contains(day)
        }
    }
}
