//
//  CalorieCyclingTests.swift
//  VoraTests
//
//  Created by Majd Arow on 2026-11-03.
//

import Foundation
import SwiftData
import Testing
@testable import Vora

@MainActor
struct CalorieCyclingPureTests {
    private typealias Kind = CalorieCycling.DayKind

    private static func week(training: Set<Int>) -> [Kind] {
        (0..<7).map { training.contains($0) ? .training : .rest }
    }

    private static func calories(base: Int = 2500, floor: Int = 1780, expected: Int? = nil, kinds: [Kind]) -> [Int] {
        CalorieCycling.dayCalories(
            baseCalories: base,
            floorCalories: floor,
            expectedTrainingDays: expected ?? kinds.count { $0 == .training },
            kinds: kinds
        )
    }

    // MARK: - Weekly totals

    @Test(arguments: 0...7)
    func aPlannedWeekAddsUpExactly(trainingDays: Int) {
        let kinds = Self.week(training: Set(0..<trainingDays))
        #expect(Self.calories(kinds: kinds).reduce(0, +) == 2500 * 7)
    }

    @Test(arguments: [2000, 2455, 2503, 3333])
    func theTotalHoldsForAnyBase(base: Int) {
        let kinds = Self.week(training: [0, 2, 4, 5])
        #expect(Self.calories(base: base, floor: 1200, kinds: kinds).reduce(0, +) == base * 7)
    }

    @Test func theTotalHoldsWhateverTheOrderOfDays() {
        for training in [Set([0, 1, 2, 3]), [3, 4, 5, 6], [0, 2, 4, 6], [6]] {
            #expect(Self.calories(kinds: Self.week(training: training)).reduce(0, +) == 2500 * 7)
        }
    }

    @Test(arguments: [0, 2, 4, 7])
    func theTotalHoldsWhenTrainingDiffersFromExpected(expected: Int) {
        for training in [Set<Int>(), [0], [1, 3, 5], [0, 1, 2, 3, 4, 5, 6]] {
            let result = Self.calories(floor: 1000, expected: expected, kinds: Self.week(training: training))
            #expect(result.reduce(0, +) == 2500 * 7, "expected \(expected), training \(training): \(result)")
        }
    }

    @Test func aPlannedWeekSplitsTrainingAboveRest() {
        let result = Self.calories(kinds: Self.week(training: [0, 2, 4, 5]))
        // Gap 250: rest is 2,500 − 4 × 250 / 7 ≈ 2,357, training 250 above it.
        #expect(abs(result[1] - 2357) <= 10)
        #expect(abs(result[0] - 2607) <= 10)
        #expect(abs(result[0] - result[1] - 250) <= 10)
    }

    @Test func theGapIsTenPercentOfTheBase() {
        #expect(CalorieCycling.dayGapFraction == 0.1)
    }

    @Test(arguments: [0, 7])
    func aWeekOfOnlyOneKindStaysOnTheBase(trainingDays: Int) {
        let result = Self.calories(kinds: Self.week(training: Set(0..<trainingDays)))
        #expect(result.allSatisfy { $0 == 2500 })
    }

    // MARK: - Stability

    @Test func aPastDaysNumberDoesntChangeAsTheWeekGoesOn() {
        let kinds = Self.week(training: [1, 3, 4])
        let whole = Self.calories(expected: 3, kinds: kinds)
        for count in 1...7 {
            #expect(Self.calories(expected: 3, kinds: Array(kinds.prefix(count))) == Array(whole.prefix(count)))
        }
    }

    // MARK: - Floors

    @Test func everyDayRespectsTheFloor() {
        for training in [Set<Int>(), [0], [0, 1, 2, 3, 4, 5], [6], [0, 1, 2]] {
            let result = Self.calories(base: 1900, floor: 1800, expected: 5, kinds: Self.week(training: training))
            #expect(result.allSatisfy { $0 >= 1800 }, "\(training): \(result)")
        }
    }

    @Test func aFloorThatBitesNarrowsTheGapAndKeepsTheTotal() {
        let result = Self.calories(base: 1900, floor: 1850, kinds: Self.week(training: [0, 1, 2, 3]))
        #expect(result.allSatisfy { $0 >= 1850 })
        #expect(result.reduce(0, +) == 1900 * 7)
        #expect(result[0] - result[6] < 190)
    }

    @Test func theFloorWinsOverTheTotalWhenTheyCantBothHold() {
        // Unexpected training days spend the week, and rounding leaves the last
        // days a few kcal short of the floor.
        let result = Self.calories(base: 1301, floor: 1200, expected: 0, kinds: Self.week(training: [0, 1, 2, 4]))
        #expect(result.allSatisfy { $0 >= 1200 })
        #expect(result.reduce(0, +) > 1301 * 7)
        #expect(result.reduce(0, +) <= 1301 * 7 + 10)
    }

    @Test(arguments: [1780, 1500])
    func aBaseAtOrBelowTheFloorDoesntCycle(base: Int) {
        let result = Self.calories(base: base, floor: 1780, kinds: Self.week(training: [0, 2, 4]))
        #expect(result.allSatisfy { $0 == base })
    }

    // MARK: - Macros

    @Test func proteinStaysAndTheRestScales() {
        let base = MacroTargets(calories: 2500, proteinG: 150, carbsG: 300, fatG: 70)
        let high = CalorieCycling.scaled(base, toCalories: 2750)
        #expect(high.calories == 2750)
        #expect(high.proteinG == 150)
        // Non-protein calories 1,900 → 2,150.
        #expect(high.carbsG == Int((300 * 2150 / 1900.0).rounded()))
        #expect(high.fatG == Int((70 * 2150 / 1900.0).rounded()))
        let low = CalorieCycling.scaled(base, toCalories: 2250)
        #expect(low.proteinG == 150)
        #expect(low.carbsG < 300)
        #expect(low.fatG < 70)
    }

    @Test func theBaseMapsToItself() {
        let base = MacroTargets(calories: 2500, proteinG: 150, carbsG: 300, fatG: 70)
        #expect(CalorieCycling.scaled(base, toCalories: 2500) == base)
    }

    @Test func proteinCoveringTheBaseLeavesMacrosAlone() {
        let base = MacroTargets(calories: 500, proteinG: 150, carbsG: 30, fatG: 10)
        let result = CalorieCycling.scaled(base, toCalories: 700)
        #expect(result.carbsG == 30)
        #expect(result.fatG == 10)
    }

    @Test func macrosOverAWeekMatchTheBaseWithinRounding() {
        let base = MacroTargets(calories: 2500, proteinG: 150, carbsG: 300, fatG: 70)
        let days = Self.calories(kinds: Self.week(training: [0, 2, 4, 5])).map { CalorieCycling.scaled(base, toCalories: $0) }
        #expect(days.allSatisfy { $0.proteinG == 150 })
        #expect(abs(days.reduce(0) { $0 + $1.carbsG } - 300 * 7) <= 7)
        #expect(abs(days.reduce(0) { $0 + $1.fatG } - 70 * 7) <= 7)
    }

    // MARK: - Notes

    @Test func dayNotesSayWhatKindOfDayItIs() {
        let targets = MacroTargets(calories: 2500, proteinG: 150, carbsG: 300, fatG: 70)
        #expect(CoachingExplanation.dayNote(DayTargets(targets: targets)) == nil)
        #expect(CoachingExplanation.dayNote(DayTargets(targets: targets, kind: .training)) == "Training day")
        #expect(CoachingExplanation.dayNote(DayTargets(targets: targets, kind: .rest)) == "Rest day")
        #expect(CoachingExplanation.dayNote(DayTargets(targets: targets, kind: .rest, ifTrainedCalories: 2700))?.contains(2700.formatted()) == true)
    }
}

/// Serialized because the setting lives in one shared defaults suite.
@MainActor
@Suite(.serialized)
struct CalorieCyclingServiceTests {
    private static let suiteName = "vora.tests.calorie-cycling"

    private let container: ModelContainer
    private let defaults: UserDefaults
    private let calendar: Calendar
    /// A Monday.
    private let weekStart: Date

    private var context: ModelContext { container.mainContext }

    init() throws {
        container = try PersistenceController.makeContainer(inMemory: true)
        defaults = try #require(UserDefaults(suiteName: Self.suiteName))
        defaults.removePersistentDomain(forName: Self.suiteName)
        defaults.set(true, forKey: CalorieCyclingSettings.storageKey)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        self.calendar = calendar
        weekStart = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 2)))
    }

    private func day(_ offset: Int) throws -> Date {
        try #require(calendar.date(byAdding: .day, value: offset, to: weekStart))
    }

    private func noon(_ offset: Int) throws -> Date {
        try day(offset).addingTimeInterval(12 * 3600)
    }

    @discardableResult
    private func insertProfile(calories: Int = 2500, weigh: Bool = true) throws -> UserProfile {
        let profile = UserProfile(
            name: "Test",
            dateOfBirth: try #require(calendar.date(byAdding: .year, value: -30, to: weekStart)),
            heightCm: 180,
            biologicalSex: .male,
            goalType: .fatLoss,
            activityLevel: .moderatelyActive,
            trainingSplit: .ppl,
            dailyCalorieTarget: calories,
            proteinTargetG: 160,
            carbsTargetG: 280,
            fatTargetG: 70
        )
        context.insert(profile)
        if weigh {
            // 80 kg, 180 cm, 30 years, male: a 1,780 kcal floor.
            context.insert(WeightEntry(date: try day(-1), weightKg: 80))
        }
        try context.save()
        return profile
    }

    private func insertWeeklySplit(training: Set<Int>) throws {
        for index in 0..<7 {
            context.insert(SplitDay(dayIndex: index, title: "Day", muscleGroups: [], isRest: !training.contains(index)))
        }
        try context.save()
    }

    private func insertCycle() throws {
        try insertWeeklySplit(training: [0, 2, 4])
        try TrainingProgramService.setMode(.cycle, context: context)
    }

    private func insertSession(dayOffset: Int, setType: SetType = .normal) throws {
        let session = WorkoutSession(date: try noon(dayOffset), sessionName: "S")
        context.insert(session)
        let log = ExerciseLog(exerciseName: "Barbell Bench Press", exerciseId: "barbell-bench-press", orderIndex: 0)
        session.exercises.append(log)
        log.sets.append(SetEntry(setNumber: 1, weightKg: 100, reps: 8, isCompleted: true, setType: setType))
        try context.save()
    }

    private func targets(
        _ profile: UserProfile,
        on offset: Int,
        now: Int? = nil,
        session: Date? = nil
    ) throws -> DayTargets {
        CalorieCyclingService.targets(
            on: try noon(offset),
            profile: profile,
            context: context,
            defaults: defaults,
            activeSessionStart: { session },
            now: try noon(now ?? offset),
            calendar: calendar
        )
    }

    // MARK: - Off and unavailable

    @Test func offByDefaultMeansTheProfileTargets() throws {
        let profile = try insertProfile()
        try insertWeeklySplit(training: [0, 2, 4])
        defaults.removeObject(forKey: CalorieCyclingSettings.storageKey)
        let result = try targets(profile, on: 0)
        #expect(result.targets == profile.baseTargets)
        #expect(result.kind == nil)
    }

    @Test func noWeighInMeansNoFloorAndNoCycling() throws {
        let profile = try insertProfile(weigh: false)
        try insertWeeklySplit(training: [0, 2, 4])
        let result = try targets(profile, on: 0)
        #expect(result.targets == profile.baseTargets)
        #expect(result.kind == nil)
    }

    @Test func aMissingSplitMeansNoCycling() throws {
        let profile = try insertProfile()
        #expect(try targets(profile, on: 0).kind == nil)
    }

    @Test func nothingIsEverWrittenToTheProfile() throws {
        let profile = try insertProfile()
        try insertWeeklySplit(training: [0, 2, 4])
        _ = try targets(profile, on: 0)
        #expect(profile.dailyCalorieTarget == 2500)
        #expect(profile.carbsTargetG == 280)
    }

    // MARK: - Weekly mode

    @Test func weeklyModeUsesThePlanAndKeepsTheTotal() throws {
        let profile = try insertProfile()
        try insertWeeklySplit(training: [0, 2, 4, 5])
        let week = try (0..<7).map { try targets(profile, on: $0) }
        #expect(week.map(\.kind) == [.training, .rest, .training, .rest, .training, .training, .rest])
        #expect(week.reduce(0) { $0 + $1.targets.calories } == 2500 * 7)
        #expect(week.allSatisfy { $0.targets.proteinG == 160 })
        #expect(week[0].targets.calories > week[1].targets.calories)
    }

    @Test func weeklyModeFollowsThePlanNotSessions() throws {
        let profile = try insertProfile()
        try insertWeeklySplit(training: [0, 2, 4])
        // Training on a planned rest day doesn't change the day's kind.
        try insertSession(dayOffset: 1)
        #expect(try targets(profile, on: 1).kind == .rest)
    }

    @Test func aFutureDayIsPlannedInWeeklyMode() throws {
        let profile = try insertProfile()
        try insertWeeklySplit(training: [0, 2, 4])
        let result = try targets(profile, on: 4, now: 0)
        #expect(result.kind == .training)
        #expect(result.targets.calories > 2500)
    }

    @Test func weeklyFloorAppliesEveryDay() throws {
        let profile = try insertProfile(calories: 1850)
        try insertWeeklySplit(training: [0, 1, 2, 3, 4, 5])
        let week = try (0..<7).map { try targets(profile, on: $0) }
        #expect(week.allSatisfy { $0.targets.calories >= 1780 })
        #expect(week.reduce(0) { $0 + $1.targets.calories } == 1850 * 7)
    }

    // MARK: - Cycle mode

    @Test func cycleModeKeepsTheTotalWhateverGetsTrained() throws {
        for training in [Set([0, 2, 4]), [], [6], [0, 1, 2, 3, 4, 5, 6], [1, 5]] {
            let container = try PersistenceController.makeContainer(inMemory: true)
            let test = try CalorieCyclingServiceTests(container: container)
            let profile = try test.insertProfile()
            try test.insertCycle()
            for dayOffset in training { try test.insertSession(dayOffset: dayOffset) }
            // The four weeks before this one trained 3 days a week.
            for week in 1...4 {
                for dayOffset in [0, 2, 4] { try test.insertSession(dayOffset: dayOffset - 7 * week) }
            }
            let week = try (0..<7).map { try test.targets(profile, on: $0, now: 6) }
            #expect(week.reduce(0) { $0 + $1.targets.calories } == 2500 * 7, "\(training)")
            #expect(week.map(\.kind) == (0..<7).map { training.contains($0) ? .training : .rest })
        }
    }

    private init(container: ModelContainer) throws {
        self.container = container
        defaults = try #require(UserDefaults(suiteName: Self.suiteName))
        defaults.set(true, forKey: CalorieCyclingSettings.storageKey)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        self.calendar = calendar
        weekStart = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 2)))
    }

    @Test func aNextCycleEntryAloneIsntATrainingDay() throws {
        let profile = try insertProfile()
        try insertCycle()
        let today = try TrainingProgramService.today(context: context, now: try noon(0), calendar: calendar)
        #expect(today?.current.isRest == false)
        #expect(try targets(profile, on: 0).kind == .rest)
    }

    @Test func aRestDayTellsYouWhatTrainingWouldMakeIt() throws {
        let profile = try insertProfile()
        try insertCycle()
        for week in 1...4 {
            for dayOffset in [0, 2, 4] { try insertSession(dayOffset: dayOffset - 7 * week) }
        }
        let rest = try targets(profile, on: 0)
        #expect(rest.kind == .rest)
        let trained = try targets(profile, on: 0, session: try noon(0))
        #expect(rest.ifTrainedCalories == trained.targets.calories)
        #expect(trained.targets.calories > rest.targets.calories)
    }

    @Test func startingASessionMakesTodayATrainingDayAndDiscardingUndoesIt() throws {
        let profile = try insertProfile()
        try insertCycle()
        let before = try targets(profile, on: 2)
        let during = try targets(profile, on: 2, session: try noon(2))
        let after = try targets(profile, on: 2)
        #expect(before.kind == .rest)
        #expect(during.kind == .training)
        #expect(during.ifTrainedCalories == nil)
        #expect(after == before)
    }

    @Test func aDraftFromAnotherDayDoesntCount() throws {
        let profile = try insertProfile()
        try insertCycle()
        #expect(try targets(profile, on: 2, session: try noon(1)).kind == .rest)
    }

    @Test func aFinishedSessionMakesTodayATrainingDay() throws {
        let profile = try insertProfile()
        try insertCycle()
        try insertSession(dayOffset: 3)
        #expect(try targets(profile, on: 3).kind == .training)
    }

    @Test func aWarmUpOnlySessionIsntATrainingDay() throws {
        let profile = try insertProfile()
        try insertCycle()
        try insertSession(dayOffset: 3, setType: .warmUp)
        #expect(try targets(profile, on: 3).kind == .rest)
    }

    @Test func aFutureCycleDayStaysOnTheBase() throws {
        let profile = try insertProfile()
        try insertCycle()
        let result = try targets(profile, on: 4, now: 1)
        #expect(result.targets == profile.baseTargets)
        #expect(result.kind == nil)
    }

    @Test func cycleFloorAppliesEveryDay() throws {
        let profile = try insertProfile(calories: 1850)
        try insertCycle()
        for week in 1...4 {
            for dayOffset in [0, 1, 2, 3, 4] { try insertSession(dayOffset: dayOffset - 7 * week) }
        }
        let week = try (0..<7).map { try targets(profile, on: $0, now: 6) }
        #expect(week.allSatisfy { $0.targets.calories >= 1780 })
    }

    // MARK: - View models

    @Test func homeShowsTheDaysTargetsWithCyclingOn() throws {
        try insertProfile()
        try insertWeeklySplit(training: [0, 2, 4])
        let vm = HomeViewModel(defaults: defaults, activeSessionStart: { nil })
        vm.load(from: context, now: try noon(0))
        #expect(vm.todayTargets.kind != nil)
        #expect(vm.dailyTargets == vm.todayTargets.targets)
        #expect(vm.remainingMacros.calories == vm.dailyTargets.calories)
    }

    @Test func homeShowsTheProfileTargetsWithCyclingOff() throws {
        let profile = try insertProfile()
        try insertWeeklySplit(training: [0, 2, 4])
        defaults.removeObject(forKey: CalorieCyclingSettings.storageKey)
        let vm = HomeViewModel(defaults: defaults, activeSessionStart: { nil })
        vm.load(from: context, now: try noon(0))
        #expect(vm.dailyTargets == profile.baseTargets)
    }

    @Test func theDiaryShowsTheProfileTargetsWithCyclingOff() throws {
        let profile = try insertProfile()
        defaults.removeObject(forKey: CalorieCyclingSettings.storageKey)
        let vm = FoodDiaryViewModel(defaults: defaults)
        vm.load(from: context)
        #expect(vm.calorieTarget == profile.dailyCalorieTarget)
        #expect(vm.carbsTarget == profile.carbsTargetG)
    }

    @Test func theDiaryShowsTheSelectedDaysTargetsWithCyclingOn() throws {
        let profile = try insertProfile()
        // Every weekday is a rest day but one: whichever today is, its target
        // differs from a flat week only if it's cycling.
        try insertWeeklySplit(training: [0, 1, 2, 3])
        let vm = FoodDiaryViewModel(defaults: defaults)
        vm.load(from: context)
        let expected = CalorieCyclingService.targets(on: vm.selectedDate, profile: profile, context: context, defaults: defaults)
        #expect(vm.calorieTarget == expected.targets.calories)
        #expect(vm.dayTargets?.kind != nil)
    }

    // MARK: - Discarding at launch

    /// A killed session's draft from today, in cycle mode with three training
    /// days a week, and Home already loaded with it.
    private func launchWithDraft(
        directory: URL,
        alert: RecordingRestAlert
    ) throws -> (home: HomeViewModel, launch: LaunchDraftViewModel, store: SessionDraftStore) {
        try insertProfile()
        try insertCycle()
        for week in 1...4 {
            for dayOffset in [0, 2, 4] { try insertSession(dayOffset: dayOffset - 7 * week) }
        }
        let now = try noon(0)
        let store = SessionDraftStore(directory: directory, now: { now })
        try store.save(ActiveSessionDraft(
            sessionName: "Push",
            startDate: now,
            savedAt: now,
            excludedSeconds: 0,
            exercises: [ActiveSessionDraft.Exercise(exerciseId: "barbell-bench-press", muscleGroups: [], restSeconds: 90, sets: [])]
        ))
        let home = HomeViewModel(defaults: defaults, activeSessionStart: { store.activeSessionStart() })
        home.load(from: context, now: now)
        let launch = LaunchDraftViewModel(store: store, alert: alert, now: { now })
        launch.check()
        return (home, launch, store)
    }

    @Test func discardingAtLaunchReloadsHomeToTheRestDayTarget() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "LaunchDiscard-\(UUID().uuidString)")
        defer { removeTestItem(at: directory) }
        let alert = RecordingRestAlert()
        let (home, launch, store) = try launchWithDraft(directory: directory, alert: alert)

        let training = home.todayTargets
        #expect(training.kind == .training)
        #expect(launch.draft != nil)

        launch.discard(home: home, context: context)

        #expect(home.todayTargets.kind == .rest)
        #expect(home.todayTargets.targets.calories < training.targets.calories)
        #expect(home.todayTargets.ifTrainedCalories == training.targets.calories)
        #expect(home.dailyTargets == home.todayTargets.targets)
        #expect(launch.draft == nil)
        #expect(store.activeSessionStart() == nil)
        #expect(!FileManager.default.fileExists(atPath: store.fileURL.path))
        #expect(alert.calls == [.cancel])
    }

    @Test func aLaunchDraftIsOfferedOnlyOnce() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "LaunchOffer-\(UUID().uuidString)")
        defer { removeTestItem(at: directory) }
        let alert = RecordingRestAlert()
        let (home, launch, store) = try launchWithDraft(directory: directory, alert: alert)

        // Dismissing the offer keeps the draft and its training-day target.
        launch.draft = nil
        launch.check()
        #expect(launch.draft == nil)
        #expect(store.activeSessionStart() != nil)
        #expect(home.todayTargets.kind == .training)
        #expect(alert.calls.isEmpty)
    }

    // MARK: - Draft peek

    @Test func peekingAtADraftLeavesEverythingInPlace() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "CalorieCyclingDraft-\(UUID().uuidString)")
        defer { removeTestItem(at: directory) }
        let start = try noon(0)
        let store = SessionDraftStore(directory: directory, now: { start.addingTimeInterval(60) })
        #expect(store.activeSessionStart() == nil)

        let draft = ActiveSessionDraft(
            sessionName: "Push",
            startDate: start,
            savedAt: start,
            excludedSeconds: 0,
            exercises: [ActiveSessionDraft.Exercise(exerciseId: "barbell-bench-press", muscleGroups: [], restSeconds: 90, sets: [])]
        )
        try store.save(draft)
        #expect(store.activeSessionStart() == start)

        let expired = SessionDraftStore(directory: directory, now: { start.addingTimeInterval(SessionDraftStore.maxAge + 1) })
        #expect(expired.activeSessionStart() == nil)
        #expect(FileManager.default.fileExists(atPath: store.fileURL.path))

        try Data("not json".utf8).write(to: store.fileURL)
        #expect(store.activeSessionStart() == nil)
        #expect(FileManager.default.fileExists(atPath: store.fileURL.path))
    }
}
