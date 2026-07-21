//
//  CalorieRingView.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import SwiftUI

struct CalorieRingView: View {
    let consumed: Double
    let target: Int

    private var progress: Double {
        guard target > 0 else { return 0 }
        return min(consumed / Double(target), 1)
    }

    private var remaining: Int {
        target - Int(consumed.rounded())
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(DesignSystem.Colors.accent.opacity(0.15), lineWidth: 10)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    DesignSystem.Colors.accent,
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.6), value: progress)

            VStack(spacing: 2) {
                Text("\(abs(remaining))")
                    .font(.system(.title, weight: .bold))
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                    .contentTransition(.numericText())
                Text(remaining >= 0 ? "kcal left" : "kcal over")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
        }
        .frame(width: 128, height: 128)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Calories")
        .accessibilityValue(remaining >= 0
                            ? "\(Int(consumed.rounded())) of \(target) kilocalories eaten, \(remaining) remaining"
                            : "\(Int(consumed.rounded())) of \(target) kilocalories eaten, \(abs(remaining)) over")
    }
}

#Preview {
    CalorieRingView(consumed: 1430, target: 2670)
        .padding()
        .background(DesignSystem.Colors.background)
}
