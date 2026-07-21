//
//  TrainingSplitStepView.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import SwiftUI

struct TrainingSplitStepView: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    Text("How do you train?")
                        .font(DesignSystem.Typography.screenTitle)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                    Text("Vora organizes your workout logging around your split.")
                        .font(DesignSystem.Typography.body)
                        .foregroundStyle(DesignSystem.Colors.textPrimary.opacity(0.6))
                }

                VStack(spacing: DesignSystem.Spacing.sm) {
                    ForEach(TrainingSplit.allCases, id: \.self) { split in
                        splitCard(split)
                    }
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.bottom, DesignSystem.Spacing.lg)
        }
    }

    private func splitCard(_ split: TrainingSplit) -> some View {
        let isSelected = viewModel.trainingSplit == split
        return Button {
            viewModel.trainingSplit = split
        } label: {
            HStack(spacing: DesignSystem.Spacing.md) {
                Image(systemName: icon(for: split))
                    .font(.title3)
                    .foregroundStyle(DesignSystem.Colors.accent)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(split.displayName)
                        .font(DesignSystem.Typography.headline)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                    Text(split.detail)
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

    private func icon(for split: TrainingSplit) -> String {
        switch split {
        case .upperLower: "square.split.2x1"
        case .ppl: "arrow.3.trianglepath"
        case .fullBody: "figure.mixed.cardio"
        case .custom: "slider.horizontal.3"
        }
    }
}

#Preview {
    TrainingSplitStepView(viewModel: OnboardingViewModel())
        .background(DesignSystem.Colors.background)
}
