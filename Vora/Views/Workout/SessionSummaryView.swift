//
//  SessionSummaryView.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import SwiftUI

struct SessionSummaryView: View {
    let summary: SessionSummary

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            DesignSystem.Colors.background
                .ignoresSafeArea()

            VStack(spacing: DesignSystem.Spacing.lg) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(DesignSystem.Colors.accent.opacity(0.15))
                        .frame(width: 96, height: 96)
                    Image(systemName: "checkmark")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(DesignSystem.Colors.accent)
                }
                .accessibilityHidden(true)

                Text("Session Complete")
                    .font(DesignSystem.Typography.screenTitle)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                HStack(spacing: DesignSystem.Spacing.md) {
                    stat(value: ActiveSessionView.timeString(summary.durationSeconds), label: "Duration")
                    stat(value: "\(Int(summary.totalVolumeKg.rounded())) kg", label: "Volume")
                    stat(value: "\(summary.exerciseCount)", label: "Exercises")
                    stat(value: "\(summary.setCount)", label: "Sets")
                }

                if !summary.newPRs.isEmpty {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                        Text("New Personal Records")
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                            .textCase(.uppercase)

                        VStack(spacing: DesignSystem.Spacing.sm) {
                            ForEach(summary.newPRs) { pr in
                                HStack {
                                    Image(systemName: "trophy.fill")
                                        .foregroundStyle(DesignSystem.Colors.macroFat)
                                        .accessibilityHidden(true)
                                    Text(pr.exerciseName)
                                        .font(DesignSystem.Typography.body)
                                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                                    Spacer()
                                    Text("\(ActiveSessionViewModel.weightString(pr.weightKg)) kg × \(pr.reps)")
                                        .font(DesignSystem.Typography.headline)
                                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                                }
                            }
                        }
                        .padding(DesignSystem.Spacing.md)
                        .background(DesignSystem.Colors.card)
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
                    }
                }

                Spacer()

                PrimaryButton(title: "Done") { dismiss() }
            }
            .padding(DesignSystem.Spacing.lg)
        }
        .interactiveDismissDisabled(false)
    }

    private func stat(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(DesignSystem.Typography.headline)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    SessionSummaryView(summary: SessionSummary(
        durationSeconds: 3480,
        totalVolumeKg: 6420,
        exerciseCount: 6,
        setCount: 18,
        newPRs: [PersonalRecord(exerciseName: "Back Squat", weightKg: 120, reps: 5, date: .now)]
    ))
}
