//
//  StrengthProgression.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-25.
//

import Foundation

/// A single completed set, for per-session drill-down display.
struct SetDetail: Identifiable {
    let id = UUID()
    let setNumber: Int
    let weightKg: Double
    let reps: Int
}

/// Per-session best set for a single exercise.
struct ExerciseSessionStat: Identifiable {
    let id: UUID
    let date: Date
    let bestWeightKg: Double
    let bestReps: Int
    let completedSets: Int
    var isPR = false
    var sets: [SetDetail] = []

    /// Epley estimate.
    var estimatedOneRepMax: Double {
        bestWeightKg * (1 + Double(bestReps) / 30)
    }

    var setsSummary: String {
        StrengthProgression.setsSummary(count: completedSets, minReps: minReps, maxReps: maxReps)
    }

    var spokenSetsSummary: String {
        StrengthProgression.spokenSetsSummary(count: completedSets, minReps: minReps, maxReps: maxReps)
    }

    private var minReps: Int { sets.map(\.reps).min() ?? bestReps }
    private var maxReps: Int { sets.map(\.reps).max() ?? bestReps }
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
                completedSets: sets.count,
                sets: sets.sorted { $0.setNumber < $1.setNumber }
                    .map { SetDetail(setNumber: $0.setNumber, weightKg: $0.weightKg, reps: $0.reps) }
            ))
        }
        return stats
    }

    /// "4 sets × 10–12 reps" / "4 sets × 8 reps" / "1 set × 8 reps".
    static func setsSummary(count: Int, minReps: Int, maxReps: Int) -> String {
        "\(setsPart(count: count)) × \(repsPart(minReps: minReps, maxReps: maxReps))"
    }

    static func setsPart(count: Int) -> String {
        count == 1 ? "1 set" : "\(count) sets"
    }

    static func repsPart(minReps: Int, maxReps: Int) -> String {
        guard minReps == maxReps else { return "\(minReps)–\(maxReps) reps" }
        return maxReps == 1 ? "1 rep" : "\(maxReps) reps"
    }

    /// VoiceOver-friendly variant without symbols: "4 sets of 10 to 12 reps".
    static func spokenSetsSummary(count: Int, minReps: Int, maxReps: Int) -> String {
        let reps = minReps == maxReps
            ? (maxReps == 1 ? "1 rep" : "\(maxReps) reps")
            : "\(minReps) to \(maxReps) reps"
        return "\(setsPart(count: count)) of \(reps)"
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
