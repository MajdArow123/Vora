//
//  NotificationService.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import Foundation
import SwiftData
import UserNotifications

/// Schedules the Sunday-evening weekly summary as a local notification.
/// iOS cannot compute content at delivery time, so the summary is
/// rebuilt from current data every time the app comes to the foreground;
/// the pending request always carries the freshest stats.
final class NotificationService {
    static let shared = NotificationService()
    static let weeklySummaryId = "vora.weeklySummary"

    private init() {}

    func refreshWeeklySummary(context: ModelContext, now: Date = .now) {
        #if DEBUG
        // Keeps the permission alert out of App Store screenshot runs.
        if ProcessInfo.processInfo.arguments.contains("--suppress-notification-prompt") { return }
        #endif
        let center = UNUserNotificationCenter.current()
        let content = weeklySummaryContent(context: context, now: now)

        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            center.removePendingNotificationRequests(withIdentifiers: [Self.weeklySummaryId])
            center.add(Self.weeklySummaryRequest(content: content))
        }
    }

    /// Repeats every Sunday at 19:00 local time.
    static func weeklySummaryRequest(content: UNMutableNotificationContent) -> UNNotificationRequest {
        var components = DateComponents()
        components.weekday = 1 // Sunday
        components.hour = 19
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        return UNNotificationRequest(
            identifier: weeklySummaryId,
            content: content,
            trigger: trigger
        )
    }

    /// Internal (not private) so the content generation is unit-testable
    /// without touching UNUserNotificationCenter.
    func weeklySummaryContent(context: ModelContext, now: Date) -> UNMutableNotificationContent {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: now)
        let weekAgo = cal.date(byAdding: .day, value: -6, to: todayStart) ?? todayStart

        let sessions = (try? context.fetch(FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.date >= weekAgo }
        ))) ?? []
        let food = (try? context.fetch(FetchDescriptor<FoodEntry>(
            predicate: #Predicate { $0.date >= weekAgo }
        ))) ?? []
        let weights = (try? context.fetch(FetchDescriptor<WeightEntry>(
            predicate: #Predicate { $0.date >= weekAgo },
            sortBy: [SortDescriptor(\.date)]
        ))) ?? []

        var stats: [String] = []
        stats.append("\(sessions.count) workout\(sessions.count == 1 ? "" : "s")")

        let trackedDays = Set(food.map { cal.startOfDay(for: $0.date) })
        if !trackedDays.isEmpty {
            let avgKcal = food.reduce(0) { $0 + $1.calories } / Double(trackedDays.count)
            stats.append("avg \(Int(avgKcal.rounded())) kcal")
        }
        if let first = weights.first, let last = weights.last, first.id != last.id {
            stats.append(String(format: "%+.1f kg", last.weightKg - first.weightKg))
        }

        let trainingDays = ((try? context.fetch(FetchDescriptor<SplitDay>())) ?? [])
            .filter { !$0.isRest }
            .count

        let content = UNMutableNotificationContent()
        content.title = "Your week in review"
        content.body = "This week: \(stats.joined(separator: " · ")). "
            + (trainingDays > 0
               ? "Next week: \(trainingDays) training day\(trainingDays == 1 ? "" : "s") planned — show up for the first one."
               : "Set up your training split to plan next week.")
        content.sound = .default
        return content
    }
}
