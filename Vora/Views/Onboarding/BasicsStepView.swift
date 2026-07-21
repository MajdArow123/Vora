//
//  BasicsStepView.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import SwiftUI

struct BasicsStepView: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    Text("About you")
                        .font(DesignSystem.Typography.screenTitle)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                    Text("This shapes your targets and how Vora displays your data.")
                        .font(DesignSystem.Typography.body)
                        .foregroundStyle(DesignSystem.Colors.textPrimary.opacity(0.6))
                }

                Picker("Units", selection: $viewModel.preferredUnits) {
                    ForEach(UnitSystem.allCases, id: \.self) { unit in
                        Text(unit.displayName).tag(unit)
                    }
                }
                .pickerStyle(.segmented)

                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    fieldLabel("Name")
                    TextField("Your name", text: $viewModel.name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .padding(DesignSystem.Spacing.md)
                        .background(.white)
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
                }

                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    fieldLabel("Biological sex")
                    HStack(spacing: DesignSystem.Spacing.sm) {
                        ForEach(BiologicalSex.allCases, id: \.self) { sex in
                            sexCard(sex)
                        }
                    }
                    Text("Used only to calculate your calorie targets.")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textPrimary.opacity(0.5))
                }

                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    fieldLabel("Date of birth")
                    HStack {
                        Text("Born")
                            .font(DesignSystem.Typography.body)
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                        Spacer()
                        DatePicker(
                            "Date of birth",
                            selection: $viewModel.dateOfBirth,
                            in: viewModel.dateOfBirthRange,
                            displayedComponents: .date
                        )
                        .labelsHidden()
                    }
                    .padding(DesignSystem.Spacing.md)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
                }

                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    fieldLabel("Height")
                    heightPickers
                        .background(.white)
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
                }

                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    fieldLabel("Weight")
                    weightPicker
                        .background(.white)
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.bottom, DesignSystem.Spacing.lg)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    @ViewBuilder
    private var heightPickers: some View {
        if viewModel.preferredUnits == .metric {
            Picker("Height", selection: $viewModel.heightCmSelection) {
                ForEach(120...220, id: \.self) { value in
                    Text("\(value) cm").tag(value)
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 110)
            .clipped()
        } else {
            HStack(spacing: 0) {
                Picker("Feet", selection: $viewModel.heightFeet) {
                    ForEach(3...7, id: \.self) { value in
                        Text("\(value) ft").tag(value)
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 110)
                .clipped()

                Picker("Inches", selection: $viewModel.heightInches) {
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

    @ViewBuilder
    private var weightPicker: some View {
        if viewModel.preferredUnits == .metric {
            Picker("Weight", selection: $viewModel.weightKgSelection) {
                ForEach(35...200, id: \.self) { value in
                    Text("\(value) kg").tag(value)
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 110)
            .clipped()
        } else {
            Picker("Weight", selection: $viewModel.weightPounds) {
                ForEach(80...440, id: \.self) { value in
                    Text("\(value) lb").tag(value)
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 110)
            .clipped()
        }
    }

    private func sexCard(_ sex: BiologicalSex) -> some View {
        let isSelected = viewModel.biologicalSex == sex
        return Button {
            viewModel.biologicalSex = sex
        } label: {
            HStack {
                Text(sex.displayName)
                    .font(DesignSystem.Typography.headline)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected
                                     ? DesignSystem.Colors.accent
                                     : DesignSystem.Colors.textPrimary.opacity(0.2))
            }
            .padding(DesignSystem.Spacing.md)
            .frame(maxWidth: .infinity)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                    .strokeBorder(isSelected ? DesignSystem.Colors.accent : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(DesignSystem.Typography.headline)
            .foregroundStyle(DesignSystem.Colors.textPrimary)
    }
}

#Preview {
    BasicsStepView(viewModel: OnboardingViewModel())
        .background(DesignSystem.Colors.background)
}
