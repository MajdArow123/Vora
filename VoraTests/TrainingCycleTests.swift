//
//  TrainingCycleTests.swift
//  VoraTests
//
//  Created by Majd Arow on 2026-11-03.
//

import Foundation
import SwiftData
import Testing
import UserNotifications
@testable import Vora

private nonisolated let calendar = Calendar.current

/// A fixed Monday noon, so results don't depend on when the suite runs.
private nonisolated let monday: Date = {
    var components = DateComponents(year: 2026, month: 11, day: 2, hour: 12)
    components.calendar = calendar
    return calendar.date(from: components)!
}()

private nonisolated func day(_ offset: Int) -> Date {
    calendar.date(byAdding: .day, value: offset, to: monday)!
}

// MARK: - The pure rules

struct CycleEngineTests {
    private let a = CycleEngine.Entry(id: UUID(), isRest: false)
    private let b = CycleEngine.Entry(id: UUID(), isRest: false)
    private let c = CycleEngine.Entry(id: UUID(), isRest: false)
    private let rest1 = CycleEngine.Entry(id: UUID(), isRest: true)
    private let rest2 = CycleEngine.Entry(id: UUID(), isRest: true)

    @Test func advancingMovesToTheNextEntryAndWraps() {
        let entries = [a, b, c]
        #expect(CycleEngine.advanced(from: a.id, in: entries, viaSession: true, today: monday, calendar: calendar)?.currentID == b.id)
        #expect(CycleEngine.advanced(from: c.id, in: entries, viaSession: true, today: monday, calendar: calendar)?.currentID == a.id)
    }

    @Test func advancingFromAnUnknownDayDoesNothing() {
        #expect(CycleEngine.advanced(from: UUID(), in: [a, b], viaSession: true, today: monday, calendar: calendar) == nil)
    }

    @Test func aRestReachedByFinishingAppliesTomorrow() throws {
        let position = try #require(CycleEngine.advanced(from: a.id, in: [a, rest1, b], viaSession: true, today: monday, calendar: calendar))
        #expect(position.currentID == rest1.id)
        #expect(position.restDay == calendar.startOfDay(for: day(1)))
    }

    @Test func aRestReachedBySkippingAppliesToday() throws {
        let position = try #require(CycleEngine.advanced(from: a.id, in: [a, rest1, b], viaSession: false, today: monday, calendar: calendar))
        #expect(position.restDay == calendar.startOfDay(for: monday))
    }

    @Test func aRestStaysThroughItsOwnDay() {
        let position = CycleEngine.Position(currentID: rest1.id, restDay: calendar.startOfDay(for: day(1)))
        // The evening of the session, and the rest day itself.
        #expect(CycleEngine.settled(position, in: [a, rest1, b], today: monday, calendar: calendar) == position)
        #expect(CycleEngine.settled(position, in: [a, rest1, b], today: day(1), calendar: calendar) == position)
    }

    @Test func aPassedRestSettlesToTheNextTrainingDay() {
        let position = CycleEngine.Position(currentID: rest1.id, restDay: calendar.startOfDay(for: monday))
        let settled = CycleEngine.settled(position, in: [a, rest1, b], today: day(1), calendar: calendar)
        #expect(settled == CycleEngine.Position(currentID: b.id, restDay: nil))
    }

    @Test func consecutiveRestsPassOnePerDay() {
        let entries = [a, rest1, rest2, b]
        let start = CycleEngine.Position(currentID: rest1.id, restDay: calendar.startOfDay(for: monday))
        let oneDayLater = CycleEngine.settled(start, in: entries, today: day(1), calendar: calendar)
        #expect(oneDayLater == CycleEngine.Position(currentID: rest2.id, restDay: calendar.startOfDay(for: day(1))))
        #expect(CycleEngine.settled(start, in: entries, today: day(2), calendar: calendar).currentID == b.id)
    }

    @Test func aLongGapStopsAtTheFirstTrainingDay() {
        let start = CycleEngine.Position(currentID: rest1.id, restDay: calendar.startOfDay(for: monday))
        let settled = CycleEngine.settled(start, in: [a, rest1, b, c], today: day(30), calendar: calendar)
        #expect(settled.currentID == b.id)
    }

    @Test func settlingTwiceChangesNothing() {
        let start = CycleEngine.Position(currentID: rest1.id, restDay: calendar.startOfDay(for: monday))
        let once = CycleEngine.settled(start, in: [a, rest1, rest2, b], today: day(1), calendar: calendar)
        #expect(CycleEngine.settled(once, in: [a, rest1, rest2, b], today: day(1), calendar: calendar) == once)
    }

    @Test func anAllRestCycleCantLoopForever() {
        let start = CycleEngine.Position(currentID: rest1.id, restDay: calendar.startOfDay(for: monday))
        let settled = CycleEngine.settled(start, in: [rest1, rest2], today: day(30), calendar: calendar)
        #expect(settled.currentID != nil)
        #expect(CycleEngine.nextTraining(from: rest1.id, in: [rest1, rest2]) == nil)
    }

    @Test func aMissingCurrentDayFallsBackToTheFirst() {
        let settled = CycleEngine.settled(CycleEngine.Position(currentID: UUID()), in: [a, b], today: monday, calendar: calendar)
        #expect(settled.currentID == a.id)
    }

    @Test func nextTrainingLooksPastRestAndWraps() {
        #expect(CycleEngine.nextTraining(from: rest1.id, in: [a, b, rest1])?.id == a.id)
        #expect(CycleEngine.nextTraining(from: b.id, in: [a, b, rest1])?.id == b.id)
    }

    @Test func numbersCountTrainingDaysOnly() {
        let entries = [a, rest1, b]
        #expect(CycleEngine.dayNumber(of: b.id, in: entries) == 2)
        #expect(CycleEngine.dayNumber(of: rest1.id, in: entries) == nil)
    }

    @Test func namesUseTheTitleWhenThereIsOne() {
        #expect(CycleEngine.displayName(number: 2, title: "Pull") == "Day 2 · Pull")
        #expect(CycleEngine.displayName(number: 2, title: "  ") == "Day 2")
    }

    @Test func restAllowanceIsAtLeastTwoAndCoversTheLongestRunAroundTheWrap() {
        #expect(CycleEngine.restAllowance(in: [a, b]) == 2)
        #expect(CycleEngine.restAllowance(in: [a, rest1, rest2]) == 2)
        let rest3 = CycleEngine.Entry(id: UUID(), isRest: true)
        #expect(CycleEngine.restAllowance(in: [rest1, a, rest2, rest3]) == 3)
    }
}

// MARK: - The cycle streak

struct CycleStreakTests {
    private func streak(_ offsets: [Int], allowance: Int = 2, today: Int = 0) -> Int {
        StreakCalculator.cycleStreak(
            sessionDates: offsets.map(day),
            restAllowance: allowance,
            today: day(today),
            calendar: calendar
        )
    }

    @Test func untrainedDaysWithinTheAllowanceCarry() {
        // Trained -3, -1 rests carry: -3, -2, -1.
        #expect(streak([-3]) == 3)
    }

    @Test func oneDayBeyondTheAllowanceBreaks() {
        #expect(streak([-4]) == 0)
        // -3 carries back through -1, then -4 extends it; -10 is too far.
        #expect(streak([-10, -4, -3]) == 4)
    }

    @Test func restAloneCantBuildAStreak() {
        #expect(streak([]) == 0)
    }

    @Test func todayIsAGraceDay() {
        #expect(streak([-1]) == 1)
        #expect(streak([-1, 0]) == 2)
        #expect(streak([0]) == 1)
    }

    @Test func aBiggerAllowanceFollowsTheCyclesOwnRests() {
        #expect(streak([-4], allowance: 2) == 0)
        #expect(streak([-4], allowance: 3) == 4)
    }

    @Test func aRunOfSessionsAndGapsAllCounts() {
        #expect(streak([-6, -4, -1], allowance: 2) == 6)
    }
}

// MARK: - The store

@MainActor
struct TrainingProgramServiceTests {
    private let container: ModelContainer
    private let context: ModelContext

    init() throws {
        container = try PersistenceController.makeContainer(inMemory: true)
        context = container.mainContext
    }

    private func seedWeek(_ split: TrainingSplit = .ppl) throws {
        context.insert(UserProfile(
            name: "Test", dateOfBirth: day(-10_000), heightCm: 180, biologicalSex: .male,
            goalType: .maintain, activityLevel: .moderatelyActive, trainingSplit: split,
            dailyCalorieTarget: 2500, proteinTargetG: 160, carbsTargetG: 280, fatTargetG: 70
        ))
        for (index, weekday) in split.weeklyTemplate.enumerated() {
            context.insert(SplitDay(dayIndex: index, title: weekday.title, muscleGroups: weekday.muscleGroups, isRest: weekday.isRest))
        }
        try context.save()
    }

    private func today(_ now: Date = monday) throws -> CycleToday {
        try #require(try TrainingProgramService.today(context: context, now: now))
    }

    private func program() throws -> TrainingProgram {
        try #require(try TrainingProgramService.program(context: context))
    }

    // MARK: Mode switching

    @Test func noProgramRowReadsAsWeekly() throws {
        #expect(try TrainingProgramService.mode(context: context) == .weekly)
        #expect(try TrainingProgramService.today(context: context) == nil)
    }

    @Test func switchingToWeeklyWithNoProgramWritesNothing() throws {
        try TrainingProgramService.setMode(.weekly, context: context)
        #expect(try context.fetchCount(FetchDescriptor<TrainingProgram>()) == 0)
    }

    @Test func trainingDaysMapInOrderWithRestsDropped() throws {
        try seedWeek(.upperLower)
        try TrainingProgramService.setMode(.cycle, context: context)
        let cycle = try today()
        #expect(cycle.days.map(\.name) == ["Day 1 · Upper", "Day 2 · Lower", "Day 3 · Upper", "Day 4 · Lower"])
        #expect(cycle.current.number == 1)
        #expect(cycle.days[0].muscleGroups.contains("chest"))
    }

    @Test func mappingCarriesSavedTemplatesAndDefaults() throws {
        try seedWeek(.ppl)
        let saved = TemplateExerciseSpec(exerciseId: "dip", targetSets: 5, repRangeMin: 5, repRangeMax: 7, targetRIR: 1, restSeconds: 150)
        try WorkoutTemplateService.save([saved], for: .ppl, dayIndex: 0, context: context)

        try TrainingProgramService.setMode(.cycle, context: context)
        let days = try today().days

        let first = try WorkoutTemplateService.plan(for: days[0].slot, context: context)
        #expect(first.map(\.exerciseId) == ["dip"])
        #expect(first[0].targetSets == 5)
        #expect(first[0].restSeconds == 150)
        #expect(first[0].id != saved.id)

        let second = try WorkoutTemplateService.plan(for: days[1].slot, context: context)
        #expect(second.map(\.exerciseId) == WorkoutTemplateService.defaultExerciseIDs(for: .ppl, dayIndex: 1))
    }

    @Test func customRowsWinOverTheBuiltInWeek() throws {
        try seedWeek(.ppl)
        let tuesday = try #require(try context.fetch(FetchDescriptor<SplitDay>()).first { $0.dayIndex == 1 })
        tuesday.isRest = true
        try context.save()
        try TrainingProgramService.setMode(.cycle, context: context)
        #expect(try today().days.count == 5)
    }

    @Test func unseededRowsFallBackToTheSplit() throws {
        context.insert(UserProfile(
            name: "Test", dateOfBirth: day(-10_000), heightCm: 180, biologicalSex: .male,
            goalType: .maintain, activityLevel: .moderatelyActive, trainingSplit: .fullBody,
            dailyCalorieTarget: 2500, proteinTargetG: 160, carbsTargetG: 280, fatTargetG: 70
        ))
        try TrainingProgramService.setMode(.cycle, context: context)
        #expect(try today().days.count == 3)
    }

    @Test func anAllRestSplitStartsWithOneEmptyDay() throws {
        try seedWeek(.custom)
        try TrainingProgramService.setMode(.cycle, context: context)
        let cycle = try today()
        #expect(cycle.days.map(\.name) == ["Day 1"])
        #expect(try WorkoutTemplateService.plan(for: cycle.current.slot, context: context).isEmpty)
    }

    @Test func switchingBackLeavesWeeklyTemplatesAndRowsIntact() throws {
        try seedWeek(.ppl)
        let weeklySpec = TemplateExerciseSpec(exerciseId: "dip", targetSets: 5)
        try WorkoutTemplateService.save([weeklySpec], for: .ppl, dayIndex: 0, context: context)

        try TrainingProgramService.setMode(.cycle, context: context)
        let slot = try today().days[0].slot
        try WorkoutTemplateService.save([TemplateExerciseSpec(exerciseId: "pull-up")], for: slot, context: context)
        try TrainingProgramService.setMode(.weekly, context: context)

        let weekly = try WorkoutTemplateService.plan(for: .ppl, dayIndex: 0, context: context)
        #expect(weekly.map(\.exerciseId) == ["dip"])
        #expect(weekly[0].id == weeklySpec.id)
        #expect(weekly[0].targetSets == 5)
        let rows = try context.fetch(FetchDescriptor<SplitDay>())
        #expect(rows.count == 7)
        #expect(rows.first { $0.dayIndex == 0 }?.title == "Push")
        #expect(try TrainingProgramService.today(context: context) == nil)
    }

    @Test func weeklyEditsDontLeakIntoTheCycle() throws {
        try seedWeek(.ppl)
        try TrainingProgramService.setMode(.cycle, context: context)
        let slot = try today().days[0].slot
        let before = try WorkoutTemplateService.plan(for: slot, context: context).map(\.exerciseId)
        try WorkoutTemplateService.save([TemplateExerciseSpec(exerciseId: "dip")], for: .ppl, dayIndex: 0, context: context)
        #expect(try WorkoutTemplateService.plan(for: slot, context: context).map(\.exerciseId) == before)
    }

    @Test func switchingBackToCycleResumesCycleAndPosition() throws {
        try seedWeek(.ppl)
        try TrainingProgramService.setMode(.cycle, context: context)
        let ids = try today().days.map(\.id)
        try TrainingProgramService.skip(context: context, now: monday)
        let slot = try today().days[0].slot
        try WorkoutTemplateService.save([TemplateExerciseSpec(exerciseId: "dip")], for: slot, context: context)

        try TrainingProgramService.setMode(.weekly, context: context)
        try TrainingProgramService.setMode(.cycle, context: context)

        let cycle = try today()
        #expect(cycle.days.map(\.id) == ids)
        #expect(cycle.current.id == ids[1])
        #expect(try WorkoutTemplateService.plan(for: slot, context: context).map(\.exerciseId) == ["dip"])
    }

    @Test func rebuildReplacesTheCycleAndKeepsWeeklyTemplates() throws {
        try seedWeek(.ppl)
        try WorkoutTemplateService.save([TemplateExerciseSpec(exerciseId: "dip")], for: .ppl, dayIndex: 0, context: context)
        try TrainingProgramService.setMode(.cycle, context: context)
        let old = try today().days.map(\.id)
        try TrainingProgramService.skip(context: context, now: monday)

        try TrainingProgramService.rebuildFromWeekly(context: context)

        let cycle = try today()
        #expect(Set(cycle.days.map(\.id)).isDisjoint(with: old))
        #expect(cycle.current.number == 1)
        #expect(try context.fetchCount(FetchDescriptor<CycleDay>()) == 6)
        #expect(try WorkoutTemplateService.plan(for: .ppl, dayIndex: 0, context: context).map(\.exerciseId) == ["dip"])
    }

    @Test func weeklySlotLookupsNeverMatchCycleTemplates() throws {
        try seedWeek(.ppl)
        try TrainingProgramService.setMode(.cycle, context: context)
        #expect(try WorkoutTemplateService.template(for: .ppl, dayIndex: 0, context: context) == nil)
        #expect(try !WorkoutTemplateService.isCustomized(for: .ppl, dayIndex: 0, context: context))
    }

    // MARK: Moving through

    @Test func skipAdvancesOneAndWraps() throws {
        try seedWeek(.upperLower)
        try TrainingProgramService.setMode(.cycle, context: context)
        for _ in 0..<3 { try TrainingProgramService.skip(context: context, now: monday) }
        #expect(try today().current.number == 4)
        try TrainingProgramService.skip(context: context, now: monday)
        #expect(try today().current.number == 1)
    }

    @Test func skipLogsNoSession() throws {
        try seedWeek(.ppl)
        try TrainingProgramService.setMode(.cycle, context: context)
        try TrainingProgramService.skip(context: context, now: monday)
        #expect(try context.fetchCount(FetchDescriptor<WorkoutSession>()) == 0)
    }

    @Test func skipIsANoOpInWeeklyMode() throws {
        try seedWeek(.ppl)
        try TrainingProgramService.skip(context: context, now: monday)
        #expect(try context.fetchCount(FetchDescriptor<TrainingProgram>()) == 0)
    }

    @Test func aPassedRestIsStoredByASettle() throws {
        try seedWeek(.fullBody)
        try TrainingProgramService.setMode(.cycle, context: context)
        let rest = try TrainingProgramService.addDay(isRest: true, context: context)
        try TrainingProgramService.setNext(dayID: rest, context: context, now: monday)
        #expect(try today(monday).current.isRest)
        #expect(try today(day(1)).current.number == 1)

        #expect(try program().currentDayID == rest)
        TrainingProgramService.settle(context: context, now: day(1))
        #expect(try program().currentDayID != rest)
        #expect(try program().restDay == nil)
    }

    @Test func aRestEntryCanBeSkipped() throws {
        try seedWeek(.fullBody)
        try TrainingProgramService.setMode(.cycle, context: context)
        let rest = try TrainingProgramService.addDay(isRest: true, context: context)
        try TrainingProgramService.setNext(dayID: rest, context: context, now: monday)
        try TrainingProgramService.skip(context: context, now: monday)
        #expect(try today().current.number == 1)
    }

    // MARK: Editing

    @Test func reorderKeepsTheNextDay() throws {
        try seedWeek(.ppl)
        try TrainingProgramService.setMode(.cycle, context: context)
        let ids = try today().days.map(\.id)
        try TrainingProgramService.setNext(dayID: ids[2], context: context, now: monday)
        try TrainingProgramService.reorder(dayIDs: [ids[2]] + ids[0..<2] + ids[3...], context: context)
        let cycle = try today()
        #expect(cycle.current.id == ids[2])
        #expect(cycle.current.number == 1)
        #expect(cycle.days.map(\.id)[1] == ids[0])
    }

    @Test func addingADayKeepsTheNextDayAndGivesItAnEmptyTemplate() throws {
        try seedWeek(.fullBody)
        try TrainingProgramService.setMode(.cycle, context: context)
        let current = try today().current.id
        let added = try TrainingProgramService.addDay(isRest: false, context: context)
        let cycle = try today()
        #expect(cycle.current.id == current)
        #expect(cycle.days.last?.id == added)
        #expect(cycle.days.last?.name == "Day 4")
        #expect(try WorkoutTemplateService.plan(for: TemplateSlot(cycleDayID: added), context: context).isEmpty)
    }

    @Test func aRestEntryHasNoTemplateAndDoesntShiftNumbers() throws {
        try seedWeek(.fullBody)
        try TrainingProgramService.setMode(.cycle, context: context)
        let ids = try today().days.map(\.id)
        let rest = try TrainingProgramService.addDay(isRest: true, context: context)
        try TrainingProgramService.reorder(dayIDs: [ids[0], rest, ids[1], ids[2]], context: context)
        let cycle = try today()
        #expect(cycle.days.map(\.name) == ["Day 1 · Full Body", "Rest", "Day 2 · Full Body", "Day 3 · Full Body"])
        #expect(try context.fetch(FetchDescriptor<CycleDay>()).first { $0.id == rest }?.template == nil)
    }

    @Test func removingTheNextDayHandsOverAndDeletesItsTemplate() throws {
        try seedWeek(.fullBody)
        try TrainingProgramService.setMode(.cycle, context: context)
        let ids = try today().days.map(\.id)
        try TrainingProgramService.remove(dayID: ids[0], context: context, now: monday)
        let cycle = try today()
        #expect(cycle.current.id == ids[1])
        #expect(cycle.current.number == 1)
        #expect(try context.fetchCount(FetchDescriptor<WorkoutTemplate>()) == 2)
    }

    @Test func removingTheLastDayInOrderWrapsToTheFirst() throws {
        try seedWeek(.fullBody)
        try TrainingProgramService.setMode(.cycle, context: context)
        let ids = try today().days.map(\.id)
        try TrainingProgramService.setNext(dayID: ids[2], context: context, now: monday)
        try TrainingProgramService.remove(dayID: ids[2], context: context, now: monday)
        #expect(try today().current.id == ids[0])
    }

    @Test func removingAnotherDayKeepsTheNextDay() throws {
        try seedWeek(.fullBody)
        try TrainingProgramService.setMode(.cycle, context: context)
        let ids = try today().days.map(\.id)
        try TrainingProgramService.remove(dayID: ids[2], context: context, now: monday)
        #expect(try today().current.id == ids[0])
    }

    @Test func theLastTrainingDayCantBeRemoved() throws {
        try seedWeek(.custom)
        try TrainingProgramService.setMode(.cycle, context: context)
        let only = try today().current.id
        _ = try TrainingProgramService.addDay(isRest: true, context: context)
        #expect(throws: CycleEditError.lastTrainingDay) {
            try TrainingProgramService.remove(dayID: only, context: context, now: monday)
        }
        #expect(try context.fetchCount(FetchDescriptor<CycleDay>()) == 2)
    }

    @Test func aRestEntryCanAlwaysBeRemoved() throws {
        try seedWeek(.custom)
        try TrainingProgramService.setMode(.cycle, context: context)
        let rest = try TrainingProgramService.addDay(isRest: true, context: context)
        try TrainingProgramService.remove(dayID: rest, context: context, now: monday)
        #expect(try context.fetchCount(FetchDescriptor<CycleDay>()) == 1)
    }

    @Test func renamingUpdatesTheDayAndItsTemplate() throws {
        try seedWeek(.fullBody)
        try TrainingProgramService.setMode(.cycle, context: context)
        let row = try #require(try program().orderedDays.first)
        TrainingProgramService.rename(row, to: "Heavy")
        #expect(row.template?.name == "Heavy")
        #expect(try today().days[0].name == "Day 1 · Heavy")
    }

    @Test func settingAMissingDayAsNextFails() throws {
        try seedWeek(.fullBody)
        try TrainingProgramService.setMode(.cycle, context: context)
        #expect(throws: CycleEditError.dayNotFound) {
            try TrainingProgramService.setNext(dayID: UUID(), context: context, now: monday)
        }
    }

    @Test func theDemoCycleSeedLinksDayOne() throws {
        try seedWeek(.ppl)
        try DemoSeeder.seedCycle(into: context)
        let plan = try WorkoutTemplateService.plan(for: try today(.now).current.slot, context: context)
        #expect(plan[0].supersetGroup == 1)
        #expect(plan[1].supersetGroup == 1)
        #expect(plan[2].supersetGroup == nil)
    }
}

// MARK: - Finishing a session

@MainActor
struct CycleSessionTests {
    private let container: ModelContainer
    private let context: ModelContext

    init() throws {
        container = try PersistenceController.makeContainer(inMemory: true)
        context = container.mainContext
        for (index, weekday) in TrainingSplit.upperLower.weeklyTemplate.enumerated() {
            context.insert(SplitDay(dayIndex: index, title: weekday.title, muscleGroups: weekday.muscleGroups, isRest: weekday.isRest))
        }
        context.insert(UserProfile(
            name: "Test", dateOfBirth: day(-10_000), heightCm: 180, biologicalSex: .male,
            goalType: .maintain, activityLevel: .moderatelyActive, trainingSplit: .upperLower,
            dailyCalorieTarget: 2500, proteinTargetG: 160, carbsTargetG: 280, fatTargetG: 70
        ))
        try context.save()
        try TrainingProgramService.setMode(.cycle, context: context)
    }

    private func today(_ now: Date = monday) throws -> CycleToday {
        try #require(try TrainingProgramService.today(context: context, now: now))
    }

    private func session(for slot: TemplateSlot?, completed: Bool = true, type: SetType = .normal) -> ActiveSessionViewModel {
        let vm = ActiveSessionViewModel(
            sessionName: "Session",
            templateSlot: slot,
            health: NoHealthWrites(),
            now: { monday }
        )
        vm.prefill(with: [TemplateExerciseSpec(exerciseId: "dip", targetSets: 1)], context: context)
        if completed {
            vm.exercises[0].sets[0].setWeight(kg: 50)
            vm.exercises[0].sets[0].repsText = "8"
            vm.exercises[0].sets[0].setType = type
            vm.exercises[0].sets[0].isCompleted = true
        }
        return vm
    }

    @Test func finishingTheNextDayAdvances() throws {
        let cycle = try today()
        session(for: cycle.current.slot).finish(context: context)
        #expect(try today().current.id == cycle.days[1].id)
        #expect(try context.fetchCount(FetchDescriptor<WorkoutSession>()) == 1)
    }

    @Test func finishingTheLastDayWraps() throws {
        let days = try today().days
        try TrainingProgramService.setNext(dayID: days[3].id, context: context, now: monday)
        session(for: days[3].slot).finish(context: context)
        #expect(try today().current.id == days[0].id)
    }

    @Test func finishingADifferentDayAdvancesFromThere() throws {
        let days = try today().days
        session(for: days[2].slot).finish(context: context)
        #expect(try today().current.id == days[3].id)
    }

    @Test func startingADifferentDayMovesNothingUntilItFinishes() throws {
        let days = try today().days
        _ = session(for: days[2].slot)
        #expect(try today().current.id == days[0].id)
    }

    @Test func aSecondSessionTheSameDayAdvancesAgain() throws {
        let days = try today().days
        session(for: days[0].slot).finish(context: context)
        session(for: days[1].slot).finish(context: context)
        #expect(try today().current.id == days[2].id)
    }

    @Test func discardingLeavesThePosition() throws {
        let cycle = try today()
        let vm = session(for: cycle.current.slot)
        vm.discardDraft()
        #expect(try today().current.id == cycle.current.id)
    }

    @Test func nothingCompletedLeavesThePosition() throws {
        let cycle = try today()
        session(for: cycle.current.slot, completed: false).finish(context: context)
        #expect(try today().current.id == cycle.current.id)
    }

    @Test func onlyWarmUpsLeaveThePositionButKeepTheSession() throws {
        let cycle = try today()
        session(for: cycle.current.slot, type: .warmUp).finish(context: context)
        #expect(try today().current.id == cycle.current.id)
        #expect(try context.fetchCount(FetchDescriptor<WorkoutSession>()) == 1)
    }

    @Test func aFailedSaveRestoresThePosition() throws {
        struct SaveFailed: Error {}
        let cycle = try today()
        session(for: cycle.current.slot).finish(context: context, save: { _ in throw SaveFailed() })
        #expect(try today().current.id == cycle.current.id)
    }

    @Test func aWeeklySlotDoesntMoveTheCycle() throws {
        let cycle = try today()
        session(for: TemplateSlot(split: .upperLower, dayIndex: 0)).finish(context: context)
        #expect(try today().current.id == cycle.current.id)
    }

    @Test func aRemovedDayStillSavesTheSessionWithoutAdvancing() throws {
        let days = try today().days
        let vm = session(for: days[2].slot)
        try TrainingProgramService.remove(dayID: days[2].id, context: context, now: monday)
        vm.finish(context: context)
        #expect(try today().current.id == days[0].id)
        #expect(try context.fetchCount(FetchDescriptor<WorkoutSession>()) == 1)
    }

    @Test func weeklyModeIgnoresALeftoverCycleSlot() throws {
        let cycle = try today()
        try TrainingProgramService.setMode(.weekly, context: context)
        session(for: cycle.current.slot).finish(context: context)
        try TrainingProgramService.setMode(.cycle, context: context)
        #expect(try today().current.id == cycle.current.id)
    }

    @Test func finishingIntoARestAppliesItTomorrow() throws {
        let days = try today().days
        let rest = try TrainingProgramService.addDay(isRest: true, context: context)
        try TrainingProgramService.reorder(
            dayIDs: [days[0].id, rest] + days[1...].map(\.id),
            context: context
        )
        session(for: days[0].slot).finish(context: context)
        #expect(try today(monday).current.isRest)
        #expect(try today(day(1)).current.isRest)
        #expect(try today(day(2)).current.id == days[1].id)
    }

    @Test func aResumedDraftAdvancesOnce() throws {
        let cycle = try today()
        let source = session(for: cycle.current.slot)
        let draft = source.snapshot()
        #expect(draft.version == ActiveSessionDraft.currentVersion)
        #expect(draft.templateSlot?.cycleDayID == cycle.current.id)

        let data = try JSONEncoder().encode(draft)
        let decoded = try JSONDecoder().decode(ActiveSessionDraft.self, from: data)
        let resumed = ActiveSessionViewModel(sessionName: "Session", health: NoHealthWrites(), now: { monday })
        resumed.restore(from: decoded, context: context)
        resumed.finish(context: context)

        #expect(try today().current.id == cycle.days[1].id)
    }

    @Test func aDraftWhoseDayWasRemovedStillFinishes() throws {
        let days = try today().days
        let draft = session(for: days[1].slot).snapshot()
        try TrainingProgramService.remove(dayID: days[1].id, context: context, now: monday)

        let resumed = ActiveSessionViewModel(sessionName: "Session", health: NoHealthWrites(), now: { monday })
        resumed.restore(from: draft, context: context)
        resumed.finish(context: context)

        #expect(try today().current.id == days[0].id)
        #expect(try context.fetchCount(FetchDescriptor<WorkoutSession>()) == 1)
    }

    @Test func aWidenedRangeSavesToTheCycleDayNotTheWeek() throws {
        let slot = try today().days[0].slot
        try WorkoutTemplateService.save(
            [TemplateExerciseSpec(exerciseId: "dip", repRangeMin: 8, repRangeMax: 12)], for: slot, context: context
        )
        let weeklyBefore = try WorkoutTemplateService.plan(for: .upperLower, dayIndex: 0, context: context).map(\.repRangeMax)

        let vm = ActiveSessionViewModel(sessionName: "Session", templateSlot: slot, health: NoHealthWrites(), now: { monday })
        vm.prefill(with: try WorkoutTemplateService.plan(for: slot, context: context), context: context)
        vm.applyFix(.widenRange(min: 8, max: 18), exerciseID: vm.exercises[0].id, context: context)

        #expect(try WorkoutTemplateService.plan(for: slot, context: context)[0].repRangeMax == 18)
        #expect(try WorkoutTemplateService.plan(for: .upperLower, dayIndex: 0, context: context).map(\.repRangeMax) == weeklyBefore)
    }
}

// MARK: - Consumers

@MainActor
struct CycleConsumerTests {
    /// Per test: Home caches its insight here, and these tests run in parallel.
    private let suiteName = "vora.tests.cycle-consumers.\(UUID().uuidString)"
    private let container: ModelContainer
    private let context: ModelContext
    private let defaults: UserDefaults

    init() throws {
        container = try PersistenceController.makeContainer(inMemory: true)
        context = container.mainContext
        defaults = try #require(UserDefaults(suiteName: suiteName))
        for (index, weekday) in TrainingSplit.ppl.weeklyTemplate.enumerated() {
            context.insert(SplitDay(dayIndex: index, title: weekday.title, muscleGroups: weekday.muscleGroups, isRest: weekday.isRest))
        }
        context.insert(UserProfile(
            name: "Test", dateOfBirth: day(-10_000), heightCm: 180, biologicalSex: .male,
            goalType: .maintain, activityLevel: .moderatelyActive, trainingSplit: .ppl,
            dailyCalorieTarget: 2500, proteinTargetG: 160, carbsTargetG: 280, fatTargetG: 70
        ))
        try context.save()
    }

    private func cycleMode() throws {
        try TrainingProgramService.setMode(.cycle, context: context)
    }

    private func insertSession(on date: Date, exerciseId: String = "dip") throws {
        let session = WorkoutSession(date: date, sessionName: "Session")
        context.insert(session)
        let log = ExerciseLog(exerciseName: "Dip", exerciseId: exerciseId, muscleGroups: ["chest"], orderIndex: 0)
        session.exercises.append(log)
        log.sets.append(SetEntry(setNumber: 1, weightKg: 50, reps: 8, isCompleted: true))
        try context.save()
    }

    private func home(now: Date = monday) -> HomeViewModel {
        let vm = HomeViewModel(defaults: defaults)
        vm.load(from: context, now: now)
        return vm
    }

    // MARK: Home

    @Test func homeWeeklyFollowsTheWeekday() {
        let vm = home()
        #expect(vm.cycleToday == nil)
        #expect(vm.todayTitle == "Push")
        #expect(vm.templateSlot == TemplateSlot(split: .ppl, dayIndex: 0))
        #expect(vm.workoutCardLabel == "Today's Workout")
    }

    @Test func homeCycleFollowsTheCycleOnAnyWeekday() throws {
        try cycleMode()
        try TrainingProgramService.skip(context: context, now: monday)
        // Sunday, a rest day in the week.
        let vm = home(now: day(6))
        #expect(vm.todayTitle == "Day 2 · Pull")
        #expect(vm.sessionName == "Day 2 · Pull")
        #expect(!vm.isRestToday)
        #expect(vm.todayMuscleGroups.contains("back"))
        #expect(vm.templateSlot.cycleDayID == vm.cycleToday?.days[1].id)
        #expect(vm.templatePlan(context: context).map(\.exerciseId) == WorkoutTemplateService.defaultExerciseIDs(for: .ppl, dayIndex: 1))
    }

    @Test func homeShowsUpNextAfterTraining() throws {
        try cycleMode()
        try insertSession(on: monday)
        let vm = home()
        #expect(vm.hasTrainedToday)
        #expect(vm.workoutCardLabel == "Up Next")
    }

    @Test func homeShowsARestEntry() throws {
        try cycleMode()
        let rest = try TrainingProgramService.addDay(isRest: true, context: context)
        try TrainingProgramService.setNext(dayID: rest, context: context, now: monday)
        let vm = home()
        #expect(vm.isRestToday)
        #expect(vm.todayTitle == "Rest")
        // Starting anyway opens the next training day.
        #expect(vm.sessionName == "Day 1 · Push")
    }

    @Test func homeSettlesAPassedRest() throws {
        try cycleMode()
        let rest = try TrainingProgramService.addDay(isRest: true, context: context)
        try TrainingProgramService.setNext(dayID: rest, context: context, now: monday)
        _ = home(now: day(1))
        #expect(try TrainingProgramService.program(context: context)?.currentDayID != rest)
    }

    // MARK: Train

    @Test func trainCycleCardAndSkip() throws {
        try cycleMode()
        let vm = WorkoutHomeViewModel()
        vm.load(from: context)
        #expect(vm.isCycleMode)
        #expect(vm.nextCycleDay?.name == "Day 1 · Push")
        #expect(vm.cycleProgressText == "Day 1 of 6")
        #expect(vm.templateSlot.cycleDayID == vm.nextCycleDay?.id)

        vm.skipCycleDay(context: context)
        #expect(vm.nextCycleDay?.name == "Day 2 · Pull")
        #expect(vm.cycleProgressText == "Day 2 of 6")
    }

    @Test func trainWeeklyIsUnchanged() throws {
        let vm = WorkoutHomeViewModel()
        vm.load(from: context)
        #expect(!vm.isCycleMode)
        #expect(vm.nextCycleDay == nil)
        #expect(vm.cycleProgressText == nil)
        #expect(vm.templateSlot == TemplateSlot(split: .ppl, dayIndex: vm.todayIndex))
    }

    // MARK: Week strip

    @Test func weekStripCycleNeverReadsMissedOrRest() throws {
        try cycleMode()
        let vm = WorkoutHomeViewModel()
        vm.load(from: context)
        for row in vm.splitDays {
            let state = vm.state(for: row)
            switch row.dayIndex {
            case vm.todayIndex: #expect(state == .today)
            case ..<vm.todayIndex: #expect(state == .open)
            default: #expect(state == .upcoming)
            }
        }
    }

    @Test func weekStripCycleMarksTrainedDays() throws {
        try cycleMode()
        try insertSession(on: .now)
        let vm = WorkoutHomeViewModel()
        vm.load(from: context)
        let today = try #require(vm.splitDays.first { $0.dayIndex == vm.todayIndex })
        #expect(vm.state(for: today) == .done)
    }

    @Test func weekStripWeeklyKeepsRestAndMissed() throws {
        let vm = WorkoutHomeViewModel()
        vm.load(from: context)
        // Sunday is the PPL rest day.
        let sunday = try #require(vm.splitDays.first { $0.dayIndex == 6 })
        #expect(vm.state(for: sunday) == .rest)
        if vm.todayIndex > 0 {
            let monday = try #require(vm.splitDays.first { $0.dayIndex == 0 })
            #expect(vm.state(for: monday) == .missed)
        }
    }

    // MARK: Streaks

    @Test func streakWeeklyBreaksOnAMissedTrainingDay() throws {
        // Friday's session is two days back; Saturday is an untrained training day.
        #expect(TrainingProgramService.streak(sessionDates: [day(-3)], context: context, now: monday) == 1)
    }

    @Test func streakCycleCarriesRestDaysInsteadOfScheduledOnes() throws {
        try cycleMode()
        #expect(TrainingProgramService.streak(sessionDates: [day(-3)], context: context, now: monday) == 3)
        #expect(TrainingProgramService.streak(sessionDates: [day(-4)], context: context, now: monday) == 0)
    }

    @Test func homeAndProgressAgreeOnTheCycleStreak() throws {
        try cycleMode()
        try insertSession(on: day(-3))
        try insertSession(on: day(-1))
        let progress = ProgressViewModel()
        progress.load(from: context, now: monday)
        #expect(home().streakDays == 3)
        #expect(progress.streakDays == 3)
    }

    // MARK: Insight

    private func missedWorkoutInsight(name: String?) -> Insight {
        let input = InsightInput(
            date: monday, hour: 12, proteinConsumedG: 0, proteinTargetG: 0, caloriesConsumed: 0, calorieTarget: 0,
            isScheduledWorkoutDay: true, hasTrainedToday: false, streakDays: 0, consecutiveDailyWeightsKg: [],
            daysTracked: 0, nextCycleDayName: name
        )
        return InsightEngine.generate(from: input)
    }

    @Test func insightWordingFollowsTheMode() {
        let weekly = missedWorkoutInsight(name: nil)
        #expect(weekly.rule == .missedWorkout)
        #expect(weekly.message.contains("scheduled training day"))
        let cycle = missedWorkoutInsight(name: "Day 2 · Pull")
        #expect(cycle.rule == .missedWorkout)
        #expect(cycle.message.contains("Next up: Day 2 · Pull"))
        #expect(!cycle.message.contains("scheduled"))
    }

    @Test func insightCycleWaitsForALapsedSession() throws {
        try cycleMode()
        try insertSession(on: day(-1))
        #expect(home().insight?.rule != .missedWorkout)
    }

    @Test func insightCycleAsksOnceTheLastSessionIsTwoDaysOld() throws {
        try cycleMode()
        try insertSession(on: day(-2))
        let insight = try #require(home().insight)
        #expect(insight.rule == .missedWorkout)
        #expect(insight.message.contains("Next up: Day 1 · Push"))
    }

    @Test func insightCycleStaysQuietOnARestEntry() throws {
        try cycleMode()
        try insertSession(on: day(-5))
        let rest = try TrainingProgramService.addDay(isRest: true, context: context)
        try TrainingProgramService.setNext(dayID: rest, context: context, now: monday)
        #expect(home().insight?.rule != .missedWorkout)
    }

    @Test func insightWeeklyStillFollowsTheWeekday() throws {
        try insertSession(on: day(-1))
        #expect(home().insight?.rule == .missedWorkout)
    }

    // MARK: Reminders

    private func workoutRequest(now: Date = monday.addingTimeInterval(-6 * 3600), minutes: Int = 18 * 60) throws -> (date: Date, body: String) {
        let request = try #require(NotificationService.reminderRequest(kind: .workout, context: context, minutes: minutes, now: now))
        let trigger = try #require(request.trigger as? UNCalendarNotificationTrigger)
        return (try #require(calendar.date(from: trigger.dateComponents)), request.content.body)
    }

    @Test func reminderWeeklySkipsRestDays() throws {
        // Sunday morning is a PPL rest day.
        let sundayMorning = day(6).addingTimeInterval(-6 * 3600)
        let reminder = try workoutRequest(now: sundayMorning)
        #expect(calendar.isDate(reminder.date, inSameDayAs: day(7)))
        #expect(reminder.body.contains("Push"))
    }

    @Test func reminderCycleFiresOnAnyDayAndNamesTheNextDay() throws {
        try cycleMode()
        try TrainingProgramService.skip(context: context, now: monday)
        let sundayMorning = day(6).addingTimeInterval(-6 * 3600)
        let reminder = try workoutRequest(now: sundayMorning)
        #expect(calendar.isDate(reminder.date, inSameDayAs: day(6)))
        #expect(reminder.body.contains("Day 2 · Pull"))
    }

    @Test func reminderCycleSkipsTodayOnARestEntryAndNamesWhatFollows() throws {
        try cycleMode()
        let rest = try TrainingProgramService.addDay(isRest: true, context: context)
        let morning = monday.addingTimeInterval(-6 * 3600)
        try TrainingProgramService.setNext(dayID: rest, context: context, now: morning)
        let reminder = try workoutRequest(now: morning)
        #expect(calendar.isDate(reminder.date, inSameDayAs: day(1)))
        #expect(reminder.body.contains("Day 1 · Push"))
    }

    @Test func reminderCycleWaitsUntilTomorrowOnceTrained() throws {
        try cycleMode()
        let morning = monday.addingTimeInterval(-6 * 3600)
        try insertSession(on: morning)
        let reminder = try workoutRequest(now: morning)
        #expect(calendar.isDate(reminder.date, inSameDayAs: day(1)))
    }

    @Test func weeklyReviewFollowsTheMode() throws {
        let weekly = NotificationService.shared.weeklySummaryContent(context: context, now: monday)
        #expect(weekly.body.contains("6 training days planned"))
        try cycleMode()
        let cycle = NotificationService.shared.weeklySummaryContent(context: context, now: monday)
        #expect(cycle.body.contains("Next up: Day 1 · Push"))
        #expect(!cycle.body.contains("training days planned"))
    }

    // MARK: No weekday logic: same in both modes

    private func levelsAndRecords() -> (sets: Double, records: [String]) {
        let levels = LevelsViewModel()
        levels.load(from: context, now: monday, calendar: calendar)
        let sets = levels.result.levels.reduce(0) { $0 + $1.setsPerWeek }
        let records = WorkoutHomeViewModel.computePersonalRecords(from: context).map(\.exerciseName)
        return (sets, records)
    }

    @Test func levelsAndRecordsDontDependOnTheMode() throws {
        try insertSession(on: day(-1))
        let weekly = levelsAndRecords()
        #expect(weekly.sets > 0)
        #expect(weekly.records == ["Dip"])
        try cycleMode()
        let cycle = levelsAndRecords()
        #expect(cycle.sets == weekly.sets)
        #expect(cycle.records == weekly.records)
    }

    @Test func deletingASessionDoesntRewindTheCycle() throws {
        try cycleMode()
        let days = try #require(try TrainingProgramService.today(context: context, now: monday)).days
        let vm = ActiveSessionViewModel(sessionName: "Session", templateSlot: days[0].slot, health: NoHealthWrites(), now: { monday })
        vm.prefill(with: [TemplateExerciseSpec(exerciseId: "dip", targetSets: 1)], context: context)
        vm.exercises[0].sets[0].setWeight(kg: 50)
        vm.exercises[0].sets[0].repsText = "8"
        vm.exercises[0].sets[0].isCompleted = true
        vm.finish(context: context)

        for session in try context.fetch(FetchDescriptor<WorkoutSession>()) { context.delete(session) }
        try context.save()

        #expect(try TrainingProgramService.today(context: context, now: monday)?.current.id == days[1].id)
    }
}

// MARK: - Superset links in templates

@MainActor
struct TemplateSupersetTests {
    private let container: ModelContainer
    private let context: ModelContext

    init() throws {
        container = try PersistenceController.makeContainer(inMemory: true)
        context = container.mainContext
    }

    private func spec(_ id: String, group: Int? = nil) -> TemplateExerciseSpec {
        TemplateExerciseSpec(exerciseId: id, supersetGroup: group)
    }

    @Test func linksSaveAndReadBack() throws {
        try WorkoutTemplateService.save(
            [spec("dip", group: 1), spec("pull-up", group: 1), spec("lateral-raise")],
            for: .ppl, dayIndex: 0, context: context
        )
        let plan = try WorkoutTemplateService.plan(for: .ppl, dayIndex: 0, context: context)
        #expect(plan.map(\.supersetGroup) == [1, 1, nil])
    }

    @Test func savingNormalizesBrokenGroups() throws {
        try WorkoutTemplateService.save(
            [spec("dip", group: 3), spec("lateral-raise"), spec("pull-up", group: 3), spec("face-pull", group: 7), spec("hammer-curl", group: 7)],
            for: .ppl, dayIndex: 0, context: context
        )
        let plan = try WorkoutTemplateService.plan(for: .ppl, dayIndex: 0, context: context)
        #expect(plan.map(\.supersetGroup) == [nil, nil, nil, 1, 1])
    }

    @Test func removingAMemberUnlinksTheOneLeftAlone() throws {
        let specs = [spec("dip", group: 1), spec("pull-up", group: 1)]
        try WorkoutTemplateService.save(specs, for: .ppl, dayIndex: 0, context: context)
        try WorkoutTemplateService.save([specs[0]], for: .ppl, dayIndex: 0, context: context)
        #expect(try WorkoutTemplateService.plan(for: .ppl, dayIndex: 0, context: context).map(\.supersetGroup) == [nil])
    }

    @Test func linkingMergesAndUnlinkingSplits() {
        #expect(SetCounting.linkingWithNext([nil, nil, nil], at: 0) == [1, 1, nil])
        #expect(SetCounting.linkingWithNext([1, 1, nil], at: 1) == [1, 1, 1])
        #expect(SetCounting.linkingWithNext([1, 1, 2, 2], at: 1) == [1, 1, 1, 1])
        #expect(SetCounting.linkingWithNext([nil], at: 0) == [nil])
        #expect(SetCounting.unlinking([1, 1, 1], at: 1) == [nil, nil, nil])
        #expect(SetCounting.unlinking([1, 1, 1, 1], at: 0) == [nil, 1, 1, 1])
        #expect(SetCounting.unlinking([1, 1], at: 5) == [1, 1])
    }

    @Test func prefillAppliesTheLinks() throws {
        let vm = ActiveSessionViewModel(sessionName: "Push", health: NoHealthWrites(), now: { monday })
        vm.prefill(with: [spec("dip", group: 1), spec("pull-up", group: 1), spec("lateral-raise")], context: context)
        #expect(vm.exercises.map(\.supersetGroup) == [1, 1, nil])
        #expect(vm.supersetPosition(of: vm.exercises[0].id) == .first)
        #expect(vm.supersetPosition(of: vm.exercises[1].id) == .last)
        #expect(vm.supersetPosition(of: vm.exercises[2].id) == nil)
    }

    @Test func prefillDropsALoneLink() throws {
        let vm = ActiveSessionViewModel(sessionName: "Push", health: NoHealthWrites(), now: { monday })
        vm.prefill(with: [spec("dip", group: 1), spec("pull-up")], context: context)
        #expect(vm.exercises.map(\.supersetGroup) == [nil, nil])
    }

    @Test func linksCopyIntoACycleDay() throws {
        for (index, weekday) in TrainingSplit.ppl.weeklyTemplate.enumerated() {
            context.insert(SplitDay(dayIndex: index, title: weekday.title, muscleGroups: weekday.muscleGroups, isRest: weekday.isRest))
        }
        try WorkoutTemplateService.save([spec("dip", group: 1), spec("pull-up", group: 1)], for: .fullBody, dayIndex: 0, context: context)
        try TrainingProgramService.setMode(.cycle, context: context)
        let first = try #require(try TrainingProgramService.today(context: context, now: monday)).days[0]
        #expect(try WorkoutTemplateService.plan(for: first.slot, context: context).map(\.supersetGroup) == [1, 1])
    }

    @Test func aWidenedRangeKeepsTheLinks() throws {
        let slot = TemplateSlot(split: .ppl, dayIndex: 0)
        try WorkoutTemplateService.save([spec("dip", group: 1), spec("pull-up", group: 1)], for: slot, context: context)
        let vm = ActiveSessionViewModel(sessionName: "Push", templateSlot: slot, health: NoHealthWrites(), now: { monday })
        vm.prefill(with: try WorkoutTemplateService.plan(for: slot, context: context), context: context)
        vm.applyFix(.widenRange(min: 8, max: 18), exerciseID: vm.exercises[0].id, context: context)
        let plan = try WorkoutTemplateService.plan(for: slot, context: context)
        #expect(plan[0].repRangeMax == 18)
        #expect(plan.map(\.supersetGroup) == [1, 1])
    }
}
