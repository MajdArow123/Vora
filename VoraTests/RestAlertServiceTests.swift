//
//  RestAlertServiceTests.swift
//  VoraTests
//
//  Created by Majd Arow on 2026-11-03.
//

import Foundation
import Testing
import UserNotifications
@testable import Vora

private struct AddFailed: Error {}

struct RestAlertServiceTests {
    private static let now = Date(timeIntervalSinceReferenceDate: 815_780_000)
    private static let id = RestAlertService.notificationId

    private func service(_ center: StubNotificationCenter) -> RestAlertService {
        RestAlertService(center: center, now: { Self.now })
    }

    private func settled(_ alert: RestAlertService) async {
        await alert.pendingWork?.value
    }

    @Test func schedulesAtTheEndOfTheRest() async throws {
        let center = StubNotificationCenter()
        let alert = service(center)
        alert.schedule(at: Self.now.addingTimeInterval(90), body: "Bench: 80 kg × 8")
        await settled(alert)

        let request = try #require(center.pending[Self.id])
        #expect(request.content.title == "Rest over")
        #expect(request.content.body == "Bench: 80 kg × 8")
        #expect(request.content.sound != nil)
        let trigger = try #require(request.trigger as? UNTimeIntervalNotificationTrigger)
        #expect(trigger.timeInterval == 90)
        #expect(!trigger.repeats)
    }

    @Test func aNewScheduleReplacesTheOldOne() async throws {
        let center = StubNotificationCenter()
        let alert = service(center)
        alert.schedule(at: Self.now.addingTimeInterval(90), body: "First")
        await settled(alert)
        alert.schedule(at: Self.now.addingTimeInterval(105), body: "Second")
        await settled(alert)

        #expect(center.pending.count == 1)
        let request = try #require(center.pending[Self.id])
        #expect(request.content.body == "Second")
        let trigger = try #require(request.trigger as? UNTimeIntervalNotificationTrigger)
        #expect(trigger.timeInterval == 105)
    }

    @Test func aFasterChangeOnlyAddsTheLatest() async throws {
        let center = StubNotificationCenter()
        let alert = service(center)
        alert.schedule(at: Self.now.addingTimeInterval(90), body: "First")
        alert.schedule(at: Self.now.addingTimeInterval(105), body: "Second")
        await settled(alert)

        #expect(center.addCount == 1)
        #expect(center.pending[Self.id]?.content.body == "Second")
    }

    @Test func cancelRemovesIt() async {
        let center = StubNotificationCenter()
        let alert = service(center)
        alert.schedule(at: Self.now.addingTimeInterval(90), body: "Rest")
        await settled(alert)
        alert.cancel()

        #expect(center.pending.isEmpty)
    }

    @Test func aSkipDuringThePermissionCheckLeavesNothing() async {
        let center = StubNotificationCenter()
        let alert = service(center)
        alert.schedule(at: Self.now.addingTimeInterval(90), body: "Rest")
        alert.cancel()
        await settled(alert)

        #expect(center.addCount == 0)
        #expect(center.pending.isEmpty)
    }

    @Test func aSkipWhileAddingLeavesNothing() async {
        let center = StubNotificationCenter()
        let alert = service(center)
        center.onAdd = { alert.cancel() }
        alert.schedule(at: Self.now.addingTimeInterval(90), body: "Rest")
        await settled(alert)

        #expect(center.addCount == 1)
        #expect(center.pending.isEmpty)
    }

    @Test(arguments: [UNAuthorizationStatus.denied, .notDetermined])
    func nothingIsScheduledWithoutPermission(status: UNAuthorizationStatus) async {
        let center = StubNotificationCenter(status: status)
        let alert = service(center)
        alert.schedule(at: Self.now.addingTimeInterval(90), body: "Rest")
        await settled(alert)

        #expect(center.addCount == 0)
    }

    @Test(arguments: [UNAuthorizationStatus.authorized, .provisional, .ephemeral])
    func grantedPermissionSchedules(status: UNAuthorizationStatus) async {
        let center = StubNotificationCenter(status: status)
        let alert = service(center)
        alert.schedule(at: Self.now.addingTimeInterval(90), body: "Rest")
        await settled(alert)

        #expect(center.addCount == 1)
    }

    @Test func aTimeAlreadyPastSchedulesNothing() async {
        let center = StubNotificationCenter()
        let alert = service(center)
        alert.schedule(at: Self.now, body: "Rest")
        await settled(alert)

        // A zero-second trigger would throw when it's created.
        #expect(center.addCount == 0)
    }

    @Test func aFailedAddIsSurvived() async {
        let center = StubNotificationCenter()
        center.addError = AddFailed()
        let alert = service(center)
        alert.schedule(at: Self.now.addingTimeInterval(90), body: "Rest")
        await settled(alert)

        #expect(center.addCount == 1)
        #expect(center.pending.isEmpty)
    }

    /// A rest that runs out with the app alive is cancelled as the alert fires.
    @Test func cancelLeavesAnAlertAlreadyDelivered() {
        let center = StubNotificationCenter()
        service(center).cancel()

        #expect(center.deliveredRemovals == 0)
    }

    @Test func aNewRestClearsTheOldDeliveredAlert() async {
        let center = StubNotificationCenter()
        let alert = service(center)
        alert.schedule(at: Self.now.addingTimeInterval(90), body: "Rest")
        await settled(alert)

        #expect(center.deliveredRemovals == 1)
    }
}
