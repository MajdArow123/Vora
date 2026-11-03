//
//  WeeklyCheckInCard.swift
//  Vora
//
//  Created by Majd Arow on 2026-11-02.
//

import SwiftUI

/// Home's offer to review expenditure and targets. Empty when no check-in is due.
struct WeeklyCheckInCard: View {
    let state: WeeklyCheckInState
    let onOpen: () -> Void

    var body: some View {
        switch state {
        case .notDue:
            EmptyView()
        case .needsMoreData(let intakeDays, let neededIntakeDays, let weighIns, let neededWeighIns):
            content(
                detail: ExpenditureExplanation.moreDataNeeded(
                    intakeDays: intakeDays,
                    neededIntakeDays: neededIntakeDays,
                    weighIns: weighIns,
                    neededWeighIns: neededWeighIns
                ),
                showsChevron: false
            )
            .accessibilityElement(children: .combine)
        case .ready(let proposal):
            Button(action: onOpen) {
                content(
                    detail: "New estimate: \(ExpenditureExplanation.kcal(proposal.result.estimate)) a day. Review your targets.",
                    showsChevron: true
                )
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows your new expenditure and proposed targets")
        }
    }

    private func content(detail: String, showsChevron: Bool) -> some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            Image(systemName: "flame.fill")
                .font(.title3)
                .foregroundStyle(DesignSystem.Colors.accent)
                .frame(width: 36, height: 36)
                .background(DesignSystem.Colors.accent.opacity(0.12))
                .clipShape(Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Weekly check-in")
                    .font(DesignSystem.Typography.headline)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Text(detail)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(DesignSystem.Spacing.md)
        .frame(maxWidth: .infinity)
        .background(DesignSystem.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
        .contentShape(Rectangle())
    }
}
