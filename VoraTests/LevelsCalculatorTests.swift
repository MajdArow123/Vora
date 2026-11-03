//
//  LevelsCalculatorTests.swift
//  VoraTests
//
//  Created by Majd Arow on 2026-11-02.
//

import Foundation
import Testing
@testable import Vora

struct LevelsCalculatorTests {
    private typealias Calc = LevelsCalculator

    private let library: [String: LevelsCalculator.ExerciseMuscles] = [
        "bench": .init(primary: [.chest], secondary: [.frontDelts, .triceps]),
        "deadlift": .init(primary: [.glutes, .hamstrings, .lowerBack], secondary: [.quads, .lats]),
    ]

    private func sets(
        _ key: String,
        count: Int,
        day: Int = 0,
        name: String? = nil,
        groups: [String] = []
    ) -> [LevelsCalculator.CompletedSet] {
        Array(repeating: LevelsCalculator.CompletedSet(
            exerciseKey: key,
            displayName: name ?? key,
            storedMuscleGroups: groups,
            dayOffset: day
        ), count: count)
    }

    private func perWeek(_ result: LevelsCalculator.Result, _ muscle: Muscle) -> Double {
        result.level(for: muscle)?.setsPerWeek ?? -1
    }

    // MARK: - Weighting

    @Test func primaryCountsInFullAndSecondaryAsHalf() {
        let result = Calc.calculate(sets: sets("bench", count: 4), library: library, range: .oneWeek)
        #expect(perWeek(result, .chest) == 4)
        #expect(perWeek(result, .triceps) == 2)
        #expect(perWeek(result, .frontDelts) == 2)
        #expect(perWeek(result, .biceps) == 0)
    }

    @Test func multiMuscleExerciseCountsForEveryMuscle() {
        let result = Calc.calculate(sets: sets("deadlift", count: 2), library: library, range: .oneWeek)
        for muscle in [Muscle.glutes, .hamstrings, .lowerBack] {
            #expect(perWeek(result, muscle) == 2)
        }
        for muscle in [Muscle.quads, .lats] {
            #expect(perWeek(result, muscle) == 1)
        }
    }

    @Test func contributionsFromSeveralExercisesAddUp() {
        let library: [String: LevelsCalculator.ExerciseMuscles] = [
            "bench": .init(primary: [.chest], secondary: [.triceps]),
            "pushdown": .init(primary: [.triceps], secondary: []),
        ]
        let result = Calc.calculate(
            sets: sets("bench", count: 4) + sets("pushdown", count: 3),
            library: library,
            range: .oneWeek
        )
        #expect(perWeek(result, .triceps) == 5)

        let contributors = result.level(for: .triceps)?.contributors ?? []
        #expect(contributors.map(\.exerciseKey) == ["pushdown", "bench"])
        #expect(contributors.map(\.role) == [.primary, .secondary])
        #expect(contributors.map(\.completedSets) == [3, 4])
        #expect(contributors.map(\.setsPerWeek) == [3, 2])
    }

    @Test func primaryWinsWhenAMuscleIsListedTwice() {
        let library: [String: LevelsCalculator.ExerciseMuscles] = [
            "odd": .init(primary: [.chest], secondary: [.chest]),
        ]
        let result = Calc.calculate(sets: sets("odd", count: 2), library: library, range: .oneWeek)
        #expect(perWeek(result, .chest) == 2)
        #expect(result.level(for: .chest)?.contributors.count == 1)
    }

    // MARK: - Averaging

    @Test func averagesOverTheWholeRangeOnceHistoryCoversIt() {
        let input = (0..<12).flatMap { sets("bench", count: 3, day: -$0 * 7) }
        let result = Calc.calculate(sets: input, library: library, range: .fourWeeks, firstTrainingDay: -83)
        #expect(result.weeksAveraged == 4)
        #expect(perWeek(result, .chest) == 3)
    }

    @Test func windowEdgesAreRollingDaysIncludingToday() {
        let edge = sets("bench", count: 1, day: -27) + sets("bench", count: 1, day: 0)
        let outside = sets("bench", count: 5, day: -28)
        let result = Calc.calculate(sets: edge + outside, library: library, range: .fourWeeks)
        #expect(perWeek(result, .chest) == 2.0 / 4)
    }

    @Test func oneWeekWindowIsSevenDays() {
        let result = Calc.calculate(
            sets: sets("bench", count: 2, day: -6) + sets("bench", count: 9, day: -7),
            library: library,
            range: .oneWeek
        )
        #expect(perWeek(result, .chest) == 2)
    }

    @Test func historyShorterThanTheRangeDividesByTimeSinceFirstSession() {
        // 30 days of history (offsets -29...0) on a 12-week range.
        let result = Calc.calculate(sets: sets("bench", count: 30, day: -29), library: library, range: .twelveWeeks)
        #expect(result.weeksAveraged == 30.0 / 7)
        #expect(abs(perWeek(result, .chest) - 7) < 0.0001)
    }

    @Test func partialFirstWeekIsNotScaledUp() {
        // 6 sets in the first 2 days read as 6 a week, not 21.
        let result = Calc.calculate(sets: sets("bench", count: 6, day: -1), library: library, range: .fourWeeks)
        #expect(result.weeksAveraged == 1)
        #expect(perWeek(result, .chest) == 6)
    }

    @Test func firstSessionTodayAveragesOverOneWeek() {
        #expect(Calc.weeksAveraged(range: .twelveWeeks, firstTrainingDay: 0) == 1)
    }

    @Test func layoffsAfterTheFirstSessionStillCount() {
        // Trained 8 weeks ago and yesterday: the gap between stays in the average.
        let input = sets("bench", count: 8, day: -55) + sets("bench", count: 8, day: -1)
        let result = Calc.calculate(sets: input, library: library, range: .twelveWeeks)
        #expect(result.weeksAveraged == 8)
        #expect(perWeek(result, .chest) == 2)
    }

    @Test func firstTrainingDayBeforeTheFetchedSetsWins() {
        let result = Calc.calculate(
            sets: sets("bench", count: 4, day: -1),
            library: library,
            range: .fourWeeks,
            firstTrainingDay: -200
        )
        #expect(result.weeksAveraged == 4)
    }

    @Test func noHistoryAtAllUsesTheFullRange() {
        #expect(Calc.weeksAveraged(range: .fourWeeks, firstTrainingDay: nil) == 4)
    }

    @Test func futureSetsAreIgnored() {
        let result = Calc.calculate(sets: sets("bench", count: 3, day: 1), library: library, range: .oneWeek)
        #expect(!result.hasTraining)
    }

    // MARK: - Custom exercises

    @Test func customWithAnUnambiguousGroupCountsAsPrimary() {
        let result = Calc.calculate(
            sets: sets("custom:my press", count: 3, name: "My Press", groups: ["chest"]),
            library: library,
            range: .oneWeek
        )
        #expect(perWeek(result, .chest) == 3)
        #expect(result.level(for: .chest)?.contributors.first?.role == .primary)
        #expect(result.level(for: .chest)?.contributors.first?.displayName == "My Press")
        #expect(result.excluded.isEmpty)
    }

    @Test(arguments: MuscleGroup.allCases)
    func everyCoarseGroupIsEitherOneMuscleOrAmbiguous(group: MuscleGroup) {
        let muscle = Calc.unambiguousMuscle(forStoredGroup: group.rawValue)
        switch group {
        case .back, .shoulders, .core: #expect(muscle == nil)
        default: #expect(muscle?.rawValue == group.rawValue)
        }
    }

    @Test(arguments: [["back"], ["shoulders"], ["core"], ["not-a-group"], []])
    func customWithoutOneMuscleIsExcludedAndReported(groups: [String]) {
        let result = Calc.calculate(
            sets: sets("custom:thing", count: 4, name: "Thing", groups: groups),
            library: library,
            range: .oneWeek
        )
        #expect(result.levels.allSatisfy { $0.setsPerWeek == 0 })
        #expect(result.excluded.map(\.displayName) == ["Thing"])
        #expect(result.excludedSetCount == 4)
        #expect(result.hasTraining)
    }

    @Test func oneAmbiguousGroupExcludesTheWholeExercise() {
        let result = Calc.calculate(
            sets: sets("custom:mixed", count: 2, groups: ["chest", "back"]),
            library: library,
            range: .oneWeek
        )
        #expect(perWeek(result, .chest) == 0)
        #expect(result.excludedSetCount == 2)
    }

    @Test func customWithSeveralUnambiguousGroupsCountsForEach() {
        let result = Calc.calculate(
            sets: sets("custom:combo", count: 2, groups: ["biceps", "triceps", "biceps"]),
            library: library,
            range: .oneWeek
        )
        #expect(perWeek(result, .biceps) == 2)
        #expect(perWeek(result, .triceps) == 2)
    }

    @Test func customSetsMergeByKey() {
        let input = sets("custom:thing", count: 1, name: "Thing", groups: ["quads"])
            + sets("custom:thing", count: 2, name: "THING", groups: ["quads"])
        let result = Calc.calculate(sets: input, library: library, range: .oneWeek)
        #expect(result.level(for: .quads)?.contributors.count == 1)
        #expect(result.level(for: .quads)?.contributors.first?.completedSets == 3)
    }

    @Test func libraryDataBeatsStoredGroups() {
        let result = Calc.calculate(sets: sets("bench", count: 2, groups: ["back"]), library: library, range: .oneWeek)
        #expect(perWeek(result, .chest) == 2)
        #expect(result.excluded.isEmpty)
    }

    @Test func excludedOutsideTheRangeIsNotReported() {
        let result = Calc.calculate(sets: sets("custom:old", count: 3, day: -10), library: library, range: .oneWeek)
        #expect(result.excluded.isEmpty)
        #expect(!result.hasTraining)
    }

    @Test func excludedSummaryPluralizes() {
        let one = Calc.calculate(sets: sets("custom:a", count: 1), library: library, range: .oneWeek)
        #expect(one.excludedSummary == "1 custom exercise (1 set) isn't counted because it has no single muscle group.")

        let two = Calc.calculate(sets: sets("custom:a", count: 1) + sets("custom:b", count: 3), library: library, range: .oneWeek)
        #expect(two.excludedSummary == "2 custom exercises (4 sets) aren't counted because they have no single muscle group.")

        let none = Calc.calculate(sets: sets("bench", count: 1), library: library, range: .oneWeek)
        #expect(none.excludedSummary == nil)
    }

    // MARK: - Output

    @Test func everyMuscleIsListedMostSetsFirstThenByName() {
        let result = Calc.calculate(sets: sets("bench", count: 4), library: library, range: .oneWeek)
        #expect(result.levels.count == Muscle.allCases.count)
        #expect(result.levels.first?.muscle == .chest)
        // Front Delts and Triceps tie at 2, by name.
        #expect(result.levels.dropFirst().prefix(2).map(\.muscle) == [.frontDelts, .triceps])
        let untrained = result.levels.dropFirst(3).map(\.muscle.displayName)
        #expect(untrained == untrained.sorted())
    }

    @Test func emptyInputHasNoTraining() {
        let result = Calc.calculate(sets: [], library: library, range: .fourWeeks)
        #expect(!result.hasTraining)
        #expect(result.levels.allSatisfy { $0.setsPerWeek == 0 && $0.contributors.isEmpty })
        #expect(result.weeksAveraged == 4)
    }

    // MARK: - Bands and text

    @Test(arguments: [
        (0.0, LevelsCalculator.Band.none),
        (0.01, .low),
        (4.9, .low),
        (4.96, .moderate),
        (5.0, .moderate),
        (9.9, .moderate),
        (10.0, .high),
        (19.9, .high),
        (19.96, .veryHigh),
        (20.0, .veryHigh),
        (40.0, .veryHigh),
    ])
    func bandBoundaries(sets: Double, band: LevelsCalculator.Band) {
        #expect(LevelsCalculator.Band(setsPerWeek: sets) == band)
    }

    @Test(arguments: [
        (0.0, "0"),
        (0.04, "<0.1"),
        (0.05, "0.1"),
        (7.5, "7.5"),
        (12.0, "12"),
        (4.2857, "4.3"),
        (9.96, "10"),
    ])
    func setsTextTrimsAndRounds(value: Double, text: String) {
        #expect(LevelsCalculator.setsText(value) == text)
    }

    @Test func setsTextRoundsTiesAwayFromZero() {
        #expect(LevelsCalculator.setsText(23.25) == "23.3")
        #expect(LevelsCalculator.setsText(15.75) == "15.8")
    }

    /// The color has to agree with the number beside it, right at the ties.
    @Test(arguments: [
        (4.95, "5", LevelsCalculator.Band.moderate),
        (9.95, "10", .high),
        (19.95, "20", .veryHigh),
    ])
    func bandAgreesWithTheShownNumberAtTies(sets: Double, text: String, band: LevelsCalculator.Band) {
        #expect(LevelsCalculator.setsText(sets) == text)
        #expect(LevelsCalculator.Band(setsPerWeek: sets) == band)
    }

    @Test func setCountPluralizes() {
        #expect(Calc.setCountText(1) == "1 set")
        #expect(Calc.setCountText(24) == "24 sets")
    }

    @Test func guidelineIsTheSameBandForEveryMuscle() {
        for muscle in Muscle.allCases {
            #expect(LevelsGuideline.band(for: muscle) == 10...20)
        }
    }
}
