//
//  AIMealSuggestionView.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-26.
//

import SwiftUI

/// Full AI meal suggestion sheet: remaining-macro summary, the suggestion,
/// refresh, and a handoff into food search. Opened from the Food diary
/// header and from the evening protein insight on Home.
struct AIMealSuggestionView: View {
    let remaining: RemainingMacros
    let goal: GoalType
    let logDate: Date

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = MealSuggestionViewModel()
    @State private var showingSearch = false

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.Colors.background
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                        summaryLine
                        content
                    }
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    .padding(.top, DesignSystem.Spacing.md)
                }
            }
            .navigationTitle("Meal Suggestion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
            }
        }
        .task { await load() }
        .sheet(isPresented: $showingSearch) {
            FoodSearchView(
                mealSlot: MealSlot.suggested(for: logDate),
                logDate: logDate,
                initialQuery: searchQuery
            )
        }
    }

    private var summaryLine: some View {
        Text("\(max(0, remaining.calories)) kcal · \(max(0, remaining.proteinG))g protein · \(max(0, remaining.carbsG))g carbs · \(max(0, remaining.fatG))g fat remaining")
            .font(DesignSystem.Typography.caption)
            .foregroundStyle(DesignSystem.Colors.textSecondary)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            card {
                ProgressView()
                    .tint(DesignSystem.Colors.accent)
                    .frame(maxWidth: .infinity, minHeight: 80)
            }

        case .loaded(let suggestion):
            card {
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

            secondaryButton("Refresh suggestion") {
                Task { await load(force: true) }
            }
            primaryButton("Search for these foods") { showingSearch = true }

        case .failed(let message):
            card {
                Text(message)
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                primaryButton("Retry") {
                    Task { await load(force: true) }
                }
            }
        }
    }

    private var searchQuery: String? {
        guard case .loaded(let suggestion) = viewModel.state else { return nil }
        return MealSuggestion.firstFoodName(in: suggestion.rawText)
    }

    private func load(force: Bool = false) async {
        await viewModel.load(remaining: remaining, goal: goal, force: force)
    }

    // MARK: - Chrome

    private func card(@ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            HStack(spacing: DesignSystem.Spacing.sm) {
                Image(systemName: "sparkles")
                    .font(.subheadline)
                    .foregroundStyle(DesignSystem.Colors.accent)
                    .accessibilityHidden(true)
                Text("Meal suggestion")
                    .font(DesignSystem.Typography.headline)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(DesignSystem.Typography.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(DesignSystem.Colors.accent)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func secondaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(DesignSystem.Typography.headline)
                .foregroundStyle(DesignSystem.Colors.accent)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(DesignSystem.Colors.accent.opacity(0.12))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    AIMealSuggestionView(
        remaining: RemainingMacros(calories: 700, proteinG: 55, carbsG: 60, fatG: 20),
        goal: .muscleGain,
        logDate: .now
    )
}
