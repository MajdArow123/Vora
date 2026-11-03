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
    /// Logged RIR, else what the set type implies.
    var rir: Int? = nil
    var setType = SetType.normal
    var side: SetSide? = nil
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
        StrengthProgression.epley(weightKg: bestWeightKg, repsToFailure: bestReps)
    }

    var setsSummary: String {
        StrengthProgression.setsSummary(count: completedSets, minReps: minReps, maxReps: maxReps)
    }

    var spokenSetsSummary: String {
        StrengthProgression.spokenSetsSummary(count: completedSets, minReps: minReps, maxReps: maxReps)
    }

    private var trainingReps: [Int] { sets.filter(\.setType.countsAsTrainingSet).map(\.reps) }
    private var minReps: Int { trainingReps.min() ?? bestReps }
    private var maxReps: Int { trainingReps.max() ?? bestReps }
}

/// Pure aggregation over fetched sessions, shared by the exercise
/// history screen and the Progress tab's strength analytics.
enum StrengthProgression {
    /// Epley: estimated one-rep max from a load and the reps it could go to
    /// failure for.
    nonisolated static func epley(weightKg: Double, repsToFailure: Int) -> Double {
        weightKg * (1 + Double(repsToFailure) / 30)
    }

    /// Best completed set per session for the named exercise, resolved to
    /// its identity key (see ExerciseIdentity), oldest session first.
    static func sessionStats(
        for exerciseName: String,
        sessions: [WorkoutSession]
    ) -> [ExerciseSessionStat] {
        sessionStats(forKey: ExerciseIdentity.key(exerciseId: nil, name: exerciseName), sessions: sessions)
    }

    /// Best completed set per session for the exercise with the given
    /// identity key, oldest session first. A set qualifies when completed
    /// with positive weight and reps; the best set is the heaviest that can
    /// set a record, ties broken by higher reps. `sets` lists every qualifying
    /// set, and `completedSets` leaves warm-ups out.
    static func sessionStats(
        forKey key: String,
        sessions: [WorkoutSession]
    ) -> [ExerciseSessionStat] {
        var stats: [ExerciseSessionStat] = []

        for session in sessions.sorted(by: { $0.date < $1.date }) {
            let sets = session.exercises
                .filter { $0.matchKey == key }
                .flatMap(\.sets)
                .filter { $0.isCompleted && $0.weightKg > 0 && $0.reps > 0 }
            let eligible = sets.filter(\.setType.countsTowardRecords)
            guard var best = eligible.first else { continue }
            for set in eligible where set.weightKg > best.weightKg
                || (set.weightKg == best.weightKg && set.reps > best.reps) {
                best = set
            }
            stats.append(ExerciseSessionStat(
                id: session.id,
                date: session.date,
                bestWeightKg: best.weightKg,
                bestReps: best.reps,
                completedSets: sets.count(where: \.setType.countsAsTrainingSet),
                sets: sets.sorted { $0.setNumber < $1.setNumber }
                    .map {
                        SetDetail(
                            setNumber: $0.setNumber,
                            weightKg: $0.weightKg,
                            reps: $0.reps,
                            rir: $0.effectiveRIR,
                            setType: $0.setType,
                            side: $0.side
                        )
                    }
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

    /// Display names of distinct exercises (deduped by identity key, so
    /// renamed and legacy rows collapse into one) with at least one
    /// qualifying set, sorted alphabetically.
    static func distinctExerciseNames(in sessions: [WorkoutSession]) -> [String] {
        var seen: [String: String] = [:]
        for session in sessions {
            for exercise in session.exercises {
                let key = exercise.matchKey
                guard seen[key] == nil,
                      exercise.sets.contains(where: { $0.isCompleted && $0.setType.countsTowardRecords && $0.weightKg > 0 && $0.reps > 0 })
                else { continue }
                seen[key] = exercise.displayName
            }
        }
        return seen.values.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}

// MARK: - Personal records

/// A set as records see it: what was actually lifted. Records ignore RIR, so
/// a record is something that was done, and old sets without RIR compare
/// fairly.
struct RecordSet: Equatable {
    let weightKg: Double
    let reps: Int
}

enum PersonalRecordKind: String, CaseIterable {
    case weight
    case reps
    case estimatedOneRepMax
}

/// One record broken by a set of a session.
struct NewRecord: Equatable {
    let kind: PersonalRecordKind
    let weightKg: Double
    let reps: Int
}

/// An exercise's all-time bests.
struct ExerciseRecords: Equatable {
    struct RepBest: Equatable, Identifiable {
        let weightKg: Double
        let reps: Int

        var id: Double { weightKg }
    }

    var heaviest: RecordSet?
    var bestE1RMSet: RecordSet?
    /// Most reps at each weight, heaviest first.
    var repBests: [RepBest] = []

    var bestE1RMKg: Double? {
        bestE1RMSet.map { StrengthProgression.epley(weightKg: $0.weightKg, repsToFailure: $0.reps) }
    }
}

extension StrengthProgression {
    /// Finer than any real plate, and stable for a converted lb weight.
    private static func weightKey(_ kg: Double) -> Int { Int((kg * 1000).rounded()) }

    /// All-time bests from every qualifying set of one exercise. Reps at
    /// 0 kg count as a bodyweight rep best; weight and e1RM need a load.
    static func records(from sets: [RecordSet]) -> ExerciseRecords {
        var records = ExerciseRecords()
        var bestByWeight: [Int: ExerciseRecords.RepBest] = [:]
        for set in sets where set.reps > 0 && set.weightKg >= 0 {
            let key = weightKey(set.weightKg)
            if set.reps > bestByWeight[key]?.reps ?? 0 {
                bestByWeight[key] = .init(weightKg: set.weightKg, reps: set.reps)
            }
            guard set.weightKg > 0 else { continue }
            if let heaviest = records.heaviest {
                if set.weightKg > heaviest.weightKg || (set.weightKg == heaviest.weightKg && set.reps > heaviest.reps) {
                    records.heaviest = set
                }
            } else {
                records.heaviest = set
            }
            let value = epley(weightKg: set.weightKg, repsToFailure: set.reps)
            if value > records.bestE1RMKg ?? 0 {
                records.bestE1RMSet = set
            }
        }
        records.repBests = bestByWeight.values.sorted { $0.weightKg > $1.weightKg }
        return records
    }

    /// Records a session's sets broke against all prior sets of the exercise.
    /// A first log only counts for weight: rep and e1RM records need
    /// something to beat. A rep record is at a weight lifted before, and
    /// only the heaviest such weight is reported per exercise.
    static func newRecords(prior: [RecordSet], session: [RecordSet]) -> [NewRecord] {
        let before = records(from: prior)
        let now = records(from: session)
        var found: [NewRecord] = []

        if let heaviest = now.heaviest, heaviest.weightKg > before.heaviest?.weightKg ?? 0 {
            found.append(NewRecord(kind: .weight, weightKg: heaviest.weightKg, reps: heaviest.reps))
        }

        let priorReps = Dictionary(
            before.repBests.map { (weightKey($0.weightKg), $0.reps) },
            uniquingKeysWith: { first, _ in first }
        )
        if let best = now.repBests.first(where: { best in
            priorReps[weightKey(best.weightKg)].map { best.reps > $0 } ?? false
        }) {
            found.append(NewRecord(kind: .reps, weightKg: best.weightKg, reps: best.reps))
        }

        if let priorBest = before.bestE1RMKg, let set = now.bestE1RMSet, let value = now.bestE1RMKg, value > priorBest {
            found.append(NewRecord(kind: .estimatedOneRepMax, weightKg: set.weightKg, reps: set.reps))
        }
        return found
    }
}
