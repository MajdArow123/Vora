//
//  StepProgressIndicator.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import SwiftUI

struct StepProgressIndicator: View {
    let currentStep: Int
    let totalSteps: Int

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            ForEach(0..<totalSteps, id: \.self) { index in
                Capsule()
                    .fill(index <= currentStep
                          ? DesignSystem.Colors.accent
                          : DesignSystem.Colors.accent.opacity(0.2))
                    .frame(height: 4)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: currentStep)
    }
}

#Preview {
    StepProgressIndicator(currentStep: 1, totalSteps: 4)
        .padding()
        .background(DesignSystem.Colors.background)
}
