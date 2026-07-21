//
//  SummaryStepView.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import SwiftUI

struct SummaryStepView: View {
    let viewModel: OnboardingViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    Text("Ready to go")
                        .font(DesignSystem.Typography.screenTitle)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                    Text("A quick look at your setup. You can change all of this later.")
                        .font(DesignSystem.Typography.body)
                        .foregroundStyle(DesignSystem.Colors.textPrimary.opacity(0.6))
                }

                summaryCard("You") {
                    summaryRow("Name", viewModel.trimmedName)
                    summaryRow("Age", "\(viewModel.age)")
                    summaryRow("Height", viewModel.heightText)
                    summaryRow("Weight", viewModel.weightText)
                }

                summaryCard("Plan") {
                    summaryRow("Goal", viewModel.goalType?.displayName ?? "—")
                    summaryRow("Calories", "\(viewModel.caloriesText) kcal")
                    summaryRow("Protein", "\(viewModel.proteinText) g")
                    summaryRow("Carbs", "\(viewModel.carbsText) g")
                    summaryRow("Fat", "\(viewModel.fatText) g")
                    summaryRow("Water", "\(viewModel.waterText) ml")
                }

                summaryCard("Preferences") {
                    summaryRow("Units", viewModel.preferredUnits.displayName)
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.bottom, DesignSystem.Spacing.lg)
        }
    }

    private func summaryCard(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text(title)
                .font(DesignSystem.Typography.headline)
                .foregroundStyle(DesignSystem.Colors.textPrimary.opacity(0.5))
                .textCase(.uppercase)
                .font(DesignSystem.Typography.caption)

            VStack(spacing: DesignSystem.Spacing.sm) {
                content()
            }
            .padding(DesignSystem.Spacing.md)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
        }
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.textPrimary.opacity(0.6))
            Spacer()
            Text(value)
                .font(DesignSystem.Typography.headline)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
        }
    }
}

#Preview {
    SummaryStepView(viewModel: OnboardingViewModel())
        .background(DesignSystem.Colors.background)
}
