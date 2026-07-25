//
//  ReminderSchedulingTests.swift
//  VoraTests
//
//  Created by Majd Arow on 2026-07-25.
//

import Foundation
import SwiftData
import Testing
import UserNotifications
@testable import Vora

struct ReminderSchedulingTests {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            UserProfile.self, FoodEntry.self, CustomFood.self,
            WorkoutSession.self, ExerciseLog.self, SetEntry.self,
            WeightEntry.self, WaterEntry.self, CardioEntry.self, SplitDay.self,
            SavedMeal.self, SavedMealItem.self, Recipe.self, RecipeIngredient.self,
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    private func foodEntry(date: Date, slot: MealSlot) -> FoodEntry {
        FoodEntry(
            date: date,
            mealSlot: slot,
            foodName: "Food",
            servingGrams: 100,
            calories: 200,
            proteinG: 10,
            carbsG: 20,
            fatG: 5
        )
    }

    /// Wednesday 2026-07-22 at the given time. Monday-first day index 2.
    private func wednesday(hour: Int, minute: Int = 0) -> Date {
        Calendar.current.date(
            from: DateComponents(year: 2026, month: 7, day: 22, hour: hour, minute: minute)
        )!
    }

    // MARK: - Condition evaluation

    @Test func mealSlotsCountDistinctSlotsTodayOnly() throws {
        let context = try makeContext()
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)

        context.insert(foodEntry(date: today.addingTimeInterval(12 * 3600), slot: .lunch))
        context.insert(foodEntry(date: today.addingTimeInterval(13 * 3600), slot: .lunch))
        context.insert(foodEntry(
            date: cal.date(byAdding: .day, value: -1, to: today)!.addingTimeInterval(8 * 3600),
            slot: .breakfast
        ))
        try context.save()

        #expect(NotificationService.mealSlotsLoggedToday(context: context, now: .now) == 1)

        context.insert(foodEntry(date: today.addingTimeInterval(19 * 3600), slot: .dinner))
        try context.save()
        #expect(NotificationService.mealSlotsLoggedToday(context: context, now: .now) == 2)
    }

    @Test func waterProgressSumsTodayAndFallsBackTo3500() throws {
        let context = try makeContext()
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)

        context.insert(WaterEntry(date: today.addingTimeInterval(9 * 3600), amountMl: 250))
        context.insert(WaterEntry(date: today.addingTimeInterval(11 * 3600), amountMl: 500))
        context.insert(WaterEntry(
            date: cal.date(byAdding: .day, value: -1, to: today)!.addingTimeInterval(9 * 3600),
            amountMl: 1000
        ))
        try context.save()

        let progress = NotificationService.waterProgressToday(context: context, now: .now)
        #expect(progress.loggedMl == 750)
        #expect(progress.targetMl == 3500)
    }

    @Test func waterTargetComesFromProfile() throws {
        let context = try makeContext()
        context.insert(UserProfile(
            name: "Majd",
            dateOfBirth: .now,
            heightCm: 180,
            biologicalSex: .male,
            goalType: .muscleGain,
            activityLevel: .moderatelyActive,
            trainingSplit: .fullBody,
            dailyCalorieTarget: 2500,
            proteinTargetG: 180,
            carbsTargetG: 250,
            fatTargetG: 70,
            waterTargetMl: 3000
        ))
        try context.save()

        #expect(NotificationService.waterProgressToday(context: context, now: .now).targetMl == 3000)
    }

    @Test func trainingDayIndicesExcludeRestDays() throws {
        let context = try makeContext()
        context.insert(SplitDay(dayIndex: 0, title: "Push", muscleGroups: ["chest"], isRest: false))
        context.insert(SplitDay(dayIndex: 1, title: "Rest", isRest: true))
        context.insert(SplitDay(dayIndex: 2, title: "Pull", muscleGroups: ["back"], isRest: false))
        try context.save()

        #expect(NotificationService.trainingDayIndices(context: context) == [0, 2])
        #expect(NotificationService.splitTitle(forDayIndex: 2, context: context) == "Pull")
    }

    @Test func hasTrainedTodayRequiresSessionDatedToday() throws {
        let context = try makeContext()
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)

        context.insert(WorkoutSession(
            date: cal.date(byAdding: .day, value: -1, to: today)!.addingTimeInterval(18 * 3600),
            sessionName: "Push"
        ))
        try context.save()
        #expect(!NotificationService.hasTrainedToday(context: context, now: .now))

        context.insert(WorkoutSession(date: today.addingTimeInterval(7 * 3600), sessionName: "Pull"))
        try context.save()
        #expect(NotificationService.hasTrainedToday(context: context, now: .now))
    }

    // MARK: - Next fire date

    @Test func firesTodayWhenNeededAndTimeAhead() {
        let fireDate = NotificationService.nextFireDate(
            kind: .meal,
            minutes: 720,
            todayNeedsReminder: true,
            trainingDayIndices: nil,
            now: wednesday(hour: 10)
        )
        #expect(fireDate == wednesday(hour: 12))
    }

    @Test func skipsToTomorrowWhenConditionAlreadyMet() {
        let fireDate = NotificationService.nextFireDate(
            kind: .meal,
            minutes: 720,
            todayNeedsReminder: false,
            trainingDayIndices: nil,
            now: wednesday(hour: 10)
        )
        let thursdayNoon = Calendar.current.date(byAdding: .day, value: 1, to: wednesday(hour: 12))
        #expect(fireDate == thursdayNoon)
    }

    @Test func skipsToTomorrowWhenTimeAlreadyPassed() {
        let fireDate = NotificationService.nextFireDate(
            kind: .water,
            minutes: 720,
            todayNeedsReminder: true,
            trainingDayIndices: nil,
            now: wednesday(hour: 13)
        )
        let thursdayNoon = Calendar.current.date(byAdding: .day, value: 1, to: wednesday(hour: 12))
        #expect(fireDate == thursdayNoon)
    }

    @Test func workoutSkipsToNextTrainingDay() {
        // Wednesday has index 2; only Friday (4) is a training day.
        let fireDate = NotificationService.nextFireDate(
            kind: .workout,
            minutes: 1050,
            todayNeedsReminder: true,
            trainingDayIndices: [4],
            now: wednesday(hour: 10)
        )
        let fridayEvening = Calendar.current.date(byAdding: .day, value: 2, to: wednesday(hour: 17, minute: 30))
        #expect(fireDate == fridayEvening)
    }

    @Test func workoutWrapsPastWeekendToMonday() {
        // Only Monday (0) trains; from Wednesday that's 5 days ahead.
        let fireDate = NotificationService.nextFireDate(
            kind: .workout,
            minutes: 1050,
            todayNeedsReminder: true,
            trainingDayIndices: [0],
            now: wednesday(hour: 10)
        )
        let monday = Calendar.current.date(byAdding: .day, value: 5, to: wednesday(hour: 17, minute: 30))
        #expect(fireDate == monday)
    }

    @Test func workoutFiresTodayOnTrainingDayBeforeTime() {
        let fireDate = NotificationService.nextFireDate(
            kind: .workout,
            minutes: 1050,
            todayNeedsReminder: true,
            trainingDayIndices: [2],
            now: wednesday(hour: 10)
        )
        #expect(fireDate == wednesday(hour: 17, minute: 30))
    }

    @Test func allRestSplitProducesNoFireDate() {
        let fireDate = NotificationService.nextFireDate(
            kind: .workout,
            minutes: 1050,
            todayNeedsReminder: true,
            trainingDayIndices: [],
            now: wednesday(hour: 10)
        )
        #expect(fireDate == nil)
    }

    // MARK: - Content

    @Test func mealContentMatchesSpec() throws {
        let context = try makeContext()
        let content = NotificationService.reminderContent(
            kind: .meal, fireDate: .now, context: context, now: .now
        )
        #expect(content.title == "Meal check-in")
        #expect(content.body == "You haven't logged lunch yet. Tap to open your food diary.")
    }

    @Test func waterContentEmbedsLitresWhenFiringToday() throws {
        let context = try makeContext()
        let today = Calendar.current.startOfDay(for: .now)
        context.insert(WaterEntry(date: today.addingTimeInterval(9 * 3600), amountMl: 1200))
        try context.save()

        let content = NotificationService.reminderContent(
            kind: .water, fireDate: .now, context: context, now: .now
        )
        #expect(content.title == "Hydration check")
        #expect(content.body == "You're behind on water today. 1.2L logged of 3.5L.")
    }

    @Test func waterContentIsGenericForFutureFireDates() throws {
        let context = try makeContext()
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now)!
        let content = NotificationService.reminderContent(
            kind: .water, fireDate: tomorrow, context: context, now: .now
        )
        #expect(content.body == "You're behind on water today. Tap to log your intake.")
    }

    @Test func workoutContentUsesFireDaySplitTitle() throws {
        let context = try makeContext()
        let now = wednesday(hour: 10)
        // Friday (index 4) is the fire day.
        context.insert(SplitDay(dayIndex: 4, title: "Leg Day", muscleGroups: ["quads"], isRest: false))
        try context.save()

        let friday = Calendar.current.date(byAdding: .day, value: 2, to: now)!
        let content = NotificationService.reminderContent(
            kind: .workout, fireDate: friday, context: context, now: now
        )
        #expect(content.title == "Workout time")
        #expect(content.body == "Time for Leg Day. Tap to start your session.")
    }

    // MARK: - Request assembly

    @Test func reminderRequestBuildsOneShotCalendarTrigger() throws {
        let context = try makeContext()
        let now = wednesday(hour: 10)

        let request = try #require(NotificationService.reminderRequest(
            kind: .meal, context: context, minutes: 720, now: now
        ))

        #expect(request.identifier == ReminderKind.meal.notificationId)
        let trigger = try #require(request.trigger as? UNCalendarNotificationTrigger)
        #expect(trigger.repeats == false)
        #expect(trigger.dateComponents.year == 2026)
        #expect(trigger.dateComponents.month == 7)
        #expect(trigger.dateComponents.day == 22)
        #expect(trigger.dateComponents.hour == 12)
        #expect(trigger.dateComponents.minute == 0)
    }

    @Test func workoutRequestIsNilWithAllRestSplit() throws {
        let context = try makeContext()
        context.insert(SplitDay(dayIndex: 0, title: "Rest", isRest: true))
        try context.save()

        let request = NotificationService.reminderRequest(
            kind: .workout, context: context, minutes: 1050, now: wednesday(hour: 10)
        )
        #expect(request == nil)
    }

    // MARK: - Settings

    @Test func settingsDefaultsAndRoundTrip() throws {
        let defaults = try #require(UserDefaults(suiteName: "vora.tests.reminders"))
        defaults.removePersistentDomain(forName: "vora.tests.reminders")
        let settings = ReminderSettings(defaults: defaults)

        #expect(!settings.isEnabled(.meal))
        #expect(settings.minutes(for: .meal) == 720)
        #expect(settings.minutes(for: .water) == 900)
        #expect(settings.minutes(for: .workout) == 1050)
        #expect(settings.weeklySummaryEnabled)

        defaults.set(true, forKey: ReminderKind.water.enabledKey)
        defaults.set(600, forKey: ReminderKind.water.timeKey)
        defaults.set(false, forKey: ReminderSettings.weeklySummaryEnabledKey)

        #expect(settings.isEnabled(.water))
        #expect(settings.minutes(for: .water) == 600)
        #expect(!settings.weeklySummaryEnabled)

        defaults.removePersistentDomain(forName: "vora.tests.reminders")
    }
}
