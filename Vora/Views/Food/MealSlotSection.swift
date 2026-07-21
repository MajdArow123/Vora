//
//  MealSlotSection.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import SwiftUI

struct MealSlotSection: View {
    let slot: MealSlot
    let entries: [FoodEntry]
    let onAdd: () -> Void
    let onDelete: (FoodEntry) -> Void

    private var slotCalories: Int {
        Int(entries.reduce(0) { $0 + $1.calories }.rounded())
    }

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onAdd) {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    Image(systemName: slot.iconName)
                        .font(.subheadline)
                        .foregroundStyle(DesignSystem.Colors.accent)
                        .frame(width: 24)
                        .accessibilityHidden(true)

                    Text(slot.displayName)
                        .font(DesignSystem.Typography.headline)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)

                    Spacer()

                    if !entries.isEmpty {
                        Text("\(slotCalories) kcal")
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                    }

                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(DesignSystem.Colors.accent)
                        .frame(width: 44, height: 44)
                }
                .padding(.leading, DesignSystem.Spacing.md)
                .padding(.trailing, DesignSystem.Spacing.xs)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            ForEach(entries) { entry in
                Divider()
                    .padding(.leading, DesignSystem.Spacing.md)
                entryRow(entry)
            }
        }
        .padding(.vertical, DesignSystem.Spacing.xs)
        .background(DesignSystem.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
    }

    private func entryRow(_ entry: FoodEntry) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.foodName)
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                    .lineLimit(1)
                Text("\(Int(entry.servingGrams.rounded())) g")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }

            Spacer()

            Text("\(Int(entry.calories.rounded())) kcal")
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.vertical, DesignSystem.Spacing.sm)
        .contentShape(Rectangle())
        .contextMenu {
            Button(role: .destructive) {
                onDelete(entry)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

#Preview {
    MealSlotSection(
        slot: .breakfast,
        entries: [],
        onAdd: {},
        onDelete: { _ in }
    )
    .padding()
    .background(DesignSystem.Colors.background)
}
