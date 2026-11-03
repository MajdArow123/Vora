//
//  RestActivityWidget.swift
//  VoraRestActivity
//
//  Created by Majd Arow on 2026-11-03.
//

import ActivityKit
import SwiftUI
import WidgetKit

/// The rest countdown on the Lock Screen and in the Dynamic Island. The timer
/// text ticks by itself, so the app sends nothing while a rest runs. A
/// suspended app can't end the activity at the end time, so past its stale
/// date the views say the rest is over until Vora next becomes active.
struct RestActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestActivityAttributes.self) { context in
            RestLockScreenView(state: context.state, isOver: context.isStale)
                .activityBackgroundTint(DesignSystem.Colors.card)
                .activitySystemActionForegroundColor(DesignSystem.Colors.accent)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    RestIcon(isOver: context.isStale)
                        .font(.title2)
                        .padding(.leading, DesignSystem.Spacing.xs)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    RestCountdown(state: context.state, isOver: context.isStale)
                        .font(DesignSystem.Typography.title)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                        .frame(maxWidth: 110, alignment: .trailing)
                        .environment(\.colorScheme, .dark)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    RestNextSetLabel(state: context.state)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, DesignSystem.Spacing.xs)
                        .environment(\.colorScheme, .dark)
                }
            } compactLeading: {
                RestIcon(isOver: context.isStale)
            } compactTrailing: {
                RestCountdown(state: context.state, isOver: context.isStale)
                    .font(DesignSystem.Typography.caption.monospacedDigit())
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                    .frame(maxWidth: 44, alignment: .trailing)
                    .environment(\.colorScheme, .dark)
            } minimal: {
                RestIcon(isOver: context.isStale)
            }
            .keylineTint(DesignSystem.Colors.accent)
        }
    }
}

private struct RestLockScreenView: View {
    let state: RestActivityAttributes.ContentState
    let isOver: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.md) {
                RestNextSetLabel(state: state)
                    .frame(maxWidth: .infinity, alignment: .leading)
                RestCountdown(state: state, isOver: isOver)
                    .font(DesignSystem.Typography.screenTitle)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                    .frame(maxWidth: 130, alignment: .trailing)
            }
            if !isOver {
                ProgressView(timerInterval: state.timerRange, countsDown: true) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .tint(DesignSystem.Colors.accent)
            }
        }
        .padding(DesignSystem.Spacing.md)
    }
}

private struct RestNextSetLabel: View {
    let state: RestActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            Text(state.exerciseName)
                .font(DesignSystem.Typography.headline)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .lineLimit(1)
            Text(state.nextSetText)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .lineLimit(1)
        }
    }
}

private struct RestCountdown: View {
    let state: RestActivityAttributes.ContentState
    let isOver: Bool

    var body: some View {
        if isOver {
            Text("Rest over")
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        } else {
            Text(timerInterval: state.timerRange, countsDown: true, showsHours: false)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct RestIcon: View {
    let isOver: Bool

    var body: some View {
        Image(systemName: isOver ? "checkmark.circle.fill" : "timer")
            .foregroundStyle(DesignSystem.Colors.accent)
            .environment(\.colorScheme, .dark)
            .accessibilityLabel(isOver ? "Rest over" : "Rest")
    }
}
