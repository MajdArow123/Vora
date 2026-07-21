//
//  ExercisePickerView.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import SwiftUI

struct ExercisePickerView: View {
    let onSelect: (String, [String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var muscleFilter: MuscleGroup?
    @State private var equipmentFilter: Equipment?

    private var results: [ExerciseDefinition] {
        ExerciseLibrary.filtered(query: query, muscleGroup: muscleFilter, equipment: equipmentFilter)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.Colors.background
                    .ignoresSafeArea()

                VStack(spacing: DesignSystem.Spacing.md) {
                    searchField
                    filterRow(
                        items: MuscleGroup.allCases,
                        selection: $muscleFilter,
                        label: \.displayName
                    )
                    filterRow(
                        items: Equipment.allCases,
                        selection: $equipmentFilter,
                        label: \.displayName
                    )
                    resultsList
                }
                .padding(.top, DesignSystem.Spacing.md)
            }
            .navigationTitle("Add Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .accessibilityHidden(true)
            TextField("Search exercises", text: $query)
                .autocorrectionDisabled()
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
        .padding(.horizontal, DesignSystem.Spacing.lg)
    }

    private func filterRow<T: Identifiable & Equatable>(
        items: [T],
        selection: Binding<T?>,
        label: KeyPath<T, String>
    ) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DesignSystem.Spacing.xs) {
                ForEach(items) { item in
                    let isSelected = selection.wrappedValue == item
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selection.wrappedValue = isSelected ? nil : item
                        }
                    } label: {
                        Text(item[keyPath: label])
                            .font(DesignSystem.Typography.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(isSelected ? .white : DesignSystem.Colors.textPrimary)
                            .padding(.horizontal, DesignSystem.Spacing.sm)
                            .padding(.vertical, 6)
                            .background(isSelected ? DesignSystem.Colors.accent : DesignSystem.Colors.card)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
        }
    }

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: DesignSystem.Spacing.xs) {
                let trimmed = query.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    row(
                        title: "Add \"\(trimmed)\"",
                        subtitle: "Custom exercise",
                        icon: "plus.circle.fill"
                    ) {
                        select(name: trimmed, muscleGroups: [])
                    }
                }

                ForEach(results) { exercise in
                    row(
                        title: exercise.name,
                        subtitle: "\(exercise.muscleGroup.displayName) · \(exercise.equipment.displayName)",
                        icon: "dumbbell"
                    ) {
                        select(name: exercise.name, muscleGroups: [exercise.muscleGroup.rawValue])
                    }
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.bottom, DesignSystem.Spacing.lg)
        }
        .scrollDismissesKeyboard(.immediately)
    }

    private func select(name: String, muscleGroups: [String]) {
        onSelect(name, muscleGroups)
        dismiss()
    }

    private func row(title: String, subtitle: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DesignSystem.Spacing.md) {
                Image(systemName: icon)
                    .foregroundStyle(DesignSystem.Colors.accent)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(DesignSystem.Typography.body)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                    Text(subtitle)
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
                Spacer()
            }
            .padding(DesignSystem.Spacing.md)
            .background(DesignSystem.Colors.card)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ExercisePickerView { _, _ in }
}
