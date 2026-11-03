//
//  GymProfileView.swift
//  Vora
//
//  Created by Majd Arow on 2026-08-10.
//

import OSLog
import SwiftUI
import SwiftData

/// Manages the user's gym profiles: activate with a tap, edit via the
/// detail button, swipe to delete. The service keeps exactly one profile
/// active and never lets the list reach zero.
struct GymProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \GymProfile.createdAt) private var profiles: [GymProfile]
    @Query private var users: [UserProfile]
    @State private var editingProfile: GymProfile?
    @State private var showingCreateSheet = false

    private var units: UnitSystem { users.first?.preferredUnits ?? .metric }

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
                GymProfileEditorView(profile: profile, units: units)
            }
            .sheet(isPresented: $showingCreateSheet) {
                GymProfileEditorView(profile: nil, units: units)
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

    private static let logger = Logger(subsystem: "com.majdarow.Vora", category: "Persistence")

    /// Nil when creating a new profile.
    let profile: GymProfile?
    let units: UnitSystem

    @State private var draftName: String
    @State private var draftPreset: GymPreset
    @State private var draftEquipment: Set<EquipmentType>
    @State private var draftInventory: LoadingInventoryDraft
    @State private var showingSaveError = false

    private let gridColumns = [
        GridItem(.flexible(), spacing: DesignSystem.Spacing.sm),
        GridItem(.flexible(), spacing: DesignSystem.Spacing.sm),
    ]

    init(profile: GymProfile?, units: UnitSystem) {
        self.profile = profile
        self.units = units
        _draftName = State(initialValue: profile?.name ?? "")
        _draftPreset = State(initialValue: profile?.preset ?? .commercial)
        _draftEquipment = State(initialValue: profile?.availableEquipment
                                ?? GymPreset.commercial.defaultEquipment)
        let preset = profile?.preset ?? .commercial
        let equipment = profile?.availableEquipment ?? preset.defaultEquipment
        var inventory = LoadingInventoryDraft(
            inventory: profile?.loadingInventory ?? preset.defaultInventory(units: units, equipment: equipment),
            units: units
        )
        if equipment.contains(.smithMachine) {
            inventory.seedSmithIfMissing()
        }
        _draftInventory = State(initialValue: inventory)
    }

    private var trimmedName: String {
        draftName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !trimmedName.isEmpty && !draftEquipment.isEmpty
            && draftInventory.inventory(for: draftEquipment) != nil
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
                        if showsLoadingCard {
                            loadingCard
                        }
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
            .alert("Couldn't save this gym", isPresented: $showingSaveError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Your changes are still here. Try saving again.")
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
                    draftInventory = LoadingInventoryDraft(
                        inventory: preset.defaultInventory(units: units, equipment: preset.defaultEquipment),
                        units: units
                    )
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
                    if equipment == .barbell {
                        draftInventory.seedBarbellIfEmpty()
                    } else if equipment == .smithMachine {
                        draftInventory.seedSmithIfMissing()
                    }
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
        guard canSave, let inventory = draftInventory.inventory(for: draftEquipment) else { return }
        do {
            if let profile {
                profile.name = trimmedName
                profile.preset = draftPreset
                profile.updateEquipment(draftEquipment)
                profile.updateInventory(inventory)
            } else {
                let isFirst = try modelContext.fetchCount(FetchDescriptor<GymProfile>()) == 0
                let newProfile = GymProfile(
                    name: trimmedName,
                    preset: draftPreset,
                    availableEquipment: draftEquipment,
                    isActive: isFirst
                )
                newProfile.updateEquipment(draftEquipment)
                newProfile.updateInventory(inventory)
                modelContext.insert(newProfile)
            }
            try modelContext.save()
            dismiss()
        } catch {
            Self.logger.error("Failed to save gym profile: \(String(describing: error), privacy: .public)")
            modelContext.rollback()
            showingSaveError = true
        }
    }

    // MARK: - Loading inventory

    private var showsLoadingCard: Bool {
        LoadingInventoryDraft.showsBarsAndPlates(for: draftEquipment)
            || LoadingInventoryDraft.showsDumbbellStep(for: draftEquipment)
            || LoadingInventoryDraft.showsMachineStep(for: draftEquipment)
    }

    private var unitSymbol: String { UnitConversion.weightUnitSymbol(units) }

    private var loadingCard: some View {
        card("Loading") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                if LoadingInventoryDraft.showsBarsAndPlates(for: draftEquipment) {
                    barsSection
                    platesSection
                }
                if LoadingInventoryDraft.showsDumbbellStep(for: draftEquipment) {
                    stepRow("Dumbbell step", field: $draftInventory.dumbbellIncrement)
                }
                if LoadingInventoryDraft.showsMachineStep(for: draftEquipment) {
                    stepRow("Machine step", field: $draftInventory.machineIncrement)
                }
                standardSetButton("Use standard kg set", units: .metric)
                standardSetButton("Use standard lb set", units: .imperial)
            }
        }
    }

    private var barsSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            sectionTitle("Bars")
            ForEach($draftInventory.bars) { $bar in
                if bar.isShown(for: draftEquipment) {
                    HStack(spacing: DesignSystem.Spacing.sm) {
                        TextField("Name", text: $bar.name)
                            .font(DesignSystem.Typography.body)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .accessibilityLabel("Bar name")
                        weightField($bar.weight, label: "Bar weight")
                        // A Smith machine always has its bar; 0 covers counterbalanced.
                        if bar.kind == .free {
                            removeButton(label: "Remove \(bar.name)") {
                                draftInventory.bars.removeAll { $0.id == bar.id }
                            }
                        }
                    }
                }
            }
            if draftEquipment.contains(.smithMachine) {
                Text("Enter 0 for a counterbalanced Smith bar.")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
            if LoadingInventoryDraft.showsFreeBarActions(for: draftEquipment) {
                addButton("Add Bar") { draftInventory.addBar() }
            }
        }
    }

    private var platesSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            sectionTitle("Plates")
            ForEach($draftInventory.plates) { $plate in
                HStack(spacing: DesignSystem.Spacing.sm) {
                    weightField($plate.weight, label: "Plate weight")
                    Stepper(
                        "\(plate.pairCount) \(plate.pairCount == 1 ? "pair" : "pairs")",
                        value: $plate.pairCount,
                        in: LoadingInventoryDraft.PlateRow.pairRange
                    )
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                    removeButton(label: "Remove \(plate.weight.text) \(unitSymbol) plates") {
                        draftInventory.plates.removeAll { $0.id == plate.id }
                    }
                }
            }
            addButton("Add Plate") { draftInventory.addPlate() }
        }
    }

    private func stepRow(_ title: String, field: Binding<WeightField>) -> some View {
        HStack {
            Text(title)
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
            Spacer()
            weightField(field, label: title)
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(DesignSystem.Typography.headline)
            .foregroundStyle(DesignSystem.Colors.textPrimary)
    }

    private func weightField(_ field: Binding<WeightField>, label: String) -> some View {
        HStack(spacing: DesignSystem.Spacing.xs) {
            TextField("0", text: field.text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .padding(.vertical, 6)
                .frame(width: 64)
                .background(DesignSystem.Colors.background)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small))
                .accessibilityLabel("\(label) in \(UnitConversion.spokenWeightUnit(units))")
            Text(unitSymbol)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
        }
    }

    private func removeButton(label: String, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15), action)
        } label: {
            Image(systemName: "minus.circle")
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .frame(width: 32, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func addButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15), action)
        } label: {
            Label(title, systemImage: "plus")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.accent)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Replaces this gym's plates and steps with a full standard set. Kept
    /// separate from the display unit: someone who reads lb can still train
    /// on kg plates.
    private func standardSetButton(_ title: String, units setUnits: UnitSystem) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                draftInventory = LoadingInventoryDraft(
                    inventory: LoadingInventory.standard(units: setUnits)
                        .addingSmithBar(ifIn: draftEquipment, units: setUnits),
                    units: units
                )
            }
        } label: {
            Text(title)
                .font(DesignSystem.Typography.caption)
                .fontWeight(.semibold)
                .foregroundStyle(DesignSystem.Colors.accent)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(DesignSystem.Colors.background)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
