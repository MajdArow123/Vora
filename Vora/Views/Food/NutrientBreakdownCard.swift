//
//  NutrientBreakdownCard.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import SwiftUI

struct NutrientBreakdownCard: View {
    let fibreG: Double
    let sugarG: Double
    let sodiumMg: Double

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text("Nutrients")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .textCase(.uppercase)

            VStack(spacing: DesignSystem.Spacing.sm) {
                row("Fibre", value: "\(Int(fibreG.rounded())) g")
                Divider()
                row("Sugar", value: "\(Int(sugarG.rounded())) g")
                Divider()
                row("Sodium", value: "\(Int(sodiumMg.rounded())) mg")
            }
            .padding(DesignSystem.Spacing.md)
            .background(DesignSystem.Colors.card)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
        }
    }

    private func row(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
            Spacer()
            Text(value)
                .font(DesignSystem.Typography.headline)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
        }
    }
}

#Preview {
    NutrientBreakdownCard(fibreG: 24, sugarG: 61, sodiumMg: 1840)
        .padding()
        .background(DesignSystem.Colors.background)
}
