//
//  LevelsMuscleDetailView.swift
//  Vora
//
//  Created by Majd Arow on 2026-11-02.
//

import SwiftUI

/// One muscle's weekly sets and the exercises behind them.
struct LevelsMuscleDetailView: View {
    let level: LevelsCalculator.MuscleLevel
    let range: LevelsCalculator.Range

    var body: some View {
        ZStack {
            DesignSystem.Colors.background
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: DesignSystem.Spacing.md) {
                    summaryCard
                    exercisesCard
                }
                .padding(.horizontal, DesignSystem.Spacing.md)
                .padding(.bottom, DesignSystem.Spacing.xl)
            }
        }
        .navigationTitle(level.muscle.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var summaryCard: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            BodyDiagramView(primaryMuscles: [level.muscle], secondaryMuscles: [])
                .frame(maxHeight: 200)
            VStack(spacing: 2) {
                Text("\(LevelsCalculator.setsText(level.setsPerWeek)) sets/week")
                    .font(DesignSystem.Typography.title)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Text("Average over \(range.phrase)")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
            .accessibilityElement(children: .combine)
        }
        .frame(maxWidth: .infinity)
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large))
    }

    private var exercisesCard: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Text("Exercises")
                .font(DesignSystem.Typography.headline)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            if level.contributors.isEmpty {
                Text("No sets for this muscle in \(range.phrase).")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            } else {
                ForEach(level.contributors) { contributor in
                    contributorRow(contributor)
                }
            }

            if level.contributors.contains(where: { $0.role == .secondary }) {
                Text("Sets for a secondary muscle count as half.")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
    }

    private func contributorRow(_ contributor: LevelsCalculator.Contributor) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(contributor.displayName)
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Text(contributor.role == .primary ? "Primary" : "Secondary")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(LevelsCalculator.setCountText(contributor.completedSets))
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Text("\(LevelsCalculator.setsText(contributor.setsPerWeek))/week")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
