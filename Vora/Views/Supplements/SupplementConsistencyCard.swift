//
//  SupplementConsistencyCard.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-26.
//

import SwiftUI

/// Progress-tab card: streak of days on which every supplement was taken,
/// a trailing-week dot row, and this month's consistency percentage.
struct SupplementConsistencyCard: View {
    let streakDays: Int
    /// All-taken flags, oldest first; index 6 is today.
    let weekDots: [Bool]
    let monthPercent: Int

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
            HStack {
                Text("Supplement consistency")
                    .font(DesignSystem.Typography.headline)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Spacer()
                if streakDays > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                            .font(.caption)
                        Text("\(streakDays) day\(streakDays == 1 ? "" : "s")")
                            .font(DesignSystem.Typography.caption)
                    }
                    .foregroundStyle(DesignSystem.Colors.accent)
                }
            }

            dotRow

            Text("\(monthPercent)% this month")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Supplement consistency")
        .accessibilityValue(
            "\(streakDays > 0 ? "\(streakDays) day streak" : "No streak"), "
            + "all taken \(weekDots.filter { $0 }.count) of the last 7 days, "
            + "\(monthPercent) percent this month"
        )
    }

    private var dotRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(weekDots.enumerated()), id: \.offset) { index, kept in
                VStack(spacing: 6) {
                    Circle()
                        .fill(kept
                              ? DesignSystem.Colors.accent
                              : DesignSystem.Colors.accent.opacity(0.15))
                        .frame(width: 14, height: 14)
                    Text(dayLetters.indices.contains(index) ? dayLetters[index] : "")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(index == 6
                                         ? DesignSystem.Colors.textPrimary
                                         : DesignSystem.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

#Preview {
    SupplementConsistencyCard(
        streakDays: 5,
        weekDots: [true, true, false, true, true, true, true],
        monthPercent: 84
    )
    .padding()
    .background(DesignSystem.Colors.background)
}
