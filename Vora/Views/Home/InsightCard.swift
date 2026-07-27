//
//  InsightCard.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import SwiftUI

struct InsightCard: View {
    let insight: Insight
    /// When set, the card becomes a button (used by the AI meal
    /// suggestion insight to open the suggestion sheet).
    var onTap: (() -> Void)? = nil

    var body: some View {
        if let onTap {
            Button(action: onTap) {
                content(showsChevron: true)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens AI meal suggestion")
        } else {
            content(showsChevron: false)
        }
    }

    private func content(showsChevron: Bool) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            Image(systemName: insight.iconName)
                .font(.title3)
                .foregroundStyle(DesignSystem.Colors.accent)
                .frame(width: 36, height: 36)
                .background(DesignSystem.Colors.accent.opacity(0.12))
                .clipShape(Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(insight.title)
                    .font(DesignSystem.Typography.headline)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Text(insight.message)
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if showsChevron {
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .frame(maxHeight: .infinity)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    VStack {
        InsightCard(insight: Insight(
            rule: .proteinGap,
            title: "Protein is behind",
            message: "It is past 2pm and you are under half your protein target — 82 g still to go.",
            iconName: "fork.knife"
        ))
        InsightCard(
            insight: Insight(
                rule: .aiProteinSuggestion,
                title: "Protein gap tonight",
                message: "You still need 55g of protein today. Tap for an AI meal suggestion.",
                iconName: "sparkles"
            ),
            onTap: {}
        )
    }
    .padding()
    .background(DesignSystem.Colors.background)
}
