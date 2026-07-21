//
//  PrimaryButton.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import SwiftUI

struct PrimaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(DesignSystem.Typography.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DesignSystem.Spacing.md)
        }
        .buttonStyle(PrimaryButtonStyle())
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(DesignSystem.Colors.accent.opacity(isEnabled ? 1 : 0.35))
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

#Preview {
    VStack(spacing: 16) {
        PrimaryButton(title: "Continue") {}
        PrimaryButton(title: "Continue") {}
            .disabled(true)
    }
    .padding()
    .background(DesignSystem.Colors.background)
}
