//
//  MealSuggestionCard.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-26.
//

import SwiftUI

/// Home-screen card showing today's AI meal suggestion (or the loading
/// and failure states around it). Works out of the box — no setup.
struct MealSuggestionCard: View {
    let state: MealSuggestionViewModel.SuggestionState
    let onViewAndLog: () -> Void
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            header
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
    }

    private var header: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: "sparkles")
                .font(.subheadline)
                .foregroundStyle(DesignSystem.Colors.accent)
                .accessibilityHidden(true)
            Text("Meal suggestion")
                .font(DesignSystem.Typography.headline)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
            Spacer()
            if case .loaded = state {
                refreshButton
            }
        }
    }

    private var refreshButton: some View {
        Button(action: onRefresh) {
            Image(systemName: "arrow.clockwise")
                .font(.subheadline)
                .foregroundStyle(DesignSystem.Colors.accent)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("New suggestion")
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle, .loading:
            ProgressView()
                .tint(DesignSystem.Colors.accent)
                .frame(maxWidth: .infinity, minHeight: 60)

        case .loaded(let suggestion):
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                mealTypeBadge(suggestion.slot)
                VStack(alignment: .leading, spacing: 4) {
                    Text(suggestion.mealName)
                        .font(DesignSystem.Typography.headline)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                    if !suggestion.description.isEmpty {
                        Text(suggestion.description)
                            .font(DesignSystem.Typography.body)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                viewAndLogButton
            }

        case .failed(let message):
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                Text(message)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Retry", action: onRefresh)
                    .font(DesignSystem.Typography.headline)
                    .foregroundStyle(DesignSystem.Colors.accent)
                    .buttonStyle(.plain)
            }
        }
    }

    private func mealTypeBadge(_ slot: MealSlot) -> some View {
        Text("\(slot.displayName) suggestion")
            .font(DesignSystem.Typography.caption)
            .fontWeight(.semibold)
            .foregroundStyle(DesignSystem.Colors.accent)
            .padding(.horizontal, DesignSystem.Spacing.sm + 4)
            .padding(.vertical, 4)
            .background(DesignSystem.Colors.accent.opacity(0.12))
            .clipShape(Capsule())
    }

    private var viewAndLogButton: some View {
        Button(action: onViewAndLog) {
            HStack(spacing: DesignSystem.Spacing.xs) {
                Text("View & log")
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .accessibilityHidden(true)
            }
            .font(DesignSystem.Typography.headline)
            .foregroundStyle(DesignSystem.Colors.accent)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("View and log suggestion")
    }
}

#Preview("Loaded") {
    MealSuggestionCard(
        state: .loaded(MealSuggestion(
            mealName: "Chicken & Rice Bowl",
            mealType: "dinner",
            description: "A balanced bowl that closes most of your remaining protein gap.",
            foods: [
                SuggestedFood(name: "chicken breast", grams: 200, unit: "g"),
                SuggestedFood(name: "basmati rice", grams: 150, unit: "g"),
            ],
            cookingTip: "Rest the chicken for five minutes before slicing.",
            generatedAt: .now
        )),
        onViewAndLog: {},
        onRefresh: {}
    )
    .padding()
    .background(DesignSystem.Colors.background)
}

#Preview("Loading") {
    MealSuggestionCard(state: .loading, onViewAndLog: {}, onRefresh: {})
        .padding()
        .background(DesignSystem.Colors.background)
}

#Preview("Failed") {
    MealSuggestionCard(
        state: .failed("Couldn't generate suggestion. Check your connection."),
        onViewAndLog: {},
        onRefresh: {}
    )
    .padding()
    .background(DesignSystem.Colors.background)
}
