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
            VStack(alignment: .leading, spacing: 4) {
                Text(suggestion.mealName)
                    .font(DesignSystem.Typography.headline)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                if !suggestion.detail.isEmpty {
                    Text(suggestion.detail)
                        .font(DesignSystem.Typography.body)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
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
}

#Preview("Loaded") {
    MealSuggestionCard(
        state: .loaded(MealSuggestion(
            rawText: "Chicken & Rice Bowl\n200g chicken breast + 1 cup rice + side salad",
            generatedAt: .now
        )),
        onRefresh: {}
    )
    .padding()
    .background(DesignSystem.Colors.background)
}

#Preview("Loading") {
    MealSuggestionCard(state: .loading, onRefresh: {})
        .padding()
        .background(DesignSystem.Colors.background)
}

#Preview("Failed") {
    MealSuggestionCard(
        state: .failed("Couldn't generate suggestion. Check your connection."),
        onRefresh: {}
    )
    .padding()
    .background(DesignSystem.Colors.background)
}
