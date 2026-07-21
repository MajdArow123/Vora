//
//  SplitBuilderView.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import SwiftUI
import SwiftData

/// Weekly split editor. Edits the persisted SplitDay rows directly;
/// changes are saved on Done.
struct SplitBuilderView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SplitDay.dayIndex) private var days: [SplitDay]

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.Colors.background
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: DesignSystem.Spacing.sm) {
                        ForEach(days) { day in
                            NavigationLink {
                                SplitDayEditorView(day: day)
                            } label: {
                                dayRow(day)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    .padding(.vertical, DesignSystem.Spacing.md)
                }
            }
            .navigationTitle("Weekly Split")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        try? modelContext.save()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(DesignSystem.Colors.accent)
                }
            }
        }
    }

    private func dayRow(_ day: SplitDay) -> some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            Text(SplitDay.dayNames[day.dayIndex])
                .font(DesignSystem.Typography.headline)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .frame(width: 44, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(day.isRest ? "Rest" : day.title)
                    .font(DesignSystem.Typography.headline)
                    .foregroundStyle(day.isRest
                                     ? DesignSystem.Colors.textSecondary
                                     : DesignSystem.Colors.textPrimary)
                if !day.isRest, !day.muscleGroups.isEmpty {
                    Text(day.muscleGroups
                        .map { MuscleGroup(rawValue: $0)?.displayName ?? $0.capitalized }
                        .joined(separator: ", "))
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary.opacity(0.5))
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
        .contentShape(Rectangle())
    }
}

struct SplitDayEditorView: View {
    @Bindable var day: SplitDay

    var body: some View {
        ZStack {
            DesignSystem.Colors.background
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                    Toggle(isOn: Binding(
                        get: { day.isRest },
                        set: { newValue in
                            day.isRest = newValue
                            if newValue {
                                day.title = "Rest"
                                day.muscleGroups = []
                            } else if day.title == "Rest" {
                                day.title = "Workout"
                            }
                        }
                    )) {
                        Text("Rest day")
                            .font(DesignSystem.Typography.headline)
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                    }
                    .tint(DesignSystem.Colors.accent)
                    .padding(DesignSystem.Spacing.md)
                    .background(DesignSystem.Colors.card)
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))

                    if !day.isRest {
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                            Text("Day name")
                                .font(DesignSystem.Typography.caption)
                                .foregroundStyle(DesignSystem.Colors.textSecondary)
                                .textCase(.uppercase)
                            TextField("e.g. Push", text: $day.title)
                                .padding(DesignSystem.Spacing.md)
                                .background(DesignSystem.Colors.card)
                                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
                        }

                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                            Text("Muscle groups")
                                .font(DesignSystem.Typography.caption)
                                .foregroundStyle(DesignSystem.Colors.textSecondary)
                                .textCase(.uppercase)

                            FlowingChips(day: day)
                        }
                    }
                }
                .padding(DesignSystem.Spacing.lg)
            }
        }
        .navigationTitle(SplitDay.dayNames[day.dayIndex])
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Toggleable muscle-group chips in a simple two-column grid.
private struct FlowingChips: View {
    @Bindable var day: SplitDay

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(MuscleGroup.allCases) { group in
                let isSelected = day.muscleGroups.contains(group.rawValue)
                Button {
                    if isSelected {
                        day.muscleGroups.removeAll { $0 == group.rawValue }
                    } else {
                        day.muscleGroups.append(group.rawValue)
                    }
                } label: {
                    Text(group.displayName)
                        .font(DesignSystem.Typography.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(isSelected ? .white : DesignSystem.Colors.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DesignSystem.Spacing.sm)
                        .background(isSelected ? DesignSystem.Colors.accent : DesignSystem.Colors.card)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

#Preview {
    SplitBuilderView()
        .modelContainer(for: SplitDay.self, inMemory: true)
}
