//
//  ExpenditureCheckInServiceTests.swift
//  VoraTests
//
//  Created by Majd Arow on 2026-11-02.
//

import Foundation
import SwiftData
import Testing
@testable import Vora

@MainActor
struct ExpenditureCheckInServiceTests {
    private let container: ModelContainer
    private let calendar: Calendar
    /// Monday noon.
    private let monday: Date

    private var context: ModelContext { container.mainContext }

    init() throws {
        container = try PersistenceController.makeContainer(inMemory: true)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        self.calendar = calendar
        monday = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 12)))
    }

    private func day(_ offset: Int, from date: Date? = nil) throws -> Date {
        let start = calendar.startOfDay(for: date ?? monday)
        return try #require(calendar.date(byAdding: .day, value: offset, to: start))
    }

    private func insertProfile(goal: GoalType = .fatLoss, activity: ActivityLevel = .moderatelyActive) throws {
        context.insert(UserProfile(
            name: "Test",
            dateOfBirth: try #require(calendar.date(byAdding: .year, value: -30, to: monday)),
            heightCm: 180,
            biologicalSex: .male,
            goalType: goal,
            activityLevel: activity,
            trainingSplit: .ppl,
            dailyCalorieTarget: 2000,
            proteinTargetG: 150,
            carbsTargetG: 200,
            fatTargetG: 60
        ))
    }

    /// `days` days ending the day before `end` (Monday by default), at a
    /// steady intake and rate, ending at 80 kg.
    private func insertHistory(
        days: Int = 21,
        kcal: Double = 2600,
        kgPerWeek: Double = -0.5,
        weighIns: Bool = true,
        food: Bool = true,
        end: Date? = nil
    ) throws {
        for offset in 1...days {
            let date = try day(-offset, from: end).addingTimeInterval(8 * 3600)
            if weighIns {
                context.insert(WeightEntry(date: date, weightKg: 80 - Double(offset) * kgPerWeek / 7))
            }
            if food {
                context.insert(FoodEntry(
                    date: date,
                    mealSlot: .lunch,
                    foodName: "Lunch",
                    servingGrams: 400,
                    calories: kcal,
                    proteinG: 100,
                    carbsG: 200,
                    fatG: 50
                ))
            }
        }
        try context.save()
    }

    private func state(now: Date? = nil, weekday: CheckInWeekday = .monday) throws -> WeeklyCheckInState {
        try ExpenditureCheckInService.state(context: context, weekday: weekday, now: now ?? monday, calendar: calendar)
    }

    private func proposal(now: Date? = nil) throws -> ExpenditureProposal {
        guard case .ready(let proposal) = try state(now: now) else {
            throw ProposalMissing()
        }
        return proposal
    }

    private struct ProposalMissing: Error {}

    private func profile() throws -> UserProfile {
        try #require(try context.fetch(FetchDescriptor<UserProfile>()).first)
    }

    // MARK: - When it's due

    @Test func checkInDayFindsTheMostRecentWeekday() throws {
        let today = try day(0)
        let tuesday = try day(1)
        let sunday = try day(-1)
        let lastWednesday = try day(-5)
        #expect(ExpenditureCheckInService.checkInDay(for: .monday, now: monday, calendar: calendar) == today)
        #expect(ExpenditureCheckInService.checkInDay(for: .monday, now: tuesday, calendar: calendar) == today)
        #expect(ExpenditureCheckInService.checkInDay(for: .sunday, now: monday, calendar: calendar) == sunday)
        #expect(ExpenditureCheckInService.checkInDay(for: .wednesday, now: monday, calendar: calendar) == lastWednesday)
    }

    @Test func noProfileMeansNotDue() throws {
        #expect(try state() == .notDue)
    }

    @Test func aMissedMondayStaysOpenLaterInTheWeek() throws {
        try insertProfile()
        try insertHistory()
        let friday = try day(4).addingTimeInterval(9 * 3600)
        let checkIn = try proposal(now: friday)
        let today = try day(0)
        #expect(checkIn.checkInDate == today)
    }

    @Test func answeringClosesItUntilTheNextCheckInDay() throws {
        try insertProfile()
        try insertHistory()
        try ExpenditureCheckInService.skip(try proposal(), context: context)
        #expect(try state() == .notDue)
        #expect(try state(now: try day(6)) == .notDue)
        guard case .ready = try state(now: try day(7).addingTimeInterval(3600)) else {
            Issue.record("Expected the next Monday to reopen it")
            return
        }
    }

    @Test func aCustomWeekdayIsRespected() throws {
        try insertProfile()
        try insertHistory()
        // No check-in day has passed since Wednesday's row.
        let wednesday = try day(2)
        context.insert(ExpenditureCheckIn(
            date: try day(-5),
            estimateKcal: 3000,
            rawEstimateKcal: 3000,
            avgIntakeKcal: 2600,
            slopeKgPerDay: 0,
            daysUsed: 21,
            applied: false
        ))
        try context.save()
        #expect(try state(now: try day(1), weekday: .wednesday) == .notDue)
        guard case .ready(let proposal) = try state(now: wednesday, weekday: .wednesday) else {
            Issue.record("Expected Wednesday's check-in to be open")
            return
        }
        #expect(proposal.checkInDate == wednesday)
    }

    @Test func weekdayDefaultsToMondayAndReadsTheSetting() throws {
        let defaults = try makeTestDefaults()
        #expect(CheckInWeekday.current(in: defaults) == .monday)
        defaults.set(CheckInWeekday.friday.rawValue, forKey: CheckInWeekday.storageKey)
        #expect(CheckInWeekday.current(in: defaults) == .friday)
    }

    // MARK: - Not enough data

    @Test func tooLittleDataExplainsWhatIsNeededOnTheDayItself() throws {
        try insertProfile()
        try insertHistory(days: 6)
        #expect(try state() == .needsMoreData(intakeDays: 6, neededIntakeDays: 10, weighIns: 6, neededWeighIns: 8))
    }

    @Test func tooLittleDataIsNotShownLaterInTheWeek() throws {
        try insertProfile()
        try insertHistory(days: 6)
        #expect(try state(now: try day(1)) == .notDue)
    }

    @Test func noWeighInsIsStillExplained() throws {
        try insertProfile()
        try insertHistory(days: 12, weighIns: false)
        #expect(try state() == .needsMoreData(intakeDays: 12, neededIntakeDays: 10, weighIns: 0, neededWeighIns: 8))
    }

    // MARK: - The proposal

    /// Formula at 80 kg, moderately active: 1780 × 1.55 ≈ 2759 before the
    /// trend's lag. The first update moves 150 toward 3150.
    @Test func firstCheckInStartsFromTheFormulaAndIsCapped() throws {
        try insertProfile()
        try insertHistory()
        let checkIn = try proposal()
        let raw = try #require(checkIn.result.rawEstimate)
        #expect(abs(raw - 3150) < 0.01)
        #expect(checkIn.result.wasCapped)
        #expect(abs(checkIn.result.estimate - checkIn.previousEstimate - 150) < 0.01)
        #expect(checkIn.currentTargets.calories == 2000)
    }

    @Test func todaysPartialLogIsLeftOut() throws {
        try insertProfile()
        try insertHistory()
        context.insert(FoodEntry(
            date: try day(0).addingTimeInterval(8 * 3600),
            mealSlot: .breakfast,
            foodName: "Breakfast",
            servingGrams: 100,
            calories: 1300,
            proteinG: 10,
            carbsG: 10,
            fatG: 10
        ))
        context.insert(WeightEntry(date: try day(0).addingTimeInterval(7 * 3600), weightKg: 200))
        try context.save()
        let checkIn = try proposal()
        #expect(checkIn.result.daysUsed == 21)
        #expect(checkIn.result.weighInsUsed == 21)
        #expect(checkIn.result.averageIntake == 2600)
    }

    @Test func proteinComesFromTheTrendNotTheLastScaleReading() throws {
        try insertProfile()
        try insertHistory(kgPerWeek: 0)
        // Two more readings yesterday average that day to (80 + 80 + 92) / 3 = 84.
        context.insert(WeightEntry(date: try day(-1).addingTimeInterval(9 * 3600), weightKg: 80))
        context.insert(WeightEntry(date: try day(-1).addingTimeInterval(10 * 3600), weightKg: 92))
        try context.save()
        let checkIn = try proposal()
        // The trend closes 10% of the gap, to 80.4 kg, so protein at 2 g/kg
        // is 161 g rather than the 184 g of the last reading.
        #expect(checkIn.proposedTargets.proteinG == 161)
    }

    @Test func targetsFollowTheGoal() throws {
        try insertProfile(goal: .muscleGain)
        try insertHistory()
        let checkIn = try proposal()
        let expected = Int((checkIn.result.estimate * 1.12 / 10).rounded() * 10)
        #expect(checkIn.proposedTargets.calories == expected)
    }

    @Test func floorsReachTheProposal() throws {
        try insertProfile()
        // Eating and losing little: 1800 kcal, weight flat, drops the estimate
        // from the formula, and × 0.8 lands under the 1780 BMR.
        try insertHistory(kcal: 1800, kgPerWeek: 0)
        context.insert(ExpenditureCheckIn(
            date: try day(-7),
            estimateKcal: 1900,
            rawEstimateKcal: 1900,
            avgIntakeKcal: 1800,
            slopeKgPerDay: 0,
            daysUsed: 21,
            applied: false
        ))
        try context.save()
        let checkIn = try proposal()
        #expect(checkIn.proposedTargets.isFloored)
        #expect(checkIn.proposedTargets.calories == 1780)
        #expect(checkIn.floorCalories == 1780)
    }

    // MARK: - Apply and Skip

    @Test func applyWritesTheRowAndTheTargets() throws {
        try insertProfile()
        try insertHistory()
        let checkIn = try proposal()
        try ExpenditureCheckInService.apply(checkIn, context: context)

        let row = try #require(try ModelContext(container).fetch(FetchDescriptor<ExpenditureCheckIn>()).first)
        let today = try day(0)
        #expect(row.applied)
        #expect(row.date == today)
        #expect(row.estimateKcal == checkIn.result.estimate)
        #expect(row.rawEstimateKcal == checkIn.result.rawEstimate)
        #expect(row.avgIntakeKcal == 2600)
        #expect(row.slopeKgPerDay == checkIn.result.slopeKgPerDay)
        #expect(row.daysUsed == 21)
        #expect(row.appliedCalories == checkIn.proposedTargets.calories)
        #expect(row.appliedProteinG == checkIn.proposedTargets.proteinG)
        #expect(row.appliedCarbsG == checkIn.proposedTargets.carbsG)
        #expect(row.appliedFatG == checkIn.proposedTargets.fatG)

        let user = try profile()
        #expect(user.dailyCalorieTarget == checkIn.proposedTargets.calories)
        #expect(user.proteinTargetG == checkIn.proposedTargets.proteinG)
        #expect(user.carbsTargetG == checkIn.proposedTargets.carbsG)
        #expect(user.fatTargetG == checkIn.proposedTargets.fatG)
    }

    @Test func skipSavesTheEstimateAndLeavesTargetsAlone() throws {
        try insertProfile()
        try insertHistory()
        let checkIn = try proposal()
        try ExpenditureCheckInService.skip(checkIn, context: context)

        let row = try #require(try ModelContext(container).fetch(FetchDescriptor<ExpenditureCheckIn>()).first)
        #expect(!row.applied)
        #expect(row.estimateKcal == checkIn.result.estimate)
        #expect(row.appliedCalories == nil)
        #expect(row.appliedProteinG == nil)
        #expect(row.appliedCarbsG == nil)
        #expect(row.appliedFatG == nil)

        let user = try profile()
        #expect(user.dailyCalorieTarget == 2000)
        #expect(user.proteinTargetG == 150)
        #expect(user.carbsTargetG == 200)
        #expect(user.fatTargetG == 60)
    }

    @Test func aPendingProposalChangesNothing() throws {
        try insertProfile()
        try insertHistory()
        _ = try proposal()
        #expect(try profile().dailyCalorieTarget == 2000)
        #expect(try context.fetchCount(FetchDescriptor<ExpenditureCheckIn>()) == 0)
    }

    @Test func aSecondAnswerForTheSameDayChangesNothing() throws {
        try insertProfile()
        try insertHistory()
        let checkIn = try proposal()
        try ExpenditureCheckInService.skip(checkIn, context: context)
        try ExpenditureCheckInService.apply(checkIn, context: context)
        #expect(try context.fetchCount(FetchDescriptor<ExpenditureCheckIn>()) == 1)
        #expect(try profile().dailyCalorieTarget == 2000)
    }

    @Test func nextWeekChainsFromASkippedEstimate() throws {
        try insertProfile()
        try insertHistory(days: 28, end: try day(7))
        let first = try proposal()
        try ExpenditureCheckInService.skip(first, context: context)

        let next = try proposal(now: try day(7).addingTimeInterval(3600))
        #expect(next.previousEstimate == first.result.estimate)
        #expect(abs(next.result.estimate - first.result.estimate - 150) < 0.01)
    }

    // MARK: - Home and Progress

    @Test func homeLoadsTheStateForTheStoredWeekday() throws {
        let defaults = try makeTestDefaults()
        let now = Date.now
        let current = Calendar.current
        let weekday = try #require(CheckInWeekday(rawValue: current.component(.weekday, from: now)))
        defaults.set(weekday.rawValue, forKey: CheckInWeekday.storageKey)

        try insertProfile()
        try insertHistory(end: now)
        let viewModel = HomeViewModel(defaults: defaults)
        viewModel.load(from: context, now: now)

        guard case .ready(let proposal) = viewModel.checkInState else {
            Issue.record("Expected a ready check-in, got \(viewModel.checkInState)")
            return
        }
        try viewModel.applyCheckIn(proposal, context: context, now: now)
        #expect(viewModel.checkInState == .notDue)
        #expect(viewModel.profile?.dailyCalorieTarget == proposal.proposedTargets.calories)
    }

    @Test func progressFiltersCheckInsByRange() throws {
        let now = Date.now
        for weeksAgo in [1, 8] {
            context.insert(ExpenditureCheckIn(
                date: try #require(Calendar.current.date(byAdding: .day, value: -7 * weeksAgo, to: now)),
                estimateKcal: 3000 - Double(weeksAgo),
                rawEstimateKcal: 3000,
                avgIntakeKcal: 2600,
                slopeKgPerDay: 0,
                daysUsed: 21,
                applied: true
            ))
        }
        try context.save()
        let viewModel = ProgressViewModel()
        viewModel.load(from: context, now: now)
        #expect(viewModel.rangeCheckIns.map(\.estimateKcal) == [2999])
        #expect(viewModel.allCheckIns.map(\.estimateKcal) == [2992, 2999])

        viewModel.selectedRange = .quarter
        viewModel.rangeChanged(now: now)
        #expect(viewModel.rangeCheckIns.map(\.estimateKcal) == [2992, 2999])
    }

    // MARK: - Demo seed

    /// 2,600 kcal a day and 0.5 kg a week should read about 3,150, through
    /// the same code a real user runs.
    @Test func demoSeedProducesTheKnownExpenditure() throws {
        DemoSeeder.seed(into: context)

        let rows = try context.fetch(FetchDescriptor<ExpenditureCheckIn>(sortBy: [SortDescriptor(\.date)]))
        #expect(rows.count == DemoSeeder.pastCheckIns)
        #expect(rows.allSatisfy { $0.applied })
        #expect(rows.map(\.estimateKcal) == rows.map(\.estimateKcal).sorted())

        let last = try #require(rows.last)
        let user = try profile()
        #expect(user.dailyCalorieTarget == last.appliedCalories)
        #expect(user.proteinTargetG == last.appliedProteinG)

        let state = try ExpenditureCheckInService.state(context: context, weekday: .monday)
        guard case .ready(let proposal) = state else {
            Issue.record("Expected today's check-in to be open, got \(state)")
            return
        }
        let raw = try #require(proposal.result.rawEstimate)
        #expect(abs(raw - 3150) < 40, "raw \(raw)")
        #expect(abs(proposal.result.estimate - 3150) < 40, "estimate \(proposal.result.estimate)")
        #expect(proposal.result.daysUsed == 21)
        #expect(abs((proposal.result.averageIntake ?? 0) - 2600) < 5)
    }
}
