//
//  GoalStepView.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import SwiftUI

struct GoalStepView: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    Text("Your goal")
                        .font(DesignSystem.Typography.screenTitle)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                    Text("Vora tunes your calorie and macro targets around this.")
                        .font(DesignSystem.Typography.body)
                        .foregroundStyle(DesignSystem.Colors.textPrimary.opacity(0.6))
                }

                VStack(spacing: DesignSystem.Spacing.sm) {
                    goalCard(.fatLoss, icon: "flame.fill", detail: "Lose fat while keeping muscle")
                    goalCard(.maintain, icon: "equal.circle.fill", detail: "Hold steady and build habits")
                    goalCard(.muscleGain, icon: "dumbbell.fill", detail: "Build muscle with a lean surplus")
                }

                Text("How active are you?")
                    .font(DesignSystem.Typography.title)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                VStack(spacing: DesignSystem.Spacing.sm) {
                    ForEach(ActivityLevel.allCases, id: \.self) { level in
                        activityRow(level)
                    }
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.bottom, DesignSystem.Spacing.lg)
        }
    }

    private func goalCard(_ goal: GoalType, icon: String, detail: String) -> some View {
        let isSelected = viewModel.goalType == goal
        return Button {
            viewModel.goalType = goal
        } label: {
            HStack(spacing: DesignSystem.Spacing.md) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(DesignSystem.Colors.accent)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(goal.displayName)
                        .font(DesignSystem.Typography.headline)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                    Text(detail)
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textPrimary.opacity(0.6))
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected
                                     ? DesignSystem.Colors.accent
                                     : DesignSystem.Colors.textPrimary.opacity(0.2))
            }
            .padding(DesignSystem.Spacing.md)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                    .strokeBorder(isSelected ? DesignSystem.Colors.accent : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private func activityRow(_ level: ActivityLevel) -> some View {
        let isSelected = viewModel.activityLevel == level
        return Button {
            viewModel.activityLevel = level
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(level.displayName)
                        .font(DesignSystem.Typography.headline)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                    Text(level.detail)
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textPrimary.opacity(0.6))
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected
                                     ? DesignSystem.Colors.accent
                                     : DesignSystem.Colors.textPrimary.opacity(0.2))
            }
            .padding(DesignSystem.Spacing.md)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                    .strokeBorder(isSelected ? DesignSystem.Colors.accent : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    GoalStepView(viewModel: OnboardingViewModel())
        .background(DesignSystem.Colors.background)
}
