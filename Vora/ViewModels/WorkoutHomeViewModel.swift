//
//  WorkoutHomeViewModel.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import Foundation
import Observation
import SwiftData

struct PersonalRecord: Identifiable {
    let exerciseName: String
    let weightKg: Double
    let reps: Int
    let date: Date
    var totalSets: Int = 0
    var minReps: Int = 0
    var maxReps: Int = 0

    var id: String { exerciseName }

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
    private(set) var profile: UserProfile?
    private(set) var splitDays: [SplitDay] = []
    private(set) var weekSessions: [WorkoutSession] = []
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

    var hasTrainedToday: Bool {
        weekSessions.contains { Calendar.current.isDateInToday($0.date) }
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
        weekSessions = (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Week states

    func state(for day: SplitDay) -> SplitDayState {
        let trained = weekSessions.contains {
            (Calendar.current.component(.weekday, from: $0.date) + 5) % 7 == day.dayIndex
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
        let sessions = (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        var best: [String: (record: PersonalRecord, session: WorkoutSession)] = [:]

        for session in sessions {
            for exercise in session.exercises {
                for set in exercise.sets where set.isCompleted && set.weightKg > 0 && set.reps > 0 {
                    let key = exercise.exerciseName.lowercased()
                    let current = best[key]?.record
                    let isBetter = current == nil
                        || set.weightKg > current!.weightKg
                        || (set.weightKg == current!.weightKg && set.reps > current!.reps)
                    if isBetter {
                        best[key] = (PersonalRecord(
                            exerciseName: exercise.exerciseName,
                            weightKg: set.weightKg,
                            reps: set.reps,
                            date: session.date
                        ), session)
                    }
                }
            }
        }

        let records = best.values.map { record, session in
            var record = record
            let key = record.exerciseName.lowercased()
            let reps = session.exercises
                .filter { $0.exerciseName.lowercased() == key }
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
