//
//  InfoCallout.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-26.
//

import SwiftUI

/// Compact instructional callout: sage left border on a light sage
/// background, matching the insight-card accent language.
struct InfoCallout: View {
    let text: String

    var body: some View {
        Text(text)
            .font(DesignSystem.Typography.caption)
            .foregroundStyle(DesignSystem.Colors.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DesignSystem.Spacing.sm)
            .padding(.leading, DesignSystem.Spacing.xs)
            .background(DesignSystem.Colors.accent.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small))
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(DesignSystem.Colors.accent)
                    .frame(width: 3)
                    .padding(.vertical, DesignSystem.Spacing.xs)
            }
    }
}

#Preview {
    InfoCallout(text: MeasurementField.generalTip)
        .padding()
        .background(DesignSystem.Colors.background)
}
