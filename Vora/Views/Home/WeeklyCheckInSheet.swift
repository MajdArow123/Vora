//
//  WeeklyCheckInSheet.swift
//  Vora
//
//  Created by Majd Arow on 2026-11-02.
//

import SwiftUI

/// Old vs new expenditure, why it changed, and the proposed targets. Only
/// Apply changes the targets.
struct WeeklyCheckInSheet: View {
    @Environment(\.dismiss) private var dismiss

    let proposal: ExpenditureProposal
    let units: UnitSystem
    let onApply: () throws -> Void
    let onSkip: () throws -> Void

    @State private var saveFailed = false

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.Colors.background
                    .ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                        expenditureCard
                        whyCard
                        ForEach(ExpenditureExplanation.notes(proposal), id: \.self) { note in
                            InfoCallout(text: note)
                        }
                        targetsCard
                        PrimaryButton(title: "Apply new targets") { answer(onApply) }
                        GhostButton(title: "Skip this week") { answer(onSkip) }
                    }
                    .padding(.horizontal, DesignSystem.Spacing.md)
                    .padding(.vertical, DesignSystem.Spacing.md)
                }
            }
            .navigationTitle("Weekly check-in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Later") { dismiss() }
                        .font(DesignSystem.Typography.headline)
                        .foregroundStyle(DesignSystem.Colors.accent)
                }
            }
            .alert("Couldn't save your check-in", isPresented: $saveFailed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Your targets haven't changed. Please try again.")
            }
        }
    }

    private func answer(_ action: () throws -> Void) {
        do {
            try action()
            dismiss()
        } catch {
            saveFailed = true
        }
    }

    private var expenditureCard: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text("Daily expenditure")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .textCase(.uppercase)
            HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.sm) {
                Text(ExpenditureExplanation.kcal(proposal.previousEstimate))
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .accessibilityLabel("to")
                Text(ExpenditureExplanation.kcal(proposal.result.estimate))
                    .font(DesignSystem.Typography.title)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
            }
            Text(ExpenditureExplanation.summary(proposal, units: units))
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large))
    }

    @ViewBuilder
    private var whyCard: some View {
        let result = proposal.result
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text("Why it changed")
                .font(DesignSystem.Typography.headline)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
            if let intake = result.averageIntake {
                row("Average intake", ExpenditureExplanation.kcal(intake))
            }
            if let slope = result.slopeKgPerDay {
                row("Weight change", ExpenditureExplanation.weeklyRate(slopeKgPerDay: slope, units: units))
            }
            row("Days logged", ExpenditureExplanation.daysLogged(result.daysUsed))
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
    }

    private var targetsCard: some View {
        let current = proposal.currentTargets
        let proposed = proposal.proposedTargets
        return VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text("Proposed targets")
                .font(DesignSystem.Typography.headline)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
            row("Calories", "\(current.calories) → \(proposed.calories) kcal")
            row("Protein", "\(current.proteinG) → \(proposed.proteinG) g")
            row("Carbs", "\(current.carbsG) → \(proposed.carbsG) g")
            row("Fat", "\(current.fatG) → \(proposed.fatG) g")
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
            Spacer()
            Text(value)
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
