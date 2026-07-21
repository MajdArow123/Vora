//
//  WelcomeStepView.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import SwiftUI

struct WelcomeStepView: View {
    var body: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            Spacer()

            ZStack {
                Circle()
                    .fill(DesignSystem.Colors.accent.opacity(0.15))
                    .frame(width: 120, height: 120)
                Image(systemName: "leaf.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(DesignSystem.Colors.accent)
            }

            Text("Vora")
                .font(DesignSystem.Typography.screenTitle)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            Text("Nutrition, training, and progress —\nall in one place.")
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.textPrimary.opacity(0.6))
                .multilineTextAlignment(.center)

            Spacer()
            Spacer()
        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
    }
}

#Preview {
    WelcomeStepView()
        .background(DesignSystem.Colors.background)
}
