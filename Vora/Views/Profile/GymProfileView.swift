//
//  GymProfileView.swift
//  Vora
//
//  Created by Majd Arow on 2026-08-10.
//

import SwiftUI
import SwiftData

/// Manages the user's gym profiles: activate with a tap, edit via the
/// detail button, swipe to delete. The service keeps exactly one profile
/// active and never lets the list reach zero.
struct GymProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \GymProfile.createdAt) private var profiles: [GymProfile]
    @State private var editingProfile: GymProfile?
    @State private var showingCreateSheet = false

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.Colors.background
                    .ignoresSafeArea()

                List {
                    ForEach(profiles) { profile in
                        profileRow(profile)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(rowInsets)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if profiles.count > 1 {
                                    Button(role: .destructive) {
                                        GymProfileService.delete(profile, context: modelContext)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("My Gym")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingCreateSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(DesignSystem.Colors.accent)
                    }
                    .accessibilityLabel("Add gym profile")
                }
            }
            .onAppear {
                GymProfileService.ensureDefaultProfile(context: modelContext)
            }
            .sheet(item: $editingProfile) { profile in
                GymProfileEditorView(profile: profile)
            }
            .sheet(isPresented: $showingCreateSheet) {
                GymProfileEditorView(profile: nil)
            }
        }
    }

    private var rowInsets: EdgeInsets {
        EdgeInsets(
            top: DesignSystem.Spacing.xs,
            leading: DesignSystem.Spacing.lg,
            bottom: DesignSystem.Spacing.xs,
            trailing: DesignSystem.Spacing.lg
        )
    }

    private func profileRow(_ profile: GymProfile) -> some View {
        Button {
            GymProfileService.activate(profile, context: modelContext)
        } label: {
            HStack(spacing: DesignSystem.Spacing.md) {
                Image(systemName: profile.isActive ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(profile.isActive
                                     ? DesignSystem.Colors.accent
                                     : DesignSystem.Colors.textSecondary.opacity(0.4))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text(profile.name)
                        .font(DesignSystem.Typography.headline)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                    Text("\(profile.preset.displayName) · \(profile.availableEquipment.count) equipment")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }

                Spacer()

                Button {
                    editingProfile = profile
                } label: {
                    Image(systemName: "pencil")
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit \(profile.name)")
            }
            .padding(DesignSystem.Spacing.md)
            .background(DesignSystem.Colors.card)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Activate \(profile.name)")
        .accessibilityAddTraits(profile.isActive ? .isSelected : [])
    }
}

// MARK: - Editor

/// Creates or edits a single gym profile. Works on draft state so Close
/// abandons changes; Save applies them in one step.
struct GymProfileEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// Nil when creating a new profile.
    let profile: GymProfile?

    @State private var draftName: String
    @State private var draftPreset: GymPreset
    @State private var draftEquipment: Set<EquipmentType>

    private let gridColumns = [
        GridItem(.flexible(), spacing: DesignSystem.Spacing.sm),
        GridItem(.flexible(), spacing: DesignSystem.Spacing.sm),
    ]

    init(profile: GymProfile?) {
        self.profile = profile
        _draftName = State(initialValue: profile?.name ?? "")
        _draftPreset = State(initialValue: profile?.preset ?? .commercial)
        _draftEquipment = State(initialValue: profile?.availableEquipment
                                ?? GymPreset.commercial.defaultEquipment)
    }

    private var trimmedName: String {
        draftName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !trimmedName.isEmpty && !draftEquipment.isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.Colors.background
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                        nameCard
                        presetCard
                        equipmentCard
                    }
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    .padding(.vertical, DesignSystem.Spacing.md)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(profile == nil ? "New Gym" : "Edit Gym")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .font(DesignSystem.Typography.headline)
                        .foregroundStyle(canSave
                                         ? DesignSystem.Colors.accent
                                         : DesignSystem.Colors.textSecondary.opacity(0.5))
                        .disabled(!canSave)
                }
            }
        }
    }

    private var nameCard: some View {
        card("Name") {
            TextField("e.g. Home Gym", text: $draftName)
                .font(DesignSystem.Typography.body)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
        }
    }

    private var presetCard: some View {
        card("Preset") {
            VStack(spacing: DesignSystem.Spacing.xs) {
                ForEach(GymPreset.allCases) { preset in
                    presetRow(preset)
                }
            }
        }
    }

    private func presetRow(_ preset: GymPreset) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                draftPreset = preset
                if preset != .custom {
                    draftEquipment = preset.defaultEquipment
                }
            }
        } label: {
            HStack {
                Text(preset.displayName)
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Spacer()
                if preset == draftPreset {
                    Image(systemName: "checkmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DesignSystem.Colors.accent)
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(preset == draftPreset ? .isSelected : [])
    }

    private var equipmentCard: some View {
        card("Equipment") {
            LazyVGrid(columns: gridColumns, spacing: DesignSystem.Spacing.sm) {
                ForEach(EquipmentType.allCases) { equipment in
                    equipmentToggle(equipment)
                }
            }
        }
    }

    private func equipmentToggle(_ equipment: EquipmentType) -> some View {
        let isOn = draftEquipment.contains(equipment)
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                var updated = draftEquipment
                if isOn {
                    updated.remove(equipment)
                } else {
                    updated.insert(equipment)
                }
                draftEquipment = updated
                if draftPreset != .custom, updated != draftPreset.defaultEquipment {
                    draftPreset = .custom
                }
            }
        } label: {
            HStack(spacing: DesignSystem.Spacing.sm) {
                Image(systemName: equipment.symbolName)
                    .font(.subheadline)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                Text(equipment.displayName)
                    .font(DesignSystem.Typography.caption)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isOn ? .white : DesignSystem.Colors.textPrimary)
            .padding(.horizontal, DesignSystem.Spacing.sm)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(isOn ? DesignSystem.Colors.accent : DesignSystem.Colors.background)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(equipment.displayName)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func save() {
        guard canSave else { return }
        if let profile {
            profile.name = trimmedName
            profile.preset = draftPreset
            profile.updateEquipment(draftEquipment)
        } else {
            let isFirst: Bool
            do {
                isFirst = try modelContext.fetchCount(FetchDescriptor<GymProfile>()) == 0
            } catch {
                assertionFailure("Failed to count gym profiles: \(error)")
                isFirst = false
            }
            let newProfile = GymProfile(
                name: trimmedName,
                preset: draftPreset,
                availableEquipment: draftEquipment,
                isActive: isFirst
            )
            newProfile.updateEquipment(draftEquipment)
            modelContext.insert(newProfile)
        }
        do {
            try modelContext.save()
        } catch {
            assertionFailure("Failed to save gym profile: \(error)")
        }
        dismiss()
    }

    private func card(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text(title)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textPrimary.opacity(0.5))
                .textCase(.uppercase)

            VStack(spacing: DesignSystem.Spacing.sm) {
                content()
            }
            .padding(DesignSystem.Spacing.md)
            .background(DesignSystem.Colors.card)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
        }
    }
}

#Preview {
    GymProfileView()
        .modelContainer(for: GymProfile.self, inMemory: true)
}
