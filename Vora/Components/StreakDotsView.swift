//
//  StreakDotsView.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import SwiftUI

/// Streak card with seven dots per row for the trailing week, oldest
/// first — filled when that day's habit was kept. Shows the workout
/// row alone, or workout + food rows when food dots are provided.
struct StreakDotsView: View {
    /// Trained flags, oldest first; index 6 is today.
    let weekDots: [Bool]
    var streakDays: Int = 0
    /// Fully-logged-food flags, oldest first; nil hides the food row.
    var foodDots: [Bool]? = nil
    var foodStreakDays: Int = 0

    private var dayLetters: [String] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        return (0..<7).map { offset in
            guard let day = cal.date(byAdding: .day, value: offset - 6, to: today) else { return "" }
            return day.formatted(.dateTime.weekday(.narrow))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            if let foodDots {
                Text("Streaks")
                    .font(DesignSystem.Typography.headline)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                streakRow(
                    icon: "dumbbell.fill",
                    label: "Workout",
                    dots: weekDots,
                    days: streakDays,
                    showsDayLetters: false
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Workout streak")
                .accessibilityValue(summary(dots: weekDots, days: streakDays, kept: "trained"))

                streakRow(
                    icon: "fork.knife",
                    label: "Food",
                    dots: foodDots,
                    days: foodStreakDays,
                    showsDayLetters: true
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Food streak")
                .accessibilityValue(summary(dots: foodDots, days: foodStreakDays, kept: "logged 3 or more meals"))
            } else {
                HStack {
                    Text("Streak")
                        .font(DesignSystem.Typography.headline)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                    Spacer()
                    streakChip(days: streakDays)
                }
                dotRow(dots: weekDots, showsDayLetters: true)
            }
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
        .accessibilityElement(children: foodDots == nil ? .ignore : .contain)
        .accessibilityLabel(foodDots == nil ? "Workout streak" : "Streaks")
        .accessibilityValue(foodDots == nil ? summary(dots: weekDots, days: streakDays, kept: "trained") : "")
    }

    // MARK: - Rows

    private func streakRow(icon: String, label: String, dots: [Bool], days: Int, showsDayLetters: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(DesignSystem.Colors.accent)
                Text(label)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                Spacer()
                streakChip(days: days)
            }
            dotRow(dots: dots, showsDayLetters: showsDayLetters)
        }
    }

    @ViewBuilder
    private func streakChip(days: Int) -> some View {
        if days > 0 {
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .font(.caption)
                Text("\(days) day\(days == 1 ? "" : "s")")
                    .font(DesignSystem.Typography.caption)
            }
            .foregroundStyle(DesignSystem.Colors.accent)
        }
    }

    private func dotRow(dots: [Bool], showsDayLetters: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(dots.enumerated()), id: \.offset) { index, kept in
                VStack(spacing: 6) {
                    Circle()
                        .fill(kept
                              ? DesignSystem.Colors.accent
                              : DesignSystem.Colors.accent.opacity(0.15))
                        .frame(width: 14, height: 14)
                    if showsDayLetters {
                        Text(dayLetters.indices.contains(index) ? dayLetters[index] : "")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(index == 6
                                             ? DesignSystem.Colors.textPrimary
                                             : DesignSystem.Colors.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func summary(dots: [Bool], days: Int, kept: String) -> String {
        let count = dots.filter { $0 }.count
        let streak = days > 0 ? "\(days) day streak" : "No streak"
        return "\(streak), \(kept) \(count) of the last 7 days"
    }
}

#Preview("Workout + food") {
    StreakDotsView(
        weekDots: [true, false, true, true, false, true, true],
        streakDays: 4,
        foodDots: [true, true, true, false, true, true, false],
        foodStreakDays: 2
    )
    .padding()
    .background(DesignSystem.Colors.background)
}

#Preview("Workout only") {
    StreakDotsView(weekDots: [true, false, true, true, false, true, true], streakDays: 4)
        .padding()
        .background(DesignSystem.Colors.background)
}
