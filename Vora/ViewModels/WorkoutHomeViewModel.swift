//
//  WorkoutHomeViewModel.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import Foundation
import Observation
import OSLog
import SwiftData

struct PersonalRecord: Identifiable {
    /// Display name: the library's current name for library exercises.
    let exerciseName: String
    let weightKg: Double
    let reps: Int
    let date: Date
    /// Library ID; nil for custom exercises.
    var exerciseId: String?
    var totalSets: Int = 0
    var minReps: Int = 0
    var maxReps: Int = 0

    /// Identity key shared by every log of this exercise (see ExerciseIdentity).
    var id: String { ExerciseIdentity.key(exerciseId: exerciseId, name: exerciseName) }

    /// Epley estimate.
    var estimatedOneRepMax: Double {
        weightKg * (1 + Double(reps) / 30)
    }

    var setsSummary: String {
        StrengthProgression.setsSummary(count: totalSets, minReps: minReps, maxReps: maxReps)
    }

    var spokenSetsSummary: String {
        StrengthProgression.spokenSetsSummary(count: totalSets, minReps: minReps, maxReps: maxReps)
    }
}

enum SplitDayState {
    case done
    case today
    case upcoming
    case missed
    case rest
}

@Observable
final class WorkoutHomeViewModel {
    private static let logger = Logger(subsystem: "com.majdarow.Vora", category: "Workout")

    private(set) var profile: UserProfile?
    private(set) var splitDays: [SplitDay] = []
    /// Dates, not sessions: this outlives the History screen, where a
    /// session can be deleted, and is read before the next reload.
    private var weekSessionDates: [Date] = []
    private(set) var personalRecords: [PersonalRecord] = []

    /// Monday-based index of today (0 = Monday).
    var todayIndex: Int {
        (Calendar.current.component(.weekday, from: .now) + 5) % 7
    }

    var todaySplitDay: SplitDay? {
        splitDays.first { $0.dayIndex == todayIndex }
    }

    var trainingSplit: TrainingSplit {
        profile?.trainingSplit ?? .fullBody
    }

    /// Today's template for a new session; empty on rest days. Falls back
    /// to the built-in default when the saved template can't be read, so
    /// a session can always start.
    func templatePlan(context: ModelContext) -> [TemplateExerciseSpec] {
        guard let day = todaySplitDay, !day.isRest else { return [] }
        do {
            return try WorkoutTemplateService.plan(for: trainingSplit, dayIndex: todayIndex, context: context)
        } catch {
            Self.logger.error("Failed to load today's template: \(String(describing: error), privacy: .public)")
            return WorkoutTemplateService.defaultPlan(for: trainingSplit, dayIndex: todayIndex)
        }
    }

    var hasTrainedToday: Bool {
        weekSessionDates.contains { Calendar.current.isDateInToday($0) }
    }

    // MARK: - Loading

    func load(from context: ModelContext) {
        profile = try? context.fetch(FetchDescriptor<UserProfile>()).first
        loadSplitDays(from: context)
        loadWeekSessions(from: context)
        personalRecords = Self.computePersonalRecords(from: context, limit: 5)
    }

    /// Seeds the 7-day structure from the profile's split template the
    /// first time the workout tab loads.
    private func loadSplitDays(from context: ModelContext) {
        let descriptor = FetchDescriptor<SplitDay>(sortBy: [SortDescriptor(\.dayIndex)])
        let existing = (try? context.fetch(descriptor)) ?? []
        if existing.count == 7 {
            splitDays = existing
            return
        }

        existing.forEach(context.delete)
        let template = (profile?.trainingSplit ?? .fullBody).weeklyTemplate
        for (index, day) in template.enumerated() {
            context.insert(SplitDay(
                dayIndex: index,
                title: day.title,
                muscleGroups: day.muscleGroups,
                isRest: day.isRest
            ))
        }
        try? context.save()
        splitDays = (try? context.fetch(descriptor)) ?? []
    }

    private func loadWeekSessions(from context: ModelContext) {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: .now)
        guard let weekStart = cal.date(byAdding: .day, value: -todayIndex, to: todayStart),
              let weekEnd = cal.date(byAdding: .day, value: 7, to: weekStart)
        else { return }

        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.date >= weekStart && $0.date < weekEnd },
            sortBy: [SortDescriptor(\.date)]
        )
        do {
            weekSessionDates = try context.fetch(descriptor).map(\.date)
        } catch {
            Self.logger.error("Failed to fetch this week's sessions: \(String(describing: error), privacy: .public)")
            weekSessionDates = []
        }
    }

    // MARK: - Week states

    func state(for day: SplitDay) -> SplitDayState {
        let trained = weekSessionDates.contains {
            (Calendar.current.component(.weekday, from: $0) + 5) % 7 == day.dayIndex
        }
        if trained { return .done }
        if day.isRest { return .rest }
        if day.dayIndex == todayIndex { return .today }
        return day.dayIndex > todayIndex ? .upcoming : .missed
    }

    // MARK: - Personal records

    /// Best completed weight per exercise across all history; reps and
    /// date come from the set that achieved it, set totals and the rep
    /// range from the session that achieved it.
    static func computePersonalRecords(from context: ModelContext, limit: Int? = nil) -> [PersonalRecord] {
        let sessions: [WorkoutSession]
        do {
            sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        } catch {
            logger.error("Failed to fetch sessions for PRs: \(String(describing: error), privacy: .public)")
            return []
        }
        var best: [String: (record: PersonalRecord, session: WorkoutSession)] = [:]

        for session in sessions {
            for exercise in session.exercises {
                for set in exercise.sets where set.isCompleted && set.weightKg > 0 && set.reps > 0 {
                    let key = exercise.matchKey
                    let current = best[key]?.record
                    let isBetter = current == nil
                        || set.weightKg > current!.weightKg
                        || (set.weightKg == current!.weightKg && set.reps > current!.reps)
                    if isBetter {
                        best[key] = (PersonalRecord(
                            exerciseName: exercise.displayName,
                            weightKg: set.weightKg,
                            reps: set.reps,
                            date: session.date,
                            exerciseId: ExerciseLibrary.definition(id: key).map(\.id)
                        ), session)
                    }
                }
            }
        }

        let records = best.values.map { record, session in
            var record = record
            let key = record.id
            let reps = session.exercises
                .filter { $0.matchKey == key }
                .flatMap(\.sets)
                .filter { $0.isCompleted && $0.weightKg > 0 && $0.reps > 0 }
                .map(\.reps)
            record.totalSets = reps.count
            record.minReps = reps.min() ?? 0
            record.maxReps = reps.max() ?? 0
            return record
        }

        let sorted = records.sorted { $0.weightKg > $1.weightKg }
        if let limit { return Array(sorted.prefix(limit)) }
        return sorted
    }
}
