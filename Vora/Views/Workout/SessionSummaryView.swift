//
//  SessionSummaryView.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import SwiftUI

struct SessionSummaryView: View {
    let summary: SessionSummary
    let units: UnitSystem

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            DesignSystem.Colors.background
                .ignoresSafeArea()

            VStack(spacing: DesignSystem.Spacing.lg) {
                ScrollView {
                    content
                }
                .defaultScrollAnchor(.center)
                .scrollBounceBehavior(.basedOnSize)

                PrimaryButton(title: "Done") { dismiss() }
            }
            .padding(DesignSystem.Spacing.lg)
        }
        .interactiveDismissDisabled(false)
    }

    private var content: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
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
                    stat(value: UnitConversion.volumeText(kg: summary.totalVolumeKg, units: units), label: "Volume")
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
                            ForEach(groupedPRs, id: \.first?.exerciseKey) { records in
                                recordRow(records)
                            }
                        }
                        .padding(DesignSystem.Spacing.md)
                        .background(DesignSystem.Colors.card)
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
                    }
                }
        }
    }

    /// One group per exercise, in session order.
    private var groupedPRs: [[SessionPR]] {
        var order: [String] = []
        var groups: [String: [SessionPR]] = [:]
        for pr in summary.newPRs {
            if groups[pr.exerciseKey] == nil { order.append(pr.exerciseKey) }
            groups[pr.exerciseKey, default: []].append(pr)
        }
        return order.compactMap { groups[$0] }
    }

    private func recordRow(_ records: [SessionPR]) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.sm) {
            Image(systemName: "trophy.fill")
                .foregroundStyle(DesignSystem.Colors.macroFat)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(records.first?.exerciseName ?? "")
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                ForEach(records) { pr in
                    HStack {
                        Text(Self.kindTitle(pr.kind))
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                        Spacer()
                        Text(Self.valueText(pr, units: units))
                            .font(DesignSystem.Typography.headline)
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    static func kindTitle(_ kind: PersonalRecordKind) -> String {
        switch kind {
        case .weight: "Weight PR"
        case .reps: "Rep PR"
        case .estimatedOneRepMax: "Est. 1RM PR"
        }
    }

    static func valueText(_ pr: SessionPR, units: UnitSystem) -> String {
        switch pr.kind {
        case .weight, .reps:
            let weight = pr.weightKg > 0 ? UnitConversion.liftWeightText(kg: pr.weightKg, units: units) : "Bodyweight"
            return "\(weight) × \(pr.reps)"
        case .estimatedOneRepMax:
            return UnitConversion.liftWeightText(kg: pr.estimatedOneRepMax, units: units)
        }
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
        newPRs: [SessionPR(exerciseName: "Back Squat", exerciseId: "back-squat", kind: .weight, weightKg: 120, reps: 5)]
    ), units: .metric)
}
