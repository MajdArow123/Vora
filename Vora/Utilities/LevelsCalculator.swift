//
//  LevelsCalculator.swift
//  Vora
//
//  Created by Majd Arow on 2026-11-02.
//

import Foundation

/// Average weekly sets per muscle. Pure: days are plain offsets and
/// exercises are plain values, so it knows nothing about dates or storage.
enum LevelsCalculator {
    /// A completed set counts in full for each muscle the exercise targets.
    static let primarySetWeight = 1.0
    /// Assisting muscles do less of the work, so a set counts for half.
    static let secondarySetWeight = 0.5
    static let daysPerWeek = 7

    /// Rolling window ending today, so there is never a partial calendar week.
    enum Range: Int, CaseIterable, Identifiable {
        case oneWeek = 1
        case fourWeeks = 4
        case twelveWeeks = 12

        var id: Int { rawValue }
        var weeks: Int { rawValue }
        var days: Int { weeks * LevelsCalculator.daysPerWeek }
        var displayName: String { "\(weeks)W" }
        /// "the last 4 weeks", for sentences.
        var phrase: String { weeks == 1 ? "the last week" : "the last \(weeks) weeks" }

        /// The longest range; how far back the data needs to reach.
        static let longestDays = Range.twelveWeeks.days
    }

    struct ExerciseMuscles: Equatable {
        let primary: Set<Muscle>
        let secondary: Set<Muscle>
    }

    struct CompletedSet: Equatable {
        /// `ExerciseIdentity.key`: the library ID, or a name-based key for
        /// custom exercises. Aliases are already resolved by this point.
        let exerciseKey: String
        let displayName: String
        /// Coarse `MuscleGroup` raw values stored with the log. Only used
        /// when the library doesn't know the exercise.
        let storedMuscleGroups: [String]
        /// Days from today: 0 is today, -1 is yesterday.
        let dayOffset: Int
    }

    enum Role: Equatable {
        case primary
        case secondary

        var setWeight: Double {
            switch self {
            case .primary: primarySetWeight
            case .secondary: secondarySetWeight
            }
        }
    }

    struct Contributor: Equatable, Identifiable {
        let exerciseKey: String
        let displayName: String
        let role: Role
        /// Sets actually logged, before the role's weight.
        let completedSets: Int
        let setsPerWeek: Double

        var id: String { exerciseKey }
    }

    struct MuscleLevel: Equatable, Identifiable {
        let muscle: Muscle
        let setsPerWeek: Double
        /// Largest share first.
        let contributors: [Contributor]

        var id: Muscle { muscle }
        var band: Band { Band(setsPerWeek: setsPerWeek) }
    }

    struct ExcludedExercise: Equatable, Identifiable {
        let exerciseKey: String
        let displayName: String
        let completedSets: Int

        var id: String { exerciseKey }
    }

    struct Result: Equatable {
        /// Every muscle, most sets first, then by name.
        let levels: [MuscleLevel]
        /// What the totals were divided by.
        let weeksAveraged: Double
        /// Custom exercises with no single muscle to count toward.
        let excluded: [ExcludedExercise]

        var excludedSetCount: Int { excluded.reduce(0) { $0 + $1.completedSets } }

        /// Whether anything was logged in the range, counted or not.
        var hasTraining: Bool {
            !excluded.isEmpty || levels.contains { !$0.contributors.isEmpty }
        }

        func level(for muscle: Muscle) -> MuscleLevel? {
            levels.first { $0.muscle == muscle }
        }

        /// Plain-English note about what wasn't counted; nil when nothing was left out.
        var excludedSummary: String? {
            guard !excluded.isEmpty else { return nil }
            let sets = LevelsCalculator.setCountText(excludedSetCount)
            return excluded.count == 1
                ? "1 custom exercise (\(sets)) isn't counted because it has no single muscle group."
                : "\(excluded.count) custom exercises (\(sets)) aren't counted because they have no single muscle group."
        }
    }

    /// "1 set", "24 sets".
    static func setCountText(_ count: Int) -> String {
        count == 1 ? "1 set" : "\(count) sets"
    }

    /// One decimal at most, ties away from zero: "12", "7.5", 23.25 is "23.3".
    /// A trace that would round to zero reads "<0.1", so it isn't mistaken for
    /// no sets.
    static func setsText(_ setsPerWeek: Double) -> String {
        if setsPerWeek > 0, setsPerWeek < 0.05 { return "<0.1" }
        return setsPerWeek.formatted(setsNumberStyle)
    }

    private static let setsNumberStyle = FloatingPointFormatStyle<Double>(locale: Locale(identifier: "en_US_POSIX"))
        .precision(.fractionLength(0...1))
        .rounded(rule: .toNearestOrAwayFromZero)
        .grouping(.never)

    /// Weekly-set bands for the body map colors. Lower bounds are inclusive.
    /// Deliberately separate from `LevelsGuideline`, so removing the guideline
    /// leaves the map unchanged.
    enum Band: Int, CaseIterable, Identifiable {
        case none, low, moderate, high, veryHigh

        static let moderateFrom = 5.0
        static let highFrom = 10.0
        static let veryHighFrom = 20.0

        /// Compares the value rounded the way it's shown, so the color always
        /// matches the number beside it. Any sets at all are at least `.low`.
        init(setsPerWeek: Double) {
            guard setsPerWeek > 0 else {
                self = .none
                return
            }
            let shown = (setsPerWeek * 10).rounded() / 10
            switch shown {
            case Self.veryHighFrom...: self = .veryHigh
            case Self.highFrom...: self = .high
            case Self.moderateFrom...: self = .moderate
            default: self = .low
            }
        }

        var id: Int { rawValue }

        var legendLabel: String {
            switch self {
            case .none: "0"
            case .low: "<5"
            case .moderate: "5–10"
            case .high: "10–20"
            case .veryHigh: "20+"
            }
        }
    }

    /// The muscle a coarse group means, when it means exactly one. Back,
    /// shoulders and core each cover several muscles that can't be told apart
    /// from the group alone, so guessing would invent data.
    static func unambiguousMuscle(forStoredGroup rawValue: String) -> Muscle? {
        switch MuscleGroup(rawValue: rawValue) {
        case .chest: .chest
        case .biceps: .biceps
        case .triceps: .triceps
        case .quads: .quads
        case .hamstrings: .hamstrings
        case .glutes: .glutes
        case .calves: .calves
        case .back, .shoulders, .core, nil: nil
        }
    }

    /// Whole weeks of the range, or fewer when training began inside it: the
    /// days since the first session count, so 30 days of history on a 12-week
    /// range isn't diluted by weeks before training began. At least one week,
    /// so a first session isn't scaled up into an impossible weekly rate.
    /// Layoffs after the first session do count, which keeps the average honest.
    static func weeksAveraged(range: Range, firstTrainingDay: Int?) -> Double {
        guard let firstTrainingDay else { return Double(range.weeks) }
        let daysSinceStart = min(range.days, 1 - firstTrainingDay)
        return max(1, Double(daysSinceStart) / Double(daysPerWeek))
    }

    /// - Parameters:
    ///   - sets: Completed sets; anything outside the range is ignored.
    ///   - library: Muscles per library exercise, by ID. A key it doesn't know
    ///     falls back to the stored muscle groups.
    ///   - firstTrainingDay: Offset of the first session ever, for when `sets`
    ///     only reaches back as far as the range. Defaults to the earliest set.
    static func calculate(
        sets: [CompletedSet],
        library: [String: ExerciseMuscles],
        range: Range,
        firstTrainingDay: Int? = nil
    ) -> Result {
        let firstDay = [firstTrainingDay, sets.map(\.dayOffset).min()].compactMap { $0 }.min()
        let weeks = weeksAveraged(range: range, firstTrainingDay: firstDay)
        let inRange = sets.filter { $0.dayOffset <= 0 && $0.dayOffset > -range.days }

        // Merged by key, keeping input order so the result is deterministic.
        var keys: [String] = []
        var setsByKey: [String: [CompletedSet]] = [:]
        for set in inRange {
            if setsByKey[set.exerciseKey] == nil { keys.append(set.exerciseKey) }
            setsByKey[set.exerciseKey, default: []].append(set)
        }

        var contributorsByMuscle: [Muscle: [Contributor]] = [:]
        var excluded: [ExcludedExercise] = []
        for key in keys {
            guard let exerciseSets = setsByKey[key], let first = exerciseSets.first else { continue }
            guard let muscles = library[key] ?? customMuscles(for: exerciseSets) else {
                excluded.append(ExcludedExercise(
                    exerciseKey: key,
                    displayName: first.displayName,
                    completedSets: exerciseSets.count
                ))
                continue
            }
            for (muscle, role) in roles(for: muscles) {
                contributorsByMuscle[muscle, default: []].append(Contributor(
                    exerciseKey: key,
                    displayName: first.displayName,
                    role: role,
                    completedSets: exerciseSets.count,
                    setsPerWeek: Double(exerciseSets.count) * role.setWeight / weeks
                ))
            }
        }

        let levels = Muscle.allCases.map { muscle in
            let contributors = (contributorsByMuscle[muscle] ?? []).sorted {
                ($0.setsPerWeek, $1.displayName) > ($1.setsPerWeek, $0.displayName)
            }
            return MuscleLevel(
                muscle: muscle,
                setsPerWeek: contributors.reduce(0) { $0 + $1.setsPerWeek },
                contributors: contributors
            )
        }.sorted {
            ($0.setsPerWeek, $1.muscle.displayName) > ($1.setsPerWeek, $0.muscle.displayName)
        }

        return Result(
            levels: levels,
            weeksAveraged: weeks,
            excluded: excluded.sorted {
                ($0.completedSets, $1.displayName) > ($1.completedSets, $0.displayName)
            }
        )
    }

    /// A custom exercise's stored groups as primary muscles. nil when there
    /// are none, or any can't be pinned to one muscle: counting only part of
    /// an exercise would understate it without saying so.
    private static func customMuscles(for sets: [CompletedSet]) -> ExerciseMuscles? {
        let groups = Set(sets.flatMap(\.storedMuscleGroups))
        guard !groups.isEmpty else { return nil }
        var muscles = Set<Muscle>()
        for group in groups {
            guard let muscle = unambiguousMuscle(forStoredGroup: group) else { return nil }
            muscles.insert(muscle)
        }
        return ExerciseMuscles(primary: muscles, secondary: [])
    }

    /// Primary wins if a muscle is ever listed in both.
    private static func roles(for muscles: ExerciseMuscles) -> [(Muscle, Role)] {
        muscles.primary.map { ($0, Role.primary) }
            + muscles.secondary.subtracting(muscles.primary).map { ($0, Role.secondary) }
    }
}
