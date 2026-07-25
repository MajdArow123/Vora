//
//  CardioSliderRow.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-25.
//

import SwiftUI

/// A titled slider card for machine-specific cardio inputs, showing the
/// current value in the accent color with a numeric transition.
struct CardioSliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String
    var fractionDigits = 0
    var valueLabel: ((Double) -> String)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            HStack {
                Text(title)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .textCase(.uppercase)
                Spacer()
                Text(formattedValue)
                    .font(DesignSystem.Typography.headline)
                    .foregroundStyle(DesignSystem.Colors.accent)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }

            Slider(value: $value, in: range, step: step)
                .tint(DesignSystem.Colors.accent)
                .accessibilityLabel(title)
                .accessibilityValue(formattedValue)
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
        .animation(.easeInOut(duration: 0.15), value: value)
    }

    private var formattedValue: String {
        if let valueLabel { return valueLabel(value) }
        let number = value.formatted(.number.precision(.fractionLength(0...fractionDigits)))
        return unit.isEmpty ? number : "\(number) \(unit)"
    }
}

#Preview {
    struct PreviewHost: View {
        @State private var speed = 8.5
        var body: some View {
            CardioSliderRow(
                title: "Speed",
                value: $speed,
                range: 1...25,
                step: 0.5,
                unit: "km/h",
                fractionDigits: 1
            )
            .padding()
        }
    }
    return PreviewHost()
}
