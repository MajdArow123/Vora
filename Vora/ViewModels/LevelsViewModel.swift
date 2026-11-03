//
//  LevelsViewModel.swift
//  Vora
//
//  Created by Majd Arow on 2026-11-02.
//

import Foundation
import Observation
import OSLog
import SwiftData

@Observable
final class LevelsViewModel {
    private static let logger = Logger(subsystem: "com.majdarow.Vora", category: "Levels")

    /// Library muscles by exercise ID, for `LevelsCalculator`.
    static let libraryMuscles: [String: LevelsCalculator.ExerciseMuscles] = Dictionary(
        uniqueKeysWithValues: ExerciseLibrary.all.map {
            ($0.id, LevelsCalculator.ExerciseMuscles(primary: $0.primaryMuscles, secondary: $0.secondaryMuscles))
        }
    )

    var selectedRange: LevelsCalculator.Range = .fourWeeks {
        didSet { recompute() }
    }
    private(set) var result: LevelsCalculator.Result
    /// True when the last load failed, so an empty screen isn't mistaken for
    /// no training.
    private(set) var loadFailed = false

    private var sets: [LevelsCalculator.CompletedSet] = []
    private var firstTrainingDay: Int?

    init() {
        result = LevelsCalculator.calculate(sets: [], library: Self.libraryMuscles, range: .fourWeeks)
    }

    /// Fetches only as far back as the longest range, plus the first session
    /// ever. Changing range afterwards recalculates without fetching.
    func load(from context: ModelContext, now: Date = .now, calendar: Calendar = .current) {
        do {
            let today = calendar.startOfDay(for: now)
            sets = try Self.completedSets(context: context, today: today, calendar: calendar)
            firstTrainingDay = try Self.firstTrainingDay(context: context, today: today, calendar: calendar)
            loadFailed = false
        } catch {
            Self.logger.error("Failed to load levels: \(String(describing: error), privacy: .public)")
            sets = []
            firstTrainingDay = nil
            loadFailed = true
        }
        recompute()
    }

    private func recompute() {
        result = LevelsCalculator.calculate(
            sets: sets,
            library: Self.libraryMuscles,
            range: selectedRange,
            firstTrainingDay: firstTrainingDay
        )
    }

    /// Starts from sessions, so a deleted session or an orphaned log can't count.
    private static func completedSets(
        context: ModelContext,
        today: Date,
        calendar: Calendar
    ) throws -> [LevelsCalculator.CompletedSet] {
        guard let cutoff = calendar.date(byAdding: .day, value: 1 - LevelsCalculator.Range.longestDays, to: today) else {
            return []
        }
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.date >= cutoff },
            sortBy: [SortDescriptor(\.date)]
        ))
        return sessions.flatMap { session -> [LevelsCalculator.CompletedSet] in
            let dayOffset = dayOffset(of: session.date, today: today, calendar: calendar)
            return session.exercises.flatMap { log -> [LevelsCalculator.CompletedSet] in
                let completed = log.sets.filter(\.isCompleted).count
                let set = LevelsCalculator.CompletedSet(
                    exerciseKey: log.matchKey,
                    displayName: log.displayName,
                    storedMuscleGroups: log.muscleGroups,
                    dayOffset: dayOffset
                )
                return Array(repeating: set, count: completed)
            }
        }
    }

    private static func firstTrainingDay(context: ModelContext, today: Date, calendar: Calendar) throws -> Int? {
        var descriptor = FetchDescriptor<WorkoutSession>(sortBy: [SortDescriptor(\.date)])
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first.map {
            dayOffset(of: $0.date, today: today, calendar: calendar)
        }
    }

    /// Whole calendar days, safe across daylight saving changes.
    private static func dayOffset(of date: Date, today: Date, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: date)).day ?? 0
    }
}
