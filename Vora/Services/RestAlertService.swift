//
//  RestAlertService.swift
//  Vora
//
//  Created by Majd Arow on 2026-11-03.
//

import Foundation
import os
import UserNotifications

/// Tells the user when rest is over. Injected so tests never schedule a real
/// notification.
protocol RestAlertScheduling {
    /// Schedules the alert, replacing any earlier one.
    func schedule(at endDate: Date, body: String)
    func cancel()
}

/// The view model's default, so only `ActiveSessionView` can reach the
/// notification center.
struct NoRestAlert: RestAlertScheduling {
    func schedule(at endDate: Date, body: String) {}
    func cancel() {}
}

/// The parts of `UNUserNotificationCenter` the rest alert uses.
protocol UserNotificationCentering {
    func authorizationStatus() async -> UNAuthorizationStatus
    func add(_ request: UNNotificationRequest) async throws
    func removePendingRequests(withIdentifiers identifiers: [String])
    func removeDeliveredNotifications(withIdentifiers identifiers: [String])
}

struct LiveUserNotificationCenter: UserNotificationCentering {
    private var center: UNUserNotificationCenter { .current() }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func add(_ request: UNNotificationRequest) async throws {
        try await center.add(request)
    }

    func removePendingRequests(withIdentifiers identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }
}

/// A one-shot local notification at the rest's end. It never asks for
/// permission: `NotificationService.refreshAll` does that at launch, and a
/// refusal here just means no alert.
final class RestAlertService: RestAlertScheduling {
    static let notificationId = "vora.restOver"

    private static let logger = Logger(subsystem: "com.majdarow.Vora", category: "RestAlert")

    private let center: any UserNotificationCentering
    private let now: () -> Date
    /// Bumped by every call, so one still checking permission can tell a
    /// newer schedule or a cancel has overtaken it.
    private var generation = 0
    private var isCancelled = false
    /// Readable so tests can await the work instead of guessing how long it takes.
    private(set) var pendingWork: Task<Void, Never>?

    init(center: any UserNotificationCentering = LiveUserNotificationCenter(), now: @escaping () -> Date = Date.init) {
        self.center = center
        self.now = now
    }

    func schedule(at endDate: Date, body: String) {
        generation += 1
        isCancelled = false
        let id = Self.notificationId
        center.removeDeliveredNotifications(withIdentifiers: [id])

        let scheduled = generation
        pendingWork = Task {
            let status = await center.authorizationStatus()
            guard scheduled == generation else { return }
            let interval = endDate.timeIntervalSince(now())
            guard Self.canAlert(status), interval > 0 else {
                center.removePendingRequests(withIdentifiers: [id])
                return
            }
            do {
                try await center.add(Self.request(body: body, interval: interval))
            } catch {
                Self.logger.error("Couldn't schedule the rest alert: \(String(describing: error), privacy: .public)")
            }
            // A cancel while the add was in flight has already run, so it
            // missed this request.
            if isCancelled {
                center.removePendingRequests(withIdentifiers: [id])
            }
        }
    }

    func cancel() {
        generation += 1
        isCancelled = true
        // Only the pending request: a rest that just ran out ends here too,
        // and its alert must stay. The next rest clears it.
        center.removePendingRequests(withIdentifiers: [Self.notificationId])
    }

    static func canAlert(_ status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional, .ephemeral: true
        case .denied, .notDetermined: false
        @unknown default: false
        }
    }

    static func request(body: String, interval: TimeInterval) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "Rest over"
        content.body = body
        content.sound = .default
        return UNNotificationRequest(
            identifier: notificationId,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        )
    }
}
