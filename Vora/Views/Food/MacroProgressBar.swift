//
//  MacroProgressBar.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import SwiftUI

struct MacroProgressBar: View {
    let label: String
    let consumedG: Double
    let targetG: Int
    let color: Color

    private var progress: Double {
        guard targetG > 0 else { return 0 }
        return min(consumedG / Double(targetG), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                Spacer()
                Text("\(Int(consumedG.rounded())) / \(targetG) g")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                    .contentTransition(.numericText())
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(color.opacity(0.15))
                    Capsule()
                        .fill(color)
                        .frame(width: max(geo.size.width * progress, progress > 0 ? 6 : 0))
                        .animation(.easeOut(duration: 0.5), value: progress)
                }
            }
            .frame(height: 6)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityValue("\(Int(consumedG.rounded())) of \(targetG) grams")
    }
}

#Preview {
    VStack(spacing: 16) {
        MacroProgressBar(label: "Protein", consumedG: 84, targetG: 120, color: DesignSystem.Colors.macroProtein)
        MacroProgressBar(label: "Carbs", consumedG: 210, targetG: 381, color: DesignSystem.Colors.macroCarbs)
        MacroProgressBar(label: "Fat", consumedG: 71, targetG: 74, color: DesignSystem.Colors.macroFat)
    }
    .padding()
    .background(DesignSystem.Colors.background)
}
