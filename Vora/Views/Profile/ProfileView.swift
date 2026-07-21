//
//  ProfileView.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import SwiftUI
import SwiftData

struct ProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = ProfileViewModel()

    var body: some View {
        ZStack {
            DesignSystem.Colors.background
                .ignoresSafeArea()

            if viewModel.profile != nil {
                VStack(spacing: 0) {
                    editBar
                        .padding(.horizontal, DesignSystem.Spacing.lg)
                        .padding(.top, DesignSystem.Spacing.md)

                    ScrollView {
                        VStack(spacing: DesignSystem.Spacing.lg) {
                            if viewModel.isEditing {
                                editingContent
                            } else if let profile = viewModel.profile {
                                displayContent(for: profile)
                            }
                        }
                        .padding(.horizontal, DesignSystem.Spacing.lg)
                        .padding(.vertical, DesignSystem.Spacing.lg)
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
            } else {
                Text("Profile")
                    .font(DesignSystem.Typography.screenTitle)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
            }
        }
        .onAppear {
            viewModel.load(from: modelContext)
        }
    }

    // MARK: - Edit bar

    private var editBar: some View {
        HStack {
            if viewModel.isEditing {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.cancelEditing()
                    }
                } label: {
                    Text("Cancel")
                        .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.textPrimary.opacity(0.6))
            }

            Spacer()

            if viewModel.isEditing {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.saveChanges(in: modelContext)
                    }
                } label: {
                    Text("Save")
                        .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .font(DesignSystem.Typography.headline)
                .foregroundStyle(viewModel.canSave
                                 ? DesignSystem.Colors.accent
                                 : DesignSystem.Colors.textPrimary.opacity(0.3))
                .disabled(!viewModel.canSave)
            } else {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.beginEditing()
                    }
                } label: {
                    Text("Edit")
                        .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .font(DesignSystem.Typography.headline)
                .foregroundStyle(DesignSystem.Colors.accent)
            }
        }
    }

    // MARK: - Display mode

    @ViewBuilder
    private func displayContent(for profile: UserProfile) -> some View {
        header(for: profile)

        card("Body") {
            row("Height", viewModel.heightText ?? "—")
            Divider()
            row("Weight", viewModel.weightText ?? "—")
            Divider()
            row("Biological sex", profile.biologicalSex.displayName)
        }

        card("Training") {
            row("Goal", profile.goalType.displayName)
            Divider()
            row("Goal weight", profile.goalWeightKg > 0
                ? String(format: "%.1f kg", profile.goalWeightKg)
                : "Not set")
            Divider()
            row("Activity", profile.activityLevel.displayName)
            Divider()
            row("Split", profile.trainingSplit.displayName)
        }

        card("Daily Targets") {
            row("Calories", "\(profile.dailyCalorieTarget) kcal")
            Divider()
            row("Protein", "\(profile.proteinTargetG) g")
            Divider()
            row("Carbs", "\(profile.carbsTargetG) g")
            Divider()
            row("Fat", "\(profile.fatTargetG) g")
            Divider()
            row("Water", "\(Int(profile.waterTargetMl)) ml")
        }

        card("Preferences") {
            row("Units", profile.preferredUnits.displayName)
        }
    }

    private func header(for profile: UserProfile) -> some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            ZStack {
                Circle()
                    .fill(DesignSystem.Colors.accent.opacity(0.15))
                    .frame(width: 88, height: 88)
                Text(viewModel.initials)
                    .font(DesignSystem.Typography.title)
                    .foregroundStyle(DesignSystem.Colors.accent)
            }

            Text(profile.name)
                .font(DesignSystem.Typography.screenTitle)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            if let age = viewModel.age {
                Text("Age \(age)")
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.textPrimary.opacity(0.6))
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Edit mode

    @ViewBuilder
    private var editingContent: some View {
        card("You") {
            HStack {
                Text("Name")
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.textPrimary.opacity(0.6))
                Spacer()
                TextField("Name", text: $viewModel.draftName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.trailing)
                    .font(DesignSystem.Typography.headline)
            }
            Divider()
            HStack {
                Text("Born")
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.textPrimary.opacity(0.6))
                Spacer()
                DatePicker(
                    "Date of birth",
                    selection: $viewModel.draftDateOfBirth,
                    in: viewModel.dateOfBirthRange,
                    displayedComponents: .date
                )
                .labelsHidden()
            }
            Divider()
            pickerRow("Biological sex", selection: $viewModel.draftBiologicalSex)
        }

        card("Height") {
            heightEditor
        }

        card("Training") {
            pickerRow("Goal", selection: $viewModel.draftGoalType)
            Divider()
            targetEditRow("Goal weight", text: $viewModel.draftGoalWeightText, unit: "kg", keyboard: .decimalPad)
            Divider()
            pickerRow("Activity", selection: $viewModel.draftActivityLevel)
            Divider()
            pickerRow("Split", selection: $viewModel.draftTrainingSplit)
        }

        card("Daily Targets") {
            targetEditRow("Calories", text: $viewModel.draftCaloriesText, unit: "kcal")
            Divider()
            targetEditRow("Protein", text: $viewModel.draftProteinText, unit: "g")
            Divider()
            targetEditRow("Carbs", text: $viewModel.draftCarbsText, unit: "g")
            Divider()
            targetEditRow("Fat", text: $viewModel.draftFatText, unit: "g")
        }

        card("Preferences") {
            Picker("Units", selection: $viewModel.draftUnits) {
                ForEach(UnitSystem.allCases, id: \.self) { unit in
                    Text(unit.displayName).tag(unit)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    @ViewBuilder
    private var heightEditor: some View {
        if viewModel.draftUnits == .metric {
            Picker("Height", selection: $viewModel.draftHeightCmSelection) {
                ForEach(120...220, id: \.self) { value in
                    Text("\(value) cm").tag(value)
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 110)
            .clipped()
        } else {
            HStack(spacing: 0) {
                Picker("Feet", selection: $viewModel.draftHeightFeet) {
                    ForEach(3...7, id: \.self) { value in
                        Text("\(value) ft").tag(value)
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 110)
                .clipped()

                Picker("Inches", selection: $viewModel.draftHeightInches) {
                    ForEach(0...11, id: \.self) { value in
                        Text("\(value) in").tag(value)
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 110)
                .clipped()
            }
        }
    }

    private func pickerRow<T: CaseIterable & Hashable>(
        _ label: String,
        selection: Binding<T>
    ) -> some View where T.AllCases: RandomAccessCollection, T: ProfileDisplayable {
        HStack {
            Text(label)
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.textPrimary.opacity(0.6))
            Spacer()
            Picker(label, selection: selection) {
                ForEach(T.allCases, id: \.self) { value in
                    Text(value.displayName).tag(value)
                }
            }
            .pickerStyle(.menu)
            .tint(DesignSystem.Colors.accent)
        }
    }

    private func targetEditRow(
        _ label: String,
        text: Binding<String>,
        unit: String,
        keyboard: UIKeyboardType = .numberPad
    ) -> some View {
        HStack {
            Text(label)
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.textPrimary.opacity(0.6))
            Spacer()
            TextField("0", text: text)
                .keyboardType(keyboard)
                .multilineTextAlignment(.trailing)
                .font(DesignSystem.Typography.headline)
                .frame(width: 80)
                .accessibilityLabel(label)
            Text(unit)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textPrimary.opacity(0.5))
                .frame(width: 36, alignment: .leading)
        }
    }

    // MARK: - Shared card/row chrome

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

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.textPrimary.opacity(0.6))
            Spacer()
            Text(value)
                .font(DesignSystem.Typography.headline)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
        }
    }
}

/// Conformance hook so the generic picker row can label any profile enum.
protocol ProfileDisplayable {
    var displayName: String { get }
}

extension BiologicalSex: ProfileDisplayable {}
extension GoalType: ProfileDisplayable {}
extension ActivityLevel: ProfileDisplayable {}
extension TrainingSplit: ProfileDisplayable {}

#Preview {
    ProfileView()
        .modelContainer(for: UserProfile.self, inMemory: true)
}
