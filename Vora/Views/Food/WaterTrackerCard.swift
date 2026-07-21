//
//  WaterTrackerCard.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import SwiftUI

struct WaterTrackerCard: View {
    let totalMl: Double
    let targetMl: Double
    let glassCount: Int
    let onAdd: () -> Void
    let onRemove: () -> Void

    private var progress: Double {
        guard targetMl > 0 else { return 0 }
        return min(totalMl / targetMl, 1)
    }

    private var litresText: String {
        String(format: "%.2f / %.1f L", totalMl / 1000, targetMl / 1000)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text("Water")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .textCase(.uppercase)

            VStack(spacing: DesignSystem.Spacing.md) {
                HStack {
                    HStack(spacing: DesignSystem.Spacing.sm) {
                        Image(systemName: "drop.fill")
                            .foregroundStyle(DesignSystem.Colors.macroCarbs)
                        Text("\(glassCount)")
                            .font(DesignSystem.Typography.title)
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                            .contentTransition(.numericText())
                        Text("glasses")
                            .font(DesignSystem.Typography.body)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                    }

                    Spacer()

                    HStack(spacing: DesignSystem.Spacing.sm) {
                        Button(action: onRemove) {
                            Image(systemName: "minus.circle.fill")
                                .font(.title2)
                                .foregroundStyle(glassCount > 0
                                                 ? DesignSystem.Colors.macroCarbs
                                                 : DesignSystem.Colors.textSecondary.opacity(0.3))
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .disabled(glassCount == 0)

                        Button(action: onAdd) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .foregroundStyle(DesignSystem.Colors.macroCarbs)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(DesignSystem.Colors.macroCarbs.opacity(0.15))
                            Capsule()
                                .fill(DesignSystem.Colors.macroCarbs)
                                .frame(width: max(geo.size.width * progress, progress > 0 ? 6 : 0))
                                .animation(.easeOut(duration: 0.4), value: progress)
                        }
                    }
                    .frame(height: 6)

                    Text(litresText)
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
            }
            .padding(DesignSystem.Spacing.md)
            .background(DesignSystem.Colors.card)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
        }
    }
}

#Preview {
    WaterTrackerCard(totalMl: 1750, targetMl: 3500, glassCount: 7, onAdd: {}, onRemove: {})
        .padding()
        .background(DesignSystem.Colors.background)
}
