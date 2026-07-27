//
//  GhostButton.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-27.
//

import SwiftUI

/// Secondary companion to PrimaryButton: same geometry, accent text on a
/// light sage fill, so a stacked action pair reads as a set.
struct GhostButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(DesignSystem.Typography.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DesignSystem.Spacing.md)
        }
        .buttonStyle(GhostButtonStyle())
    }
}

struct GhostButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(DesignSystem.Colors.accent.opacity(isEnabled ? 1 : 0.35))
            .background(DesignSystem.Colors.accent.opacity(isEnabled ? 0.12 : 0.06))
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

#Preview {
    VStack(spacing: 16) {
        GhostButton(title: "Refresh suggestion") {}
        GhostButton(title: "Refresh suggestion") {}
            .disabled(true)
    }
    .padding()
    .background(DesignSystem.Colors.background)
}
