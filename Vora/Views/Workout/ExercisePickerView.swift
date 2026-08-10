//
//  ExercisePickerView.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import SwiftUI
import SwiftData

struct ExercisePickerView: View {
    let onSelect: (String, [String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<GymProfile> { $0.isActive })
    private var activeProfiles: [GymProfile]
    @State private var query = ""
    @State private var muscleFilter: MuscleGroup?
    @State private var equipmentFilter: EquipmentType?
    @State private var showUnavailable = false

    /// Nil when no gym profile exists yet (fresh installs before seeding
    /// runs); everything counts as available in that case.
    private var activeEquipment: Set<EquipmentType>? {
        activeProfiles.first?.availableEquipment
    }

    private var results: [ExerciseDefinition] {
        ExerciseLibrary.filtered(query: query, muscleGroup: muscleFilter, equipment: equipmentFilter)
    }

    private var availableResults: [ExerciseDefinition] {
        guard let activeEquipment else { return results }
        return results.filter { $0.isAvailable(with: activeEquipment) }
    }

    private var unavailableResults: [ExerciseDefinition] {
        guard let activeEquipment else { return [] }
        return results.filter { !$0.isAvailable(with: activeEquipment) }
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
                        items: EquipmentType.allCases,
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
                        icon: "plus.circle.fill",
                        isAvailable: true
                    ) {
                        select(name: trimmed, muscleGroups: [])
                    }
                }

                ForEach(availableResults) { exercise in
                    exerciseRow(exercise, isAvailable: true)
                }

                if !unavailableResults.isEmpty {
                    unavailableToggle

                    if showUnavailable {
                        ForEach(unavailableResults) { exercise in
                            exerciseRow(exercise, isAvailable: false)
                        }
                    }
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.bottom, DesignSystem.Spacing.lg)
        }
        .scrollDismissesKeyboard(.immediately)
    }

    private var unavailableToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                showUnavailable.toggle()
            }
        } label: {
            HStack(spacing: DesignSystem.Spacing.xs) {
                Image(systemName: showUnavailable ? "chevron.down" : "chevron.right")
                    .font(.caption2)
                    .accessibilityHidden(true)
                Text(showUnavailable
                     ? "Hide unavailable"
                     : "Show unavailable (\(unavailableResults.count))")
                    .font(DesignSystem.Typography.caption)
            }
            .foregroundStyle(DesignSystem.Colors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, DesignSystem.Spacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(showUnavailable
                            ? "Hide exercises unavailable at your gym"
                            : "Show exercises unavailable at your gym")
    }

    private func exerciseRow(_ exercise: ExerciseDefinition, isAvailable: Bool) -> some View {
        row(
            title: exercise.name,
            subtitle: "\(exercise.muscleGroup.displayName) · \(exercise.equipmentText)",
            icon: isAvailable ? "dumbbell" : "circle.slash",
            isAvailable: isAvailable
        ) {
            select(name: exercise.name, muscleGroups: [exercise.muscleGroup.rawValue])
        }
    }

    private func select(name: String, muscleGroups: [String]) {
        onSelect(name, muscleGroups)
        dismiss()
    }

    private func row(
        title: String,
        subtitle: String,
        icon: String,
        isAvailable: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: DesignSystem.Spacing.md) {
                Image(systemName: icon)
                    .foregroundStyle(isAvailable
                                     ? DesignSystem.Colors.accent
                                     : DesignSystem.Colors.textSecondary)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(DesignSystem.Typography.body)
                        .foregroundStyle(isAvailable
                                         ? DesignSystem.Colors.textPrimary
                                         : DesignSystem.Colors.textSecondary)
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
            .opacity(isAvailable ? 1 : 0.55)
        }
        .buttonStyle(.plain)
        .accessibilityHint(isAvailable ? "" : "Not available at your active gym")
    }
}

#Preview {
    ExercisePickerView { _, _ in }
        .modelContainer(for: GymProfile.self, inMemory: true)
}
