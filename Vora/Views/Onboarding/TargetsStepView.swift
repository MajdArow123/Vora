//
//  TargetsStepView.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import SwiftUI

struct TargetsStepView: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    Text("Daily targets")
                        .font(DesignSystem.Typography.screenTitle)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                    Text("Suggested from your stats and goal — adjust anything.")
                        .font(DesignSystem.Typography.body)
                        .foregroundStyle(DesignSystem.Colors.textPrimary.opacity(0.6))
                }

                VStack(spacing: 0) {
                    targetRow(label: "Calories", text: $viewModel.caloriesText, unit: "kcal")
                    Divider()
                    targetRow(label: "Protein", text: $viewModel.proteinText, unit: "g")
                    Divider()
                    targetRow(label: "Carbs", text: $viewModel.carbsText, unit: "g")
                    Divider()
                    targetRow(label: "Fat", text: $viewModel.fatText, unit: "g")
                    Divider()
                    targetRow(label: "Water", text: $viewModel.waterText, unit: "ml")
                }
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.bottom, DesignSystem.Spacing.lg)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func targetRow(label: String, text: Binding<String>, unit: String) -> some View {
        HStack {
            Text(label)
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            Spacer()

            TextField("0", text: text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .font(DesignSystem.Typography.headline)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .frame(width: 80)

            Text(unit)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textPrimary.opacity(0.5))
                .frame(width: 32, alignment: .leading)
        }
        .padding(DesignSystem.Spacing.md)
    }
}

#Preview {
    TargetsStepView(viewModel: OnboardingViewModel())
        .background(DesignSystem.Colors.background)
}
