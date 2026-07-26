//
//  SupplementsCard.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-26.
//

import SwiftUI

/// Daily supplement checklist card on Home. Rows toggle today's taken
/// state; more than four supplements are grouped under timing labels.
struct SupplementsCard: View {
    /// Active supplements in the user's order.
    let supplements: [Supplement]
    let takenIDs: Set<UUID>
    let onToggle: (Supplement) -> Void
    let onManage: () -> Void
    let onAdd: () -> Void

    private var takenCount: Int {
        supplements.filter { takenIDs.contains($0.id) }.count
    }

    private var progress: Double {
        guard !supplements.isEmpty else { return 0 }
        return Double(takenCount) / Double(supplements.count)
    }

    private var groupsByTiming: [(timing: SupplementTiming, supplements: [Supplement])] {
        let grouped = Dictionary(grouping: supplements, by: \.timing)
        return SupplementTiming.allCases.compactMap { timing in
            grouped[timing].map { (timing: timing, supplements: $0) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            HStack {
                Text("Supplements")
                    .font(DesignSystem.Typography.headline)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Spacer()
                Button("Manage", action: onManage)
                    .font(DesignSystem.Typography.caption.weight(.semibold))
                    .foregroundStyle(DesignSystem.Colors.accent)
                    .buttonStyle(.plain)
                    .accessibilityLabel("Manage supplements")
            }

            if supplements.isEmpty {
                emptyState
            } else {
                checklist
                footer
            }
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            Text("Track your daily supplements")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)

            Button(action: onAdd) {
                Label("Add supplement", systemImage: "plus")
                    .font(DesignSystem.Typography.caption.weight(.semibold))
                    .foregroundStyle(DesignSystem.Colors.accent)
                    .padding(.horizontal, DesignSystem.Spacing.sm + 4)
                    .padding(.vertical, 6)
                    .background(DesignSystem.Colors.accent.opacity(0.12))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add supplement")
        }
        .frame(maxWidth: .infinity, minHeight: 60)
    }

    // MARK: - Checklist

    @ViewBuilder
    private var checklist: some View {
        if supplements.count > 4 {
            ForEach(groupsByTiming, id: \.timing) { group in
                Text(group.timing.displayName)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .textCase(.uppercase)
                    .padding(.top, DesignSystem.Spacing.xs)
                ForEach(group.supplements) { supplement in
                    row(supplement)
                }
            }
        } else {
            ForEach(supplements) { supplement in
                row(supplement)
            }
        }
    }

    private func row(_ supplement: Supplement) -> some View {
        SupplementRow(
            supplement: supplement,
            isTaken: takenIDs.contains(supplement.id),
            onToggle: { onToggle(supplement) }
        )
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(DesignSystem.Colors.accent.opacity(0.15))
                    Capsule()
                        .fill(DesignSystem.Colors.accent)
                        .frame(width: max(geo.size.width * progress, progress > 0 ? 6 : 0))
                        .animation(.easeOut(duration: 0.4), value: progress)
                }
            }
            .frame(height: 6)

            Text("\(takenCount) of \(supplements.count) taken today")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
        }
        .padding(.top, DesignSystem.Spacing.xs)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Supplement progress")
        .accessibilityValue("\(takenCount) of \(supplements.count) taken today")
    }
}

/// One checklist row: name + dose on the left, a circular checkbox on the
/// right. Mirrors the workout set completion checkmark animation.
private struct SupplementRow: View {
    let supplement: Supplement
    let isTaken: Bool
    let onToggle: () -> Void

    var body: some View {
        Button {
            withAnimation(.spring(duration: 0.3)) {
                onToggle()
            }
            if !isTaken {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
        } label: {
            HStack(spacing: DesignSystem.Spacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(supplement.name)
                        .font(DesignSystem.Typography.body)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                        .strikethrough(isTaken)
                    Text(supplement.dose)
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .strikethrough(isTaken)
                }
                .opacity(isTaken ? 0.5 : 1)

                Spacer()

                Image(systemName: isTaken ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isTaken
                                     ? DesignSystem.Colors.accent
                                     : DesignSystem.Colors.textSecondary.opacity(0.3))
                    .frame(width: 40, height: 40)
                    .scaleEffect(isTaken ? 1.08 : 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(supplement.name)
        .accessibilityValue(isTaken ? "Taken" : "Not taken")
        .accessibilityHint(supplement.dose)
    }
}

#Preview("With supplements") {
    struct PreviewWrapper: View {
        @State private var taken: Set<UUID> = []
        let supplements = [
            Supplement(name: "Creatine", dose: "5g", timing: .morning, orderIndex: 0),
            Supplement(name: "Vitamin D", dose: "2000IU", timing: .morning, orderIndex: 1),
            Supplement(name: "Magnesium", dose: "400mg", timing: .evening, orderIndex: 2),
        ]

        var body: some View {
            SupplementsCard(
                supplements: supplements,
                takenIDs: taken,
                onToggle: { supplement in
                    if taken.contains(supplement.id) {
                        taken.remove(supplement.id)
                    } else {
                        taken.insert(supplement.id)
                    }
                },
                onManage: {},
                onAdd: {}
            )
            .padding()
            .background(DesignSystem.Colors.background)
        }
    }
    return PreviewWrapper()
}

#Preview("Empty") {
    SupplementsCard(supplements: [], takenIDs: [], onToggle: { _ in }, onManage: {}, onAdd: {})
        .padding()
        .background(DesignSystem.Colors.background)
}
