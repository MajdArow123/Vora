//
//  StreakDotsView.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import SwiftUI

/// Seven dots for the trailing week, oldest first — filled when a
/// workout was logged that day.
struct StreakDotsView: View {
    /// Trained flags, oldest first; index 6 is today.
    let weekDots: [Bool]
    var streakDays: Int = 0

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
                Text("Streak")
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

            HStack(spacing: 0) {
                ForEach(Array(weekDots.enumerated()), id: \.offset) { index, trained in
                    VStack(spacing: 6) {
                        Circle()
                            .fill(trained
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
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
    }
}

#Preview {
    StreakDotsView(weekDots: [true, false, true, true, false, true, true], streakDays: 4)
        .padding()
        .background(DesignSystem.Colors.background)
}
