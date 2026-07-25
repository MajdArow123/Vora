//
//  NotificationService.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import Foundation
import SwiftData
import UserNotifications

/// Schedules the weekly summary and the configurable smart reminders as
/// local notifications. iOS cannot compute content or evaluate conditions
/// at delivery time, so everything is rebuilt from current data every time
/// the app becomes active: reminders whose condition is already met today
/// are pushed to their next valid day, and message bodies always carry the
/// freshest stats. If the app is never reopened, at most one occurrence of
/// each reminder fires — a deliberate tradeoff over unconditional daily
/// repeats.
final class NotificationService {
    static let shared = NotificationService()
    static let weeklySummaryId = "vora.weeklySummary"

    private init() {}

    /// Re-evaluates and reschedules every notification. Call on scene
    /// activation and whenever reminder settings change.
    func refreshAll(context: ModelContext, now: Date = .now, settings: ReminderSettings = ReminderSettings()) {
        #if DEBUG
        // Keeps the permission alert out of App Store screenshot runs.
        if ProcessInfo.processInfo.arguments.contains("--suppress-notification-prompt") { return }
        #endif
        let center = UNUserNotificationCenter.current()
        let idsToClear = ReminderKind.allCases.map(\.notificationId) + [Self.weeklySummaryId]

        // Requests are built before the authorization callback because
        // ModelContext must stay on the calling thread.
        var requests: [UNNotificationRequest] = []
        if settings.weeklySummaryEnabled {
            requests.append(Self.weeklySummaryRequest(
                content: weeklySummaryContent(context: context, now: now)
            ))
        }
        for kind in ReminderKind.allCases where settings.isEnabled(kind) {
            if let request = Self.reminderRequest(
                kind: kind,
                context: context,
                minutes: settings.minutes(for: kind),
                now: now
            ) {
                requests.append(request)
            }
        }

        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            center.removePendingNotificationRequests(withIdentifiers: idsToClear)
            guard granted else { return }
            requests.forEach { center.add($0) }
        }
    }

    // MARK: - Smart reminders

    /// Builds the pending request for one reminder, or nil when there is no
    /// valid fire date (workout reminder with an all-rest split).
    static func reminderRequest(
        kind: ReminderKind,
        context: ModelContext,
        minutes: Int,
        now: Date
    ) -> UNNotificationRequest? {
        let trainingDays: Set<Int>? = kind == .workout ? trainingDayIndices(context: context) : nil

        let todayNeedsReminder: Bool
        switch kind {
        case .meal:
            todayNeedsReminder = mealSlotsLoggedToday(context: context, now: now) < 2
        case .water:
            let progress = waterProgressToday(context: context, now: now)
            todayNeedsReminder = progress.loggedMl < 0.5 * progress.targetMl
        case .workout:
            todayNeedsReminder = !hasTrainedToday(context: context, now: now)
        }

        guard let fireDate = nextFireDate(
            kind: kind,
            minutes: minutes,
            todayNeedsReminder: todayNeedsReminder,
            trainingDayIndices: trainingDays,
            now: now
        ) else { return nil }

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: fireDate
        )
        return UNNotificationRequest(
            identifier: kind.notificationId,
            content: reminderContent(kind: kind, fireDate: fireDate, context: context, now: now),
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
    }

    /// Pure date math: the next moment this reminder should fire. One-shot
    /// triggers are used instead of repeating ones because a repeating
    /// trigger cannot skip "just today" — cancelling it kills the series.
    /// `trainingDayIndices` restricts valid days (nil = every day is valid);
    /// an empty set means no day is ever valid.
    static func nextFireDate(
        kind: ReminderKind,
        minutes: Int,
        todayNeedsReminder: Bool,
        trainingDayIndices: Set<Int>?,
        now: Date,
        calendar: Calendar = .current
    ) -> Date? {
        func isValidDay(_ date: Date) -> Bool {
            guard let indices = trainingDayIndices else { return true }
            return indices.contains((calendar.component(.weekday, from: date) + 5) % 7)
        }

        let todayStart = calendar.startOfDay(for: now)
        if todayNeedsReminder, isValidDay(now),
           let candidate = calendar.date(byAdding: .minute, value: minutes, to: todayStart),
           candidate > now {
            return candidate
        }
        // Future days always "need" the reminder — they haven't happened yet.
        for offset in 1...7 {
            guard let dayStart = calendar.date(byAdding: .day, value: offset, to: todayStart) else { continue }
            if isValidDay(dayStart) {
                return calendar.date(byAdding: .minute, value: minutes, to: dayStart)
            }
        }
        return nil
    }

    /// Content is frozen at schedule time, so bodies that reference live data
    /// are built against the fire date: the workout title comes from the fire
    /// day's split, and water numbers are only embedded when firing today.
    static func reminderContent(
        kind: ReminderKind,
        fireDate: Date,
        context: ModelContext,
        now: Date
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        switch kind {
        case .meal:
            content.title = "Meal check-in"
            content.body = "You haven't logged lunch yet. Tap to open your food diary."
            content.userInfo = ["vora.destination": "diary"]
        case .water:
            content.title = "Hydration check"
            if Calendar.current.isDate(fireDate, inSameDayAs: now) {
                let progress = waterProgressToday(context: context, now: now)
                content.body = String(
                    format: "You're behind on water today. %.1fL logged of %.1fL.",
                    progress.loggedMl / 1000,
                    progress.targetMl / 1000
                )
            } else {
                content.body = "You're behind on water today. Tap to log your intake."
            }
            content.userInfo = ["vora.destination": "diary"]
        case .workout:
            let dayIndex = (Calendar.current.component(.weekday, from: fireDate) + 5) % 7
            let sessionName = splitTitle(forDayIndex: dayIndex, context: context) ?? "your workout"
            content.title = "Workout time"
            content.body = "Time for \(sessionName). Tap to start your session."
            content.userInfo = ["vora.destination": "workout"]
        }
        content.sound = .default
        return content
    }

    // MARK: - Condition evaluation

    /// Number of distinct meal slots with at least one entry today.
    static func mealSlotsLoggedToday(context: ModelContext, now: Date) -> Int {
        let (start, end) = todayBounds(for: now)
        let entries = (try? context.fetch(FetchDescriptor<FoodEntry>(
            predicate: #Predicate { $0.date >= start && $0.date < end }
        ))) ?? []
        return Set(entries.map(\.mealSlot)).count
    }

    static func waterProgressToday(context: ModelContext, now: Date) -> (loggedMl: Double, targetMl: Double) {
        let (start, end) = todayBounds(for: now)
        let entries = (try? context.fetch(FetchDescriptor<WaterEntry>(
            predicate: #Predicate { $0.date >= start && $0.date < end }
        ))) ?? []
        let target = ((try? context.fetch(FetchDescriptor<UserProfile>())) ?? [])
            .first?.waterTargetMl ?? 3500
        return (entries.reduce(0) { $0 + $1.amountMl }, target)
    }

    static func hasTrainedToday(context: ModelContext, now: Date) -> Bool {
        let (start, end) = todayBounds(for: now)
        let sessions = (try? context.fetch(FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.date >= start && $0.date < end }
        ))) ?? []
        return !sessions.isEmpty
    }

    /// Monday-first day indices (0 = Mon … 6 = Sun) of non-rest split days.
    static func trainingDayIndices(context: ModelContext) -> Set<Int> {
        let days = (try? context.fetch(FetchDescriptor<SplitDay>())) ?? []
        return Set(days.filter { !$0.isRest }.map(\.dayIndex))
    }

    static func splitTitle(forDayIndex dayIndex: Int, context: ModelContext) -> String? {
        let days = (try? context.fetch(FetchDescriptor<SplitDay>(
            predicate: #Predicate { $0.dayIndex == dayIndex }
        ))) ?? []
        return days.first?.title
    }

    private static func todayBounds(for now: Date) -> (start: Date, end: Date) {
        let cal = Calendar.current
        let start = cal.startOfDay(for: now)
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? start
        return (start, end)
    }

    // MARK: - Weekly summary

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
