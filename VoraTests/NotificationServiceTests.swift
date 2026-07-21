//
//  NotificationServiceTests.swift
//  VoraTests
//
//  Created by Majd Arow on 2026-07-21.
//

import Foundation
import SwiftData
import Testing
import UserNotifications
@testable import Vora

struct NotificationServiceTests {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            UserProfile.self, FoodEntry.self, CustomFood.self,
            WorkoutSession.self, ExerciseLog.self, SetEntry.self,
            WeightEntry.self, WaterEntry.self, CardioEntry.self, SplitDay.self,
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    @Test func summaryIncludesWorkoutsCaloriesAndWeightDelta() throws {
        let context = try makeContext()
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)

        for offset in [1, 3] {
            context.insert(WorkoutSession(
                date: cal.date(byAdding: .day, value: -offset, to: today)!.addingTimeInterval(18 * 3600),
                sessionName: "Session"
            ))
        }
        for offset in 0..<2 {
            context.insert(FoodEntry(
                date: cal.date(byAdding: .day, value: -offset, to: today)!.addingTimeInterval(12 * 3600),
                mealSlot: .lunch,
                foodName: "Meal",
                servingGrams: 300,
                calories: 2000,
                proteinG: 100,
                carbsG: 200,
                fatG: 60
            ))
        }
        context.insert(WeightEntry(date: cal.date(byAdding: .day, value: -5, to: today)!, weightKg: 82.0))
        context.insert(WeightEntry(date: today.addingTimeInterval(7 * 3600), weightKg: 81.2))
        for (index, template) in TrainingSplit.upperLower.weeklyTemplate.enumerated() {
            context.insert(SplitDay(
                dayIndex: index,
                title: template.title,
                muscleGroups: template.muscleGroups,
                isRest: template.isRest
            ))
        }
        try context.save()

        let content = NotificationService.shared.weeklySummaryContent(context: context, now: .now)

        #expect(content.title == "Your week in review")
        #expect(content.body.contains("2 workouts"))
        #expect(content.body.contains("avg 2000 kcal"))
        #expect(content.body.contains("-0.8 kg"))
        #expect(content.body.contains("4 training days planned"))
    }

    @Test func emptyStoreProducesGracefulSummary() throws {
        let context = try makeContext()
        let content = NotificationService.shared.weeklySummaryContent(context: context, now: .now)

        #expect(content.body.contains("0 workouts"))
        #expect(!content.body.contains("avg"))
        #expect(!content.body.contains("kg"))
        #expect(content.body.contains("Set up your training split"))
    }

    @Test func weeklyRequestFiresSundayEveningAndRepeats() {
        let content = UNMutableNotificationContent()
        content.title = "Test"
        let request = NotificationService.weeklySummaryRequest(content: content)

        #expect(request.identifier == NotificationService.weeklySummaryId)
        let trigger = request.trigger as? UNCalendarNotificationTrigger
        #expect(trigger?.repeats == true)
        #expect(trigger?.dateComponents.weekday == 1)
        #expect(trigger?.dateComponents.hour == 19)

        if let next = trigger?.nextTriggerDate() {
            let parts = Calendar.current.dateComponents([.weekday, .hour], from: next)
            #expect(parts.weekday == 1)
            #expect(parts.hour == 19)
        }
    }

    @Test func singularFormsReadCorrectly() throws {
        let context = try makeContext()
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)

        context.insert(WorkoutSession(
            date: cal.date(byAdding: .day, value: -1, to: today)!.addingTimeInterval(18 * 3600),
            sessionName: "Session"
        ))
        context.insert(SplitDay(dayIndex: 0, title: "Full Body", muscleGroups: ["chest"], isRest: false))
        for index in 1..<7 {
            context.insert(SplitDay(dayIndex: index, title: "Rest", isRest: true))
        }
        try context.save()

        let content = NotificationService.shared.weeklySummaryContent(context: context, now: .now)
        #expect(content.body.contains("1 workout ·") || content.body.contains("1 workout."))
        #expect(content.body.contains("1 training day planned"))
    }
}
