//
//  StrengthProgressViewModel.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-25.
//

import Foundation
import Observation
import SwiftData

struct WeeklyVolumePoint: Identifiable {
    let weekStart: Date
    let volumeKg: Double

    var id: Date { weekStart }
}

struct WeeklyCardioPoint: Identifiable {
    let weekStart: Date
    let minutes: Double
    let calories: Double

    var id: Date { weekStart }
}

@Observable
final class StrengthProgressViewModel {
    private(set) var exerciseNames: [String] = []
    private(set) var progression: [ExerciseSessionStat] = []
    private(set) var weeklyVolume: [WeeklyVolumePoint] = []
    private(set) var weeklyCardio: [WeeklyCardioPoint] = []

    var selectedExercise: String?
    var selectedRange: ChartRange = .quarter

    private var allSessions: [WorkoutSession] = []
    private var allCardio: [CardioEntry] = []

    // MARK: - Loading

    func load(from context: ModelContext, now: Date = .now) {
        allSessions = (try? context.fetch(FetchDescriptor<WorkoutSession>(
            sortBy: [SortDescriptor(\.date)]
        ))) ?? []
        allCardio = (try? context.fetch(FetchDescriptor<CardioEntry>(
            sortBy: [SortDescriptor(\.date)]
        ))) ?? []

        exerciseNames = StrengthProgression.distinctExerciseNames(in: allSessions)
        if selectedExercise == nil
            || !exerciseNames.contains(where: { $0 == selectedExercise }) {
            selectedExercise = WorkoutHomeViewModel
                .computePersonalRecords(from: context, limit: 1)
                .first?.exerciseName ?? exerciseNames.first
        }
        recompute(now: now)
    }

    func rangeChanged(now: Date = .now) {
        recompute(now: now)
    }

    func exerciseChanged(now: Date = .now) {
        recompute(now: now)
    }

    private func recompute(now: Date, calendar: Calendar = .current) {
        let cutoff = Self.cutoff(for: selectedRange, now: now, calendar: calendar)

        if let name = selectedExercise {
            let stats = StrengthProgression.sessionStats(for: name, sessions: allSessions)
            progression = cutoff.map { cut in stats.filter { $0.date >= cut } } ?? stats
        } else {
            progression = []
        }
        weeklyVolume = Self.weeklyVolume(
            sessions: allSessions, range: selectedRange, now: now, calendar: calendar
        )
        weeklyCardio = Self.weeklyCardio(
            entries: allCardio, range: selectedRange, now: now, calendar: calendar
        )
    }

    // MARK: - Aggregation

    static func weeklyVolume(
        sessions: [WorkoutSession],
        range: ChartRange,
        now: Date,
        calendar: Calendar = .current
    ) -> [WeeklyVolumePoint] {
        let buckets = weeklyBuckets(
            dates: sessions.map(\.date),
            values: sessions.map { ($0.totalVolumeKg, 0.0) },
            range: range, now: now, calendar: calendar
        )
        return buckets.map { WeeklyVolumePoint(weekStart: $0.weekStart, volumeKg: $0.first) }
    }

    static func weeklyCardio(
        entries: [CardioEntry],
        range: ChartRange,
        now: Date,
        calendar: Calendar = .current
    ) -> [WeeklyCardioPoint] {
        let buckets = weeklyBuckets(
            dates: entries.map(\.date),
            values: entries.map { (Double($0.durationSeconds) / 60, $0.estimatedCalories) },
            range: range, now: now, calendar: calendar
        )
        return buckets.map {
            WeeklyCardioPoint(weekStart: $0.weekStart, minutes: $0.first, calories: $0.second)
        }
    }

    static func cutoff(for range: ChartRange, now: Date, calendar: Calendar = .current) -> Date? {
        guard let days = range.days else { return nil }
        return calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: now))
    }

    /// Sums paired values into calendar-week buckets, gap-filling empty
    /// weeks between the first and last active week so bar charts show
    /// missed weeks honestly.
    private static func weeklyBuckets(
        dates: [Date],
        values: [(Double, Double)],
        range: ChartRange,
        now: Date,
        calendar: Calendar
    ) -> [(weekStart: Date, first: Double, second: Double)] {
        let cut = cutoff(for: range, now: now, calendar: calendar)
        var sums: [Date: (Double, Double)] = [:]

        for (date, value) in zip(dates, values) {
            if let cut, date < cut { continue }
            guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: date)?.start
            else { continue }
            let existing = sums[weekStart] ?? (0, 0)
            sums[weekStart] = (existing.0 + value.0, existing.1 + value.1)
        }

        guard let firstWeek = sums.keys.min(), let lastWeek = sums.keys.max()
        else { return [] }

        var result: [(weekStart: Date, first: Double, second: Double)] = []
        var week = firstWeek
        while week <= lastWeek {
            let sum = sums[week] ?? (0, 0)
            result.append((weekStart: week, first: sum.0, second: sum.1))
            guard let next = calendar.date(byAdding: .weekOfYear, value: 1, to: week)
            else { break }
            week = next
        }
        return result
    }
}
