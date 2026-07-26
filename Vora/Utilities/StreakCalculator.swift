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
