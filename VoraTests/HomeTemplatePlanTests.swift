//
//  HomeTemplatePlanTests.swift
//  VoraTests
//
//  Created by Majd Arow on 2026-11-02.
//

import Foundation
import SwiftData
import Testing
@testable import Vora

/// Home's Start Session must open the same plan as Train's.
@MainActor
struct HomeTemplatePlanTests {
    private static let suiteName = "vora.tests.home-template-plan"
    private static let mondayIndex = 0
    private static let sundayIndex = 6

    /// Held for the test's lifetime; a context outlives its container
    /// only as a dangling reference.
    private let container: ModelContainer
    private let defaults: UserDefaults
    /// Fixed days so results don't depend on when the suite runs.
    private let monday: Date
    private let sunday: Date

    init() throws {
        container = try PersistenceController.makeContainer(inMemory: true)
        defaults = try #require(UserDefaults(suiteName: Self.suiteName))
        defaults.removePersistentDomain(forName: Self.suiteName)
        monday = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 12)))
        sunday = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: 12)))
    }

    private var context: ModelContext {
        container.mainContext
    }

    private func insertProfile(split: TrainingSplit = .ppl) throws {
        context.insert(UserProfile(
            name: "Test User",
            dateOfBirth: try #require(Calendar.current.date(byAdding: .year, value: -30, to: monday)),
            heightCm: 180,
            biologicalSex: .male,
            goalType: .fatLoss,
            activityLevel: .moderatelyActive,
            trainingSplit: split,
            dailyCalorieTarget: 2400,
            proteinTargetG: 170,
            carbsTargetG: 250,
            fatTargetG: 70
        ))
    }

    private func insertDay(_ dayIndex: Int, title: String = "Push", isRest: Bool = false) {
        context.insert(SplitDay(dayIndex: dayIndex, title: title, muscleGroups: [], isRest: isRest))
    }

    private func savedSpecs() -> [TemplateExerciseSpec] {
        [
            TemplateExerciseSpec(exerciseId: "dip", targetSets: 5),
            TemplateExerciseSpec(exerciseId: "barbell-bench-press", targetSets: 2),
        ]
    }

    private func loadHome(now: Date) throws -> HomeViewModel {
        try context.save()
        let viewModel = HomeViewModel(defaults: defaults)
        viewModel.load(from: context, now: now)
        return viewModel
    }

    // MARK: - Plan

    @Test func savedTemplateIsReturnedInOrderWithTargets() throws {
        try insertProfile()
        insertDay(Self.mondayIndex)
        try WorkoutTemplateService.save(savedSpecs(), for: .ppl, dayIndex: Self.mondayIndex, context: context)

        let plan = try loadHome(now: monday).templatePlan(context: context)

        #expect(plan.map(\.exerciseId) == ["dip", "barbell-bench-press"])
        #expect(plan.map(\.targetSets) == [5, 2])
    }

    @Test func withoutSavedTemplateTheSplitsDefaultIsReturned() throws {
        try insertProfile()
        insertDay(Self.mondayIndex)

        let plan = try loadHome(now: monday).templatePlan(context: context)

        let expected = WorkoutTemplateService.defaultExerciseIDs(for: .ppl, dayIndex: Self.mondayIndex)
        #expect(!expected.isEmpty)
        #expect(plan.compactMap(\.exerciseId) == expected)
    }

    @Test func restDayIsEmptyEvenWithSavedTemplate() throws {
        try insertProfile()
        insertDay(Self.mondayIndex, title: "Rest", isRest: true)
        try WorkoutTemplateService.save(savedSpecs(), for: .ppl, dayIndex: Self.mondayIndex, context: context)

        let plan = try loadHome(now: monday).templatePlan(context: context)

        #expect(plan.isEmpty)
    }

    /// SplitDay rows are only seeded once Train has been opened.
    @Test func missingSplitDayStillUsesSavedOrDefaultPlan() throws {
        try insertProfile()

        let defaultPlan = try loadHome(now: monday).templatePlan(context: context)
        #expect(defaultPlan.compactMap(\.exerciseId)
            == WorkoutTemplateService.defaultExerciseIDs(for: .ppl, dayIndex: Self.mondayIndex))

        try WorkoutTemplateService.save(savedSpecs(), for: .ppl, dayIndex: Self.mondayIndex, context: context)
        let savedPlan = try loadHome(now: monday).templatePlan(context: context)
        #expect(savedPlan.map(\.exerciseId) == ["dip", "barbell-bench-press"])
    }

    /// Train only reads the real clock, so every day is a training day here
    /// and the template is saved for today's slot, whichever day that is.
    @Test func homeAndTrainResolveTheSamePlan() throws {
        try insertProfile()
        for index in WorkoutTemplateService.dayIndices {
            insertDay(index)
        }
        try context.save()

        let train = WorkoutHomeViewModel()
        train.load(from: context)
        try WorkoutTemplateService.save(savedSpecs(), for: .ppl, dayIndex: train.todayIndex, context: context)

        let homePlan = try loadHome(now: .now).templatePlan(context: context)

        #expect(!homePlan.isEmpty)
        #expect(homePlan == train.templatePlan(context: context))
    }

    @Test func homePlanPrefillsTheSession() throws {
        try insertProfile()
        insertDay(Self.mondayIndex)
        try WorkoutTemplateService.save(savedSpecs(), for: .ppl, dayIndex: Self.mondayIndex, context: context)
        let plan = try loadHome(now: monday).templatePlan(context: context)

        let session = ActiveSessionViewModel(sessionName: "Push", health: NoHealthWrites())
        session.prefill(with: plan, context: context)

        #expect(session.exercises.map(\.exerciseId) == ["dip", "barbell-bench-press"])
        #expect(session.exercises.map(\.sets.count) == [5, 2])
    }

    // MARK: - Card title

    @Test func missingSplitDayTitleComesFromDefaultPlan() throws {
        try insertProfile()

        let viewModel = try loadHome(now: monday)

        #expect(viewModel.todaySplitDay == nil)
        #expect(viewModel.todayTitle == WorkoutTemplateService.defaultName(for: .ppl, dayIndex: Self.mondayIndex))
    }

    @Test func missingSplitDayTitleComesFromSavedTemplateName() throws {
        try insertProfile()
        try WorkoutTemplateService.save(savedSpecs(), for: .ppl, dayIndex: Self.mondayIndex, context: context)
        let saved = try #require(try WorkoutTemplateService.template(for: .ppl, dayIndex: Self.mondayIndex, context: context))
        saved.name = "Chest Day"

        let viewModel = try loadHome(now: monday)

        #expect(viewModel.todayTitle == "Chest Day")
    }

    /// The card shows "No plan" for a nil title.
    @Test func missingSplitDayWithEmptyPlanHasNoTitle() throws {
        try insertProfile()

        let viewModel = try loadHome(now: sunday)

        #expect(viewModel.todayIndex == Self.sundayIndex)
        #expect(viewModel.templatePlan(context: context).isEmpty)
        #expect(viewModel.todayTitle == nil)
    }

    @Test func splitDayTitleWinsOverTemplateName() throws {
        try insertProfile()
        insertDay(Self.mondayIndex, title: "Heavy Push")
        try WorkoutTemplateService.save(savedSpecs(), for: .ppl, dayIndex: Self.mondayIndex, context: context)
        let saved = try #require(try WorkoutTemplateService.template(for: .ppl, dayIndex: Self.mondayIndex, context: context))
        saved.name = "Chest Day"

        let viewModel = try loadHome(now: monday)

        #expect(viewModel.todayTitle == "Heavy Push")
    }

    // MARK: - Session name

    /// Train names a session after the SplitDay it seeds from this template.
    @Test func missingSplitDaySessionIsNamedAsTrainWouldNameIt() throws {
        try insertProfile()

        let viewModel = try loadHome(now: monday)

        #expect(viewModel.todaySplitDay == nil)
        #expect(viewModel.sessionName == "Push")
        #expect(viewModel.sessionName == TrainingSplit.ppl.weeklyTemplate[Self.mondayIndex].title)
    }

    @Test func sessionNameFollowsTheCardTitle() throws {
        try insertProfile()
        insertDay(Self.mondayIndex, title: "Heavy Push")

        let viewModel = try loadHome(now: monday)

        #expect(viewModel.sessionName == "Heavy Push")
        #expect(viewModel.sessionName == viewModel.todayTitle)
    }

    @Test func sessionNameFallsBackWithoutATitle() throws {
        try insertProfile()

        let viewModel = try loadHome(now: sunday)

        #expect(viewModel.todayTitle == nil)
        #expect(viewModel.sessionName == "Workout")
    }
}
