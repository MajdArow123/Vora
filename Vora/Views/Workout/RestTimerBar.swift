//
//  RestTimerBar.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import SwiftUI

/// Countdown bar shown while a rest period runs. Fires a haptic and
/// dismisses itself when the timer reaches zero.
struct RestTimerBar: View {
    let viewModel: ActiveSessionViewModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { timeline in
            let remaining = max(viewModel.restEndDate?.timeIntervalSince(timeline.date) ?? 0, 0)

            HStack(spacing: DesignSystem.Spacing.md) {
                Image(systemName: "timer")
                    .foregroundStyle(.white)
                    .accessibilityHidden(true)

                Text(Self.timeString(remaining))
                    .font(.system(.title3, design: .monospaced, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 64, alignment: .leading)
                    .accessibilityLabel("Rest time remaining")
                    .accessibilityValue(Self.timeString(remaining))
                    .accessibilityAddTraits(.updatesFrequently)

                Spacer()

                Text("Rest")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(.white.opacity(0.7))

                Button {
                    viewModel.cancelRest()
                } label: {
                    Text("Skip")
                        .font(DesignSystem.Typography.headline)
                        .foregroundStyle(DesignSystem.Colors.accent)
                        .padding(.horizontal, DesignSystem.Spacing.md)
                        .padding(.vertical, DesignSystem.Spacing.sm)
                        .background(.white)
                        .clipShape(Capsule())
                        .contentShape(Rectangle().inset(by: -6))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Skip rest")
            }
            .padding(DesignSystem.Spacing.md)
            .background(DesignSystem.Colors.accent)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large))
            .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        }
        .task(id: viewModel.restEndDate) {
            guard let end = viewModel.restEndDate else { return }
            let interval = end.timeIntervalSince(.now)
            if interval > 0 {
                try? await Task.sleep(for: .seconds(interval))
            }
            guard !Task.isCancelled, viewModel.restEndDate == end else { return }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            viewModel.cancelRest()
        }
    }

    private static func timeString(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
