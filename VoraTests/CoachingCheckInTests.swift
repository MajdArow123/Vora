//
//  CoachingCheckInTests.swift
//  VoraTests
//
//  Created by Majd Arow on 2026-11-03.
//

import Foundation
import SwiftData
import Testing
@testable import Vora

@MainActor
struct CoachingCheckInTests {
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

    private func day(_ offset: Int) throws -> Date {
        try #require(calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: monday)))
    }

    private func insertNutrition(target: Int = 2500, goal: GoalType = .fatLoss, kcal: Double = 2500, kgPerWeek: Double = -0.5) throws {
        context.insert(UserProfile(
            name: "Test",
            dateOfBirth: try #require(calendar.date(byAdding: .year, value: -30, to: monday)),
            heightCm: 180,
            biologicalSex: .male,
            goalType: goal,
            activityLevel: .moderatelyActive,
            trainingSplit: .ppl,
            dailyCalorieTarget: target,
            proteinTargetG: 160,
            carbsTargetG: 280,
            fatTargetG: 70
        ))
        for offset in 1...21 {
            let date = try day(-offset).addingTimeInterval(8 * 3600)
            context.insert(WeightEntry(date: date, weightKg: 80 - Double(offset) * kgPerWeek / 7))
            context.insert(FoodEntry(
                date: date,
                mealSlot: .lunch,
                foodName: "Lunch",
                servingGrams: 500,
                calories: kcal,
                proteinG: 150,
                carbsG: 300,
                fatG: 70
            ))
        }
        try context.save()
    }

    /// One lift's weekly sessions, `perWeekKg` heavier each week going forward,
    /// over the five weeks before Monday.
    private func insertLift(
        name: String,
        exerciseId: String?,
        perWeekKg: Double,
        setType: SetType = .normal,
        rir: (Int) -> Int? = { _ in nil }
    ) throws {
        for week in 0..<5 {
            let session = WorkoutSession(date: try day(-1 - 7 * week).addingTimeInterval(17 * 3600), sessionName: "S")
            context.insert(session)
            let log = ExerciseLog(exerciseName: name, exerciseId: exerciseId, orderIndex: 0)
            session.exercises.append(log)
            log.sets.append(SetEntry(
                setNumber: 1,
                weightKg: 100 - perWeekKg * Double(week),
                reps: 8,
                isCompleted: true,
                rir: rir(week),
                setType: setType
            ))
        }
        try context.save()
    }

    private func insertFallingStrength() throws {
        try insertLift(name: "Barbell Bench Press", exerciseId: "barbell-bench-press", perWeekKg: -2)
        try insertLift(name: "Back Squat", exerciseId: "back-squat", perWeekKg: -2)
    }

    private func proposal() throws -> ExpenditureProposal {
        let state = try ExpenditureCheckInService.state(context: context, weekday: .monday, now: monday, calendar: calendar)
        guard case .ready(let proposal) = state else { throw CheckInNotReady() }
        return proposal
    }

    private struct CheckInNotReady: Error {}

    private func profile() throws -> UserProfile {
        try #require(try context.fetch(FetchDescriptor<UserProfile>()).first)
    }

    // MARK: - Store to advice

    @Test func aFallingWeekOverWeekOffersAnAdjustmentOnTopOfTheProposal() throws {
        try insertNutrition()
        try insertFallingStrength()
        let proposal = try proposal()
        let advice = try #require(proposal.coaching)
        #expect(advice.strength.isFalling)
        #expect(advice.previousStrength.isFalling)
        guard case .easeDeficit = advice.rule else {
            Issue.record("Expected easeDeficit, got \(advice.rule)")
            return
        }
        let adjustment = try #require(advice.adjustment)
        #expect(adjustment.targets.calories == proposal.proposedTargets.calories + adjustment.deltaKcal)
        #expect(adjustment.targets.proteinG == proposal.proposedTargets.proteinG)
    }

    @Test func noSessionsSaysNotEnoughData() throws {
        try insertNutrition()
        let advice = try #require(try proposal().coaching)
        #expect(advice.rule == .notEnoughTrainingData)
        #expect(advice.adjustment == nil)
    }

    @Test func customExercisesCountByTheirKey() throws {
        try insertNutrition()
        try insertLift(name: "Sled Push", exerciseId: nil, perWeekKg: -2)
        try insertLift(name: "Prowler Drag", exerciseId: nil, perWeekKg: -2)
        #expect(try #require(try proposal().coaching).strength.isFalling)
    }

    @Test func aRenamedExerciseIsStillTheSameLift() throws {
        try insertNutrition()
        // The same ID under two stored names has to stay one lift, so with only
        // this lift there's still not enough data.
        for (week, name) in ["Barbell Bench Press", "Bench", "Old Name", "Flat Bench"].enumerated() {
            let session = WorkoutSession(date: try day(-1 - 7 * week), sessionName: "S")
            context.insert(session)
            let log = ExerciseLog(exerciseName: name, exerciseId: "barbell-bench-press", orderIndex: 0)
            session.exercises.append(log)
            log.sets.append(SetEntry(setNumber: 1, weightKg: 100, reps: 8, isCompleted: true))
        }
        try context.save()
        guard case .notEnoughData(let usable) = try #require(try proposal().coaching).strength else {
            Issue.record("Expected not enough data")
            return
        }
        #expect(usable == 1)
    }

    @Test func deletingSessionsChangesTheAdvice() throws {
        try insertNutrition()
        try insertFallingStrength()
        #expect(try #require(try proposal().coaching).strength.isFalling)
        for session in try context.fetch(FetchDescriptor<WorkoutSession>()) {
            context.delete(session)
        }
        try context.save()
        #expect(try #require(try proposal().coaching).rule == .notEnoughTrainingData)
    }

    @Test func dropSetsDontMakeATrend() throws {
        try insertNutrition()
        try insertLift(name: "Barbell Bench Press", exerciseId: "barbell-bench-press", perWeekKg: -2, setType: .drop)
        try insertLift(name: "Back Squat", exerciseId: "back-squat", perWeekKg: -2, setType: .drop)
        #expect(try #require(try proposal().coaching).rule == .notEnoughTrainingData)
    }

    @Test func startingToLogRIRDoesntLookLikeGettingStronger() throws {
        try insertNutrition()
        // The weights fall; RIR is logged only on the latest sessions, which a
        // reps + RIR estimate would read as gaining strength.
        let rir: (Int) -> Int? = { $0 < 2 ? 5 : nil }
        try insertLift(name: "Barbell Bench Press", exerciseId: "barbell-bench-press", perWeekKg: -2, rir: rir)
        try insertLift(name: "Back Squat", exerciseId: "back-squat", perWeekKg: -2, rir: rir)
        #expect(try #require(try proposal().coaching).strength.isFalling)
    }

    @Test func todaysSessionIsLeftOut() throws {
        try insertNutrition()
        try insertFallingStrength()
        let session = WorkoutSession(date: monday, sessionName: "Today")
        context.insert(session)
        let log = ExerciseLog(exerciseName: "Barbell Bench Press", exerciseId: "barbell-bench-press", orderIndex: 0)
        session.exercises.append(log)
        log.sets.append(SetEntry(setNumber: 1, weightKg: 500, reps: 8, isCompleted: true))
        try context.save()
        #expect(try #require(try proposal().coaching).strength.isFalling)
    }

    // MARK: - Answers

    @Test func applyWithoutTheAdjustmentWritesOnlyTheProposal() throws {
        try insertNutrition()
        try insertFallingStrength()
        let proposal = try proposal()
        try ExpenditureCheckInService.apply(proposal, context: context)
        #expect(try profile().dailyCalorieTarget == proposal.proposedTargets.calories)
        let row = try #require(try context.fetch(FetchDescriptor<ExpenditureCheckIn>()).first)
        #expect(row.appliedCalories == proposal.proposedTargets.calories)
    }

    @Test func applyWithTheAdjustmentWritesItAndRecordsIt() throws {
        try insertNutrition()
        try insertFallingStrength()
        let proposal = try proposal()
        let adjusted = try #require(proposal.coaching?.adjustment).targets
        try ExpenditureCheckInService.apply(proposal, includingAdjustment: true, context: context)
        let user = try profile()
        #expect(user.dailyCalorieTarget == adjusted.calories)
        #expect(user.proteinTargetG == adjusted.proteinG)
        #expect(user.carbsTargetG == adjusted.carbsG)
        #expect(user.fatTargetG == adjusted.fatG)
        let row = try #require(try context.fetch(FetchDescriptor<ExpenditureCheckIn>()).first)
        #expect(row.applied)
        #expect(row.appliedCalories == adjusted.calories)
        #expect(row.appliedFatG == adjusted.fatG)
        // The estimate stays what was measured; the adjustment isn't part of it.
        #expect(row.estimateKcal == proposal.result.estimate)
    }

    @Test func askingForAnAdjustmentThatDoesntExistWritesTheProposal() throws {
        try insertNutrition()
        let proposal = try proposal()
        #expect(proposal.coaching?.adjustment == nil)
        try ExpenditureCheckInService.apply(proposal, includingAdjustment: true, context: context)
        #expect(try profile().dailyCalorieTarget == proposal.proposedTargets.calories)
    }

    @Test func skipLeavesTheTargetsAlone() throws {
        try insertNutrition(target: 2500)
        try insertFallingStrength()
        try ExpenditureCheckInService.skip(try proposal(), context: context)
        #expect(try profile().dailyCalorieTarget == 2500)
        let row = try #require(try context.fetch(FetchDescriptor<ExpenditureCheckIn>()).first)
        #expect(!row.applied)
        #expect(row.appliedCalories == nil)
    }

    @Test func aSecondAnswerChangesNothing() throws {
        try insertNutrition()
        try insertFallingStrength()
        let proposal = try proposal()
        try ExpenditureCheckInService.apply(proposal, context: context)
        let first = try profile().dailyCalorieTarget
        try ExpenditureCheckInService.apply(proposal, includingAdjustment: true, context: context)
        #expect(try profile().dailyCalorieTarget == first)
        #expect(try context.fetchCount(FetchDescriptor<ExpenditureCheckIn>()) == 1)
    }

    @Test func nextWeekStartsAgainFromTheEstimate() throws {
        try insertNutrition()
        try insertFallingStrength()
        let first = try proposal()
        try ExpenditureCheckInService.apply(first, includingAdjustment: true, context: context)
        let row = try #require(try context.fetch(FetchDescriptor<ExpenditureCheckIn>()).first)
        // The stored estimate has no adjustment in it, so next week's proposal
        // isn't built on top of this one.
        #expect(row.estimateKcal == first.result.estimate)
    }

    // MARK: - Deficit

    private func insertCheckIn(estimate: Double, daysAgo: Int) throws {
        context.insert(ExpenditureCheckIn(
            date: try day(-daysAgo),
            estimateKcal: estimate,
            rawEstimateKcal: estimate,
            avgIntakeKcal: 2500,
            slopeKgPerDay: 0,
            daysUsed: 21,
            applied: false
        ))
        try context.save()
    }

    @Test func noCheckInMeansNoDeficitContext() throws {
        try insertNutrition(kcal: 2000)
        #expect(try CoachingService.deficitPercent(context: context, now: monday, calendar: calendar) == nil)
    }

    @Test func aRecentEstimateGivesTheDeficit() throws {
        try insertNutrition(kcal: 2500)
        try insertCheckIn(estimate: 3125, daysAgo: 7)
        #expect(try CoachingService.deficitPercent(context: context, now: monday, calendar: calendar) == 20)
    }

    @Test func aSmallDeficitIsNotMeaningful() throws {
        try insertNutrition(kcal: 2500)
        try insertCheckIn(estimate: 2700, daysAgo: 7)
        #expect(try CoachingService.deficitPercent(context: context, now: monday, calendar: calendar) == nil)
    }

    @Test func theEstimateCanBeTwentyEightDaysOldButNoMore() throws {
        try insertNutrition(kcal: 2500)
        try insertCheckIn(estimate: 3125, daysAgo: 29)
        #expect(try CoachingService.deficitPercent(context: context, now: monday, calendar: calendar) == nil)
        try insertCheckIn(estimate: 3125, daysAgo: 28)
        #expect(try CoachingService.deficitPercent(context: context, now: monday, calendar: calendar) == 20)
    }

    @Test func aSkippedCheckInStillGivesAnEstimate() throws {
        try insertNutrition(kcal: 2500)
        try insertCheckIn(estimate: 3125, daysAgo: 1)
        let row = try #require(try context.fetch(FetchDescriptor<ExpenditureCheckIn>()).first)
        #expect(!row.applied)
        #expect(try CoachingService.deficitPercent(context: context, now: monday, calendar: calendar) != nil)
    }

    // MARK: - Demo scenarios

    private func seededProposal(_ scenario: DemoSeeder.CoachingScenario) throws -> ExpenditureProposal {
        DemoSeeder.seed(into: context, scenario: scenario)
        let state = try ExpenditureCheckInService.state(context: context, weekday: .monday)
        guard case .ready(let proposal) = state else { throw CheckInNotReady() }
        return proposal
    }

    @Test func strengthFallingScenarioEasesForStrength() throws {
        let advice = try #require(try seededProposal(.strengthFalling).coaching)
        guard case .easeDeficit(let reasons) = advice.rule, case .strengthFalling = reasons.first else {
            Issue.record("Got \(advice.rule)")
            return
        }
        #expect(reasons.count == 1)
        #expect(advice.adjustment?.deltaKcal == 100)
    }

    @Test func lossTooFastScenarioEasesForRate() throws {
        let advice = try #require(try seededProposal(.lossTooFast).coaching)
        guard case .easeDeficit(let reasons) = advice.rule,
              reasons.contains(where: { if case .losingTooFast = $0 { true } else { false } })
        else {
            Issue.record("Got \(advice.rule)")
            return
        }
        #expect(advice.adjustment?.deltaKcal == 150)
    }

    @Test func gainTooFastScenarioTrims() throws {
        let advice = try #require(try seededProposal(.gainTooFast).coaching)
        guard case .trimSurplus = advice.rule else {
            Issue.record("Got \(advice.rule)")
            return
        }
        #expect(advice.adjustment?.deltaKcal == -100)
    }

    @Test func gainOnTrackScenarioIsOnTrack() throws {
        let advice = try #require(try seededProposal(.gainOnTrack).coaching)
        #expect(advice.rule == .onTrack)
    }

    @Test func notEnoughTrainingScenarioSaysSo() throws {
        let advice = try #require(try seededProposal(.notEnoughTraining).coaching)
        #expect(advice.rule == .notEnoughTrainingData)
    }

    @Test func deficitHoldScenarioHoldsASessionStartedToday() throws {
        DemoSeeder.seed(into: context, scenario: .deficitHold)
        let deficit = try #require(try CoachingService.deficitPercent(context: context))
        let vm = ActiveSessionViewModel(sessionName: "Push", health: NoHealthWrites())
        vm.prefill(
            with: [TemplateExerciseSpec(exerciseId: "barbell-bench-press", targetSets: 3, repRangeMin: 8, repRangeMax: 12, targetRIR: 2)],
            context: context,
            progression: ProgressionContext(mode: .repsFirst, inventory: .standard(units: .metric), deficitPercent: deficit)
        )
        let recommendation = try #require(vm.exercises.first?.sets.compactMap(\.activeRecommendation).first)
        #expect(recommendation.reason == .holdForDeficit(struggling: 3, total: 3))
        #expect(recommendation.deficitPercent == deficit)
    }
}
