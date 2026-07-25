//
//  StrengthProgression.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-25.
//

import Foundation

/// Per-session best set for a single exercise.
struct ExerciseSessionStat: Identifiable {
    let id: UUID
    let date: Date
    let bestWeightKg: Double
    let bestReps: Int
    let completedSets: Int
    var isPR = false

    /// Epley estimate.
    var estimatedOneRepMax: Double {
        bestWeightKg * (1 + Double(bestReps) / 30)
    }
}

/// Pure aggregation over fetched sessions, shared by the exercise
/// history screen and the Progress tab's strength analytics.
enum StrengthProgression {
    /// Best completed set per session for the named exercise
    /// (case-insensitive), oldest session first. A set qualifies when
    /// completed with positive weight and reps; the best set is the
    /// heaviest, ties broken by higher reps.
    static func sessionStats(
        for exerciseName: String,
        sessions: [WorkoutSession]
    ) -> [ExerciseSessionStat] {
        let target = exerciseName.lowercased()
        var stats: [ExerciseSessionStat] = []

        for session in sessions.sorted(by: { $0.date < $1.date }) {
            let sets = session.exercises
                .filter { $0.exerciseName.lowercased() == target }
                .flatMap(\.sets)
                .filter { $0.isCompleted && $0.weightKg > 0 && $0.reps > 0 }
            guard var best = sets.first else { continue }
            for set in sets where set.weightKg > best.weightKg
                || (set.weightKg == best.weightKg && set.reps > best.reps) {
                best = set
            }
            stats.append(ExerciseSessionStat(
                id: session.id,
                date: session.date,
                bestWeightKg: best.weightKg,
                bestReps: best.reps,
                completedSets: sets.count
            ))
        }
        return stats
    }

    /// Distinct exercise names with at least one qualifying set,
    /// case-insensitively deduped (first-seen casing wins), sorted
    /// alphabetically.
    static func distinctExerciseNames(in sessions: [WorkoutSession]) -> [String] {
        var seen: [String: String] = [:]
        for session in sessions {
            for exercise in session.exercises {
                let key = exercise.exerciseName.lowercased()
                guard seen[key] == nil,
                      exercise.sets.contains(where: { $0.isCompleted && $0.weightKg > 0 && $0.reps > 0 })
                else { continue }
                seen[key] = exercise.exerciseName
            }
        }
        return seen.values.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}
