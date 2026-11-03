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
    /// Best Epley estimate across every set of the exercise.
    var bestE1RMKg: Double?

    /// Identity key shared by every log of this exercise (see ExerciseIdentity).
    var id: String { ExerciseIdentity.key(exerciseId: exerciseId, name: exerciseName) }

    /// The all-time best estimate, or this set's when none was computed.
    var estimatedOneRepMax: Double {
        bestE1RMKg ?? StrengthProgression.epley(weightKg: weightKg, repsToFailure: reps)
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
    /// A past untrained day in cycle mode: nothing was scheduled, so nothing
    /// was missed.
    case open
}

@Observable
final class WorkoutHomeViewModel {
    private static let logger = Logger(subsystem: "com.majdarow.Vora", category: "Workout")

    private(set) var profile: UserProfile?
    private(set) var splitDays: [SplitDay] = []
    /// Where the cycle stands; nil in weekly mode.
    private(set) var cycleToday: CycleToday?
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

    var isCycleMode: Bool {
        cycleToday != nil
    }

    /// The day a session started now is for; nil in weekly mode.
    var nextCycleDay: CycleDayInfo? {
        cycleToday?.nextTraining
    }

    /// "Day 2 of 4" for the next training day.
    var cycleProgressText: String? {
        guard let cycleToday, let number = cycleToday.nextTraining?.number else { return nil }
        return "Day \(number) of \(cycleToday.trainingDays.count)"
    }

    var templateSlot: TemplateSlot {
        nextCycleDay?.slot ?? TemplateSlot(split: trainingSplit, dayIndex: todayIndex)
    }

    /// Today's template for a new session; a missing day reads as rest, as
    /// it does on the Today card.
    func templatePlan(context: ModelContext) -> [TemplateExerciseSpec] {
        if let slot = nextCycleDay?.slot {
            return WorkoutTemplateService.sessionPlan(for: slot, context: context)
        }
        return WorkoutTemplateService.sessionPlan(
            isRestDay: todaySplitDay?.isRest ?? true,
            split: trainingSplit,
            dayIndex: todayIndex,
            context: context
        )
    }

    var hasTrainedToday: Bool {
        weekSessionDates.contains { Calendar.current.isDateInToday($0) }
    }

    // MARK: - Loading

    func load(from context: ModelContext) {
        do {
            profile = try context.fetch(FetchDescriptor<UserProfile>()).first
        } catch {
            Self.logger.error("Failed to fetch the user profile: \(String(describing: error), privacy: .public)")
        }
        loadSplitDays(from: context)
        TrainingProgramService.settle(context: context)
        cycleToday = TrainingProgramService.todayOrNil(context: context)
        loadWeekSessions(from: context)
        personalRecords = Self.computePersonalRecords(from: context, limit: 5)
    }

    /// Seeds the 7-day structure from the profile's split template the
    /// first time the workout tab loads.
    private func loadSplitDays(from context: ModelContext) {
        let descriptor = FetchDescriptor<SplitDay>(sortBy: [SortDescriptor(\.dayIndex)])
        let existing: [SplitDay]
        do {
            existing = try context.fetch(descriptor)
        } catch {
            // Not the same as having no days: reseeding here would delete them.
            Self.logger.error("Failed to fetch split days: \(String(describing: error), privacy: .public)")
            splitDays = []
            return
        }
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
        do {
            try context.save()
            splitDays = try context.fetch(descriptor)
        } catch {
            Self.logger.error("Failed to seed split days: \(String(describing: error), privacy: .public)")
            splitDays = []
        }
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

    /// "Skip to next day". On failure the position simply stays where it was.
    func skipCycleDay(context: ModelContext) {
        do {
            try TrainingProgramService.skip(context: context)
        } catch {
            Self.logger.error("Failed to skip the cycle day: \(String(describing: error), privacy: .public)")
        }
        load(from: context)
    }

    // MARK: - Week states

    func state(for day: SplitDay) -> SplitDayState {
        let trained = weekSessionDates.contains {
            (Calendar.current.component(.weekday, from: $0) + 5) % 7 == day.dayIndex
        }
        if trained { return .done }
        if isCycleMode {
            if day.dayIndex == todayIndex { return .today }
            return day.dayIndex > todayIndex ? .upcoming : .open
        }
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
        var bestE1RM: [String: Double] = [:]

        for session in sessions {
            for exercise in session.exercises {
                for set in exercise.sets where set.isCompleted && set.setType.countsTowardRecords && set.weightKg > 0 && set.reps > 0 {
                    let key = exercise.matchKey
                    bestE1RM[key] = max(
                        bestE1RM[key] ?? 0,
                        StrengthProgression.epley(weightKg: set.weightKg, repsToFailure: set.reps)
                    )
                    let isBetter = best[key].map { current in
                        set.weightKg > current.record.weightKg
                            || (set.weightKg == current.record.weightKg && set.reps > current.record.reps)
                    } ?? true
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
                .filter { $0.isCompleted && $0.setType.countsAsTrainingSet && $0.weightKg > 0 && $0.reps > 0 }
                .map(\.reps)
            record.totalSets = reps.count
            record.minReps = reps.min() ?? 0
            record.maxReps = reps.max() ?? 0
            record.bestE1RMKg = bestE1RM[key]
            return record
        }

        let sorted = records.sorted { $0.weightKg > $1.weightKg }
        if let limit { return Array(sorted.prefix(limit)) }
        return sorted
    }
}
