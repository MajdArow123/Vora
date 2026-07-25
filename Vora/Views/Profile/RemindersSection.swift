//
//  RemindersSection.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-25.
//

import SwiftData
import SwiftUI
import UserNotifications

/// The "Reminders" card in ProfileView: toggles and time pickers for the
/// three smart reminders plus the weekly summary. Settings are device
/// preferences in UserDefaults; any change reschedules notifications.
struct RemindersSection: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage(ReminderKind.meal.enabledKey) private var mealEnabled = false
    @AppStorage(ReminderKind.meal.timeKey) private var mealMinutes = ReminderKind.meal.defaultMinutes
    @AppStorage(ReminderKind.water.enabledKey) private var waterEnabled = false
    @AppStorage(ReminderKind.water.timeKey) private var waterMinutes = ReminderKind.water.defaultMinutes
    @AppStorage(ReminderKind.workout.enabledKey) private var workoutEnabled = false
    @AppStorage(ReminderKind.workout.timeKey) private var workoutMinutes = ReminderKind.workout.defaultMinutes
    @AppStorage(ReminderSettings.weeklySummaryEnabledKey) private var weeklySummaryEnabled = true

    @State private var authorizationDenied = false

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text("Reminders")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textPrimary.opacity(0.5))
                .textCase(.uppercase)

            VStack(spacing: DesignSystem.Spacing.sm) {
                if authorizationDenied {
                    deniedBanner
                }

                reminderRow(
                    kind: .meal,
                    enabled: $mealEnabled,
                    minutes: $mealMinutes,
                    condition: "if fewer than 2 meals logged"
                )
                Divider()
                reminderRow(
                    kind: .water,
                    enabled: $waterEnabled,
                    minutes: $waterMinutes,
                    condition: "if you're under half your water target"
                )
                Divider()
                reminderRow(
                    kind: .workout,
                    enabled: $workoutEnabled,
                    minutes: $workoutMinutes,
                    condition: "on training days if no session is logged"
                )
                Divider()
                weeklySummaryRow
            }
            .padding(DesignSystem.Spacing.md)
            .background(DesignSystem.Colors.card)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
        }
        .task { await checkAuthorization() }
        .onChange(of: scenePhase) { _, phase in
            // Re-check when returning from the iOS Settings app.
            guard phase == .active else { return }
            Task { await checkAuthorization() }
        }
        .onChange(of: settingsFingerprint) {
            NotificationService.shared.refreshAll(context: modelContext)
        }
    }

    // MARK: - Rows

    private func reminderRow(
        kind: ReminderKind,
        enabled: Binding<Bool>,
        minutes: Binding<Int>,
        condition: String
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            Toggle(isOn: enabled) {
                Text(kind.displayName)
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.textPrimary.opacity(0.6))
            }
            .tint(DesignSystem.Colors.accent)
            .frame(minHeight: 44)

            if enabled.wrappedValue {
                HStack {
                    Text("Time")
                        .font(DesignSystem.Typography.body)
                        .foregroundStyle(DesignSystem.Colors.textPrimary.opacity(0.6))
                    Spacer()
                    DatePicker(
                        "\(kind.displayName) time",
                        selection: timeBinding(minutes),
                        displayedComponents: .hourAndMinute
                    )
                    .labelsHidden()
                }
                .frame(minHeight: 44)

                Text("Will remind at \(timeText(minutes.wrappedValue)) \(condition)")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .padding(.bottom, DesignSystem.Spacing.xs)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: enabled.wrappedValue)
    }

    private var weeklySummaryRow: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            Toggle(isOn: $weeklySummaryEnabled) {
                Text("Weekly summary")
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.textPrimary.opacity(0.6))
            }
            .tint(DesignSystem.Colors.accent)
            .frame(minHeight: 44)

            if weeklySummaryEnabled {
                Text("Sundays at 7:00 PM")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .padding(.bottom, DesignSystem.Spacing.xs)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: weeklySummaryEnabled)
    }

    private var deniedBanner: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
            Image(systemName: "bell.slash.fill")
                .font(.caption)
                .foregroundStyle(DesignSystem.Colors.negative)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text("Notifications are off. Enable them in Settings to get reminders.")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignSystem.Spacing.sm)
        .background(DesignSystem.Colors.negative.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small))
    }

    // MARK: - Helpers

    /// Single value observed for changes so one onChange covers all settings.
    private var settingsFingerprint: String {
        [
            "\(mealEnabled)", "\(mealMinutes)",
            "\(waterEnabled)", "\(waterMinutes)",
            "\(workoutEnabled)", "\(workoutMinutes)",
            "\(weeklySummaryEnabled)",
        ].joined(separator: "|")
    }

    private func timeBinding(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding {
            date(fromMinutes: minutes.wrappedValue)
        } set: { newValue in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            minutes.wrappedValue = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        }
    }

    private func date(fromMinutes minutes: Int) -> Date {
        Calendar.current.date(
            bySettingHour: minutes / 60,
            minute: minutes % 60,
            second: 0,
            of: .now
        ) ?? .now
    }

    private func timeText(_ minutes: Int) -> String {
        date(fromMinutes: minutes).formatted(date: .omitted, time: .shortened)
    }

    private func checkAuthorization() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationDenied = settings.authorizationStatus == .denied
    }
}

#Preview {
    ScrollView {
        RemindersSection()
            .padding()
    }
    .background(DesignSystem.Colors.background)
}
