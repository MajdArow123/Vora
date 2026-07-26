//
//  SupplementReminderTests.swift
//  VoraTests
//
//  Created by Majd Arow on 2026-07-26.
//

import Foundation
import SwiftData
import Testing
import UserNotifications
@testable import Vora

struct SupplementReminderTests {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([Supplement.self, SupplementLog.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    private func supplement(
        _ name: String,
        dose: String = "5g",
        minutes: Int,
        orderIndex: Int = 0,
        reminderEnabled: Bool = true,
        isActive: Bool = true
    ) -> Supplement {
        Supplement(
            name: name,
            dose: dose,
            reminderEnabled: reminderEnabled,
            reminderMinutes: minutes,
            isActive: isActive,
            orderIndex: orderIndex
        )
    }

    /// Wednesday 2026-07-22 at the given time.
    private func wednesday(hour: Int, minute: Int = 0) -> Date {
        Calendar.current.date(
            from: DateComponents(year: 2026, month: 7, day: 22, hour: hour, minute: minute)
        )!
    }

    // MARK: - Grouping

    @Test func supplementsWithinFiveMinutesShareAGroup() {
        let groups = NotificationService.supplementReminderGroups([
            supplement("Creatine", minutes: 480, orderIndex: 0),
            supplement("Vitamin D", minutes: 483, orderIndex: 1),
        ])
        #expect(groups.count == 1)
        #expect(groups[0].map(\.name) == ["Creatine", "Vitamin D"])
    }

    @Test func groupingIsAnchorBasedNotChained() {
        // 8:00 anchors [8:00, 8:04]; 8:08 is outside the anchor's window
        // even though it is within 5 minutes of 8:04.
        let groups = NotificationService.supplementReminderGroups([
            supplement("A", minutes: 480, orderIndex: 0),
            supplement("B", minutes: 484, orderIndex: 1),
            supplement("C", minutes: 488, orderIndex: 2),
        ])
        #expect(groups.map { $0.map(\.name) } == [["A", "B"], ["C"]])
    }

    @Test func exactlyFiveMinutesApartStillBatches() {
        let groups = NotificationService.supplementReminderGroups([
            supplement("A", minutes: 480, orderIndex: 0),
            supplement("B", minutes: 485, orderIndex: 1),
        ])
        #expect(groups.count == 1)
    }

    @Test func sixMinutesApartSplits() {
        let groups = NotificationService.supplementReminderGroups([
            supplement("A", minutes: 480, orderIndex: 0),
            supplement("B", minutes: 486, orderIndex: 1),
        ])
        #expect(groups.count == 2)
    }

    // MARK: - Identifier

    @Test func identifierUsesSpecFormat() {
        let id = UUID()
        #expect(NotificationService.supplementNotificationId(id) == "vora.supplement.\(id.uuidString)")
    }

    @Test func requestUsesAnchorSupplementId() throws {
        let context = try makeContext()
        let creatine = supplement("Creatine", minutes: 480, orderIndex: 0)
        let vitaminD = supplement("Vitamin D", minutes: 482, orderIndex: 1)
        context.insert(creatine)
        context.insert(vitaminD)
        try context.save()

        let requests = NotificationService.supplementReminderRequests(
            context: context, now: wednesday(hour: 6)
        )
        #expect(requests.count == 1)
        #expect(requests[0].identifier == NotificationService.supplementNotificationId(creatine.id))
    }

    // MARK: - Content

    @Test func singleSupplementBodyMatchesSpec() {
        let creatine = supplement("Creatine", dose: "5g", minutes: 480)
        let content = NotificationService.supplementReminderContent(
            group: [creatine], untaken: [creatine], fireDate: wednesday(hour: 8), now: wednesday(hour: 6)
        )
        #expect(content.title == "Supplement reminder")
        #expect(content.body == "Creatine · 5g — time to take your supplement")
    }

    @Test func batchedBodyListsNames() {
        let group = [
            supplement("Creatine", minutes: 480, orderIndex: 0),
            supplement("Vitamin D", minutes: 481, orderIndex: 1),
            supplement("Omega-3", minutes: 482, orderIndex: 2),
        ]
        let content = NotificationService.supplementReminderContent(
            group: group, untaken: group, fireDate: wednesday(hour: 8), now: wednesday(hour: 6)
        )
        #expect(content.body == "Time for your supplements: Creatine, Vitamin D, Omega-3")
    }

    @Test func firingTodayListsOnlyUntakenMembers() {
        let creatine = supplement("Creatine", minutes: 480, orderIndex: 0)
        let vitaminD = supplement("Vitamin D", dose: "2000IU", minutes: 481, orderIndex: 1)
        let content = NotificationService.supplementReminderContent(
            group: [creatine, vitaminD],
            untaken: [vitaminD],
            fireDate: wednesday(hour: 8),
            now: wednesday(hour: 6)
        )
        #expect(content.body == "Vitamin D · 2000IU — time to take your supplement")
    }

    @Test func futureFireDateCoversWholeGroup() {
        let creatine = supplement("Creatine", minutes: 480, orderIndex: 0)
        let vitaminD = supplement("Vitamin D", minutes: 481, orderIndex: 1)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: wednesday(hour: 8))!
        let content = NotificationService.supplementReminderContent(
            group: [creatine, vitaminD],
            untaken: [],
            fireDate: tomorrow,
            now: wednesday(hour: 10)
        )
        #expect(content.body == "Time for your supplements: Creatine, Vitamin D")
    }

    // MARK: - Request assembly

    @Test func disabledAndInactiveSupplementsAreExcluded() throws {
        let context = try makeContext()
        context.insert(supplement("Active", minutes: 480, orderIndex: 0))
        context.insert(supplement("No reminder", minutes: 480, orderIndex: 1, reminderEnabled: false))
        context.insert(supplement("Deleted", minutes: 480, orderIndex: 2, isActive: false))
        try context.save()

        let requests = NotificationService.supplementReminderRequests(
            context: context, now: wednesday(hour: 6)
        )
        #expect(requests.count == 1)
    }

    @Test func allTakenRollsToTomorrow() throws {
        let context = try makeContext()
        let creatine = supplement("Creatine", minutes: 480, orderIndex: 0)
        context.insert(creatine)
        let now = wednesday(hour: 6)
        let todayStart = Calendar.current.startOfDay(for: now)
        context.insert(SupplementLog(
            supplementID: creatine.id,
            supplementName: "Creatine",
            dose: "5g",
            date: todayStart,
            takenAt: now
        ))
        try context.save()

        let requests = NotificationService.supplementReminderRequests(context: context, now: now)
        let trigger = try #require(requests.first?.trigger as? UNCalendarNotificationTrigger)
        #expect(trigger.repeats == false)
        #expect(trigger.dateComponents.day == 23) // tomorrow, not today
        #expect(trigger.dateComponents.hour == 8)
    }

    @Test func untakenFiresTodayBeforeReminderTime() throws {
        let context = try makeContext()
        context.insert(supplement("Creatine", minutes: 480, orderIndex: 0))
        try context.save()

        let requests = NotificationService.supplementReminderRequests(
            context: context, now: wednesday(hour: 6)
        )
        let trigger = try #require(requests.first?.trigger as? UNCalendarNotificationTrigger)
        #expect(trigger.dateComponents.day == 22)
        #expect(trigger.dateComponents.hour == 8)
        #expect(trigger.dateComponents.minute == 0)
    }
}
