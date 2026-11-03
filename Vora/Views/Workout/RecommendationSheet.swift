//
//  RecommendationSheet.swift
//  Vora
//
//  Created by Majd Arow on 2026-11-02.
//

import SwiftUI

/// Amber warning with its one-tap fixes, shared by the exercise card and
/// the why sheet.
struct ProgressionWarningCard: View {
    let recommendation: Recommendation
    let units: UnitSystem
    let onFix: (ProgressionFix) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            ForEach(recommendation.warnings.indices, id: \.self) { index in
                Label {
                    Text(ProgressionExplanation.warning(recommendation.warnings[index], units: units))
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                        .accessibilityHidden(true)
                }
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.warning)
            }
            ForEach(recommendation.fixes.indices, id: \.self) { index in
                let fix = recommendation.fixes[index]
                Button {
                    onFix(fix)
                } label: {
                    Text(ProgressionExplanation.fixTitle(fix))
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(DesignSystem.Colors.warning.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(DesignSystem.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignSystem.Colors.warning.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small))
    }
}

/// Explains one set's recommendation in plain English.
struct RecommendationSheet: View {
    @Environment(\.dismiss) private var dismiss

    let exerciseName: String
    let setNumber: Int
    let recommendation: Recommendation
    let lastSessionText: String?
    let units: UnitSystem
    let onFix: (ProgressionFix) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.Colors.background
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(exerciseName), set \(setNumber)")
                                .font(DesignSystem.Typography.caption)
                                .foregroundStyle(DesignSystem.Colors.textSecondary)
                            Text("\(UnitConversion.liftWeightText(kg: recommendation.weightKg, units: units)) × \(recommendation.targetReps)")
                                .font(DesignSystem.Typography.title)
                                .foregroundStyle(DesignSystem.Colors.textPrimary)
                        }

                        Text(ProgressionExplanation.why(recommendation, units: units))
                            .font(DesignSystem.Typography.body)
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(DesignSystem.Spacing.md)
                            .background(DesignSystem.Colors.card)
                            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))

                        if let lastSessionText {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Last session")
                                    .font(DesignSystem.Typography.caption)
                                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                                    .textCase(.uppercase)
                                Text(lastSessionText)
                                    .font(DesignSystem.Typography.body)
                                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                            }
                            .accessibilityElement(children: .combine)
                        }

                        if !recommendation.warnings.isEmpty {
                            ProgressionWarningCard(recommendation: recommendation, units: units) { fix in
                                onFix(fix)
                                dismiss()
                            }
                        }
                    }
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    .padding(.vertical, DesignSystem.Spacing.md)
                }
            }
            .navigationTitle("Why this set")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(DesignSystem.Typography.headline)
                        .foregroundStyle(DesignSystem.Colors.accent)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview {
    RecommendationSheet(
        exerciseName: "Barbell Bench Press",
        setNumber: 1,
        recommendation: Recommendation(
            weightKg: 102.5,
            targetReps: 8,
            reason: .raiseLoad(fromKg: 100, toKg: 102.5, topReps: 12)
        ),
        lastSessionText: "100×12, 100×12, 100×12",
        units: .metric,
        onFix: { _ in }
    )
}
