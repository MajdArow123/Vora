//
//  CustomFoodFormView.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import SwiftUI
import SwiftData

struct CustomFoodFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = CustomFoodViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.Colors.background
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                        card("Food") {
                            textRow("Name", text: $viewModel.name, placeholder: "e.g. Overnight Oats", keyboard: .default)
                            Divider()
                            textRow("Brand", text: $viewModel.brand, placeholder: "Optional", keyboard: .default)
                            Divider()
                            textRow("Default serving (g)", text: $viewModel.servingText, placeholder: "100", keyboard: .decimalPad)
                        }

                        card("Nutrition per 100 g") {
                            textRow("Calories (kcal)", text: $viewModel.caloriesText, placeholder: "0", keyboard: .decimalPad)
                            Divider()
                            textRow("Protein (g)", text: $viewModel.proteinText, placeholder: "0", keyboard: .decimalPad)
                            Divider()
                            textRow("Carbs (g)", text: $viewModel.carbsText, placeholder: "0", keyboard: .decimalPad)
                            Divider()
                            textRow("Fat (g)", text: $viewModel.fatText, placeholder: "0", keyboard: .decimalPad)
                            Divider()
                            textRow("Fibre (g)", text: $viewModel.fibreText, placeholder: "0", keyboard: .decimalPad)
                            Divider()
                            textRow("Sugar (g)", text: $viewModel.sugarText, placeholder: "0", keyboard: .decimalPad)
                            Divider()
                            textRow("Sodium (mg)", text: $viewModel.sodiumText, placeholder: "0", keyboard: .decimalPad)
                        }
                    }
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    .padding(.vertical, DesignSystem.Spacing.md)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Create Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        viewModel.save(in: modelContext)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(viewModel.canSave
                                     ? DesignSystem.Colors.accent
                                     : DesignSystem.Colors.textSecondary.opacity(0.5))
                    .disabled(!viewModel.canSave)
                }
            }
        }
    }

    private func card(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text(title)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .textCase(.uppercase)

            VStack(spacing: DesignSystem.Spacing.sm) {
                content()
            }
            .padding(DesignSystem.Spacing.md)
            .background(DesignSystem.Colors.card)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
        }
    }

    private func textRow(
        _ label: String,
        text: Binding<String>,
        placeholder: String,
        keyboard: UIKeyboardType
    ) -> some View {
        HStack {
            Text(label)
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
            Spacer()
            TextField(placeholder, text: text)
                .keyboardType(keyboard)
                .multilineTextAlignment(.trailing)
                .font(DesignSystem.Typography.headline)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .frame(maxWidth: 160)
        }
    }
}

#Preview {
    CustomFoodFormView()
        .modelContainer(for: CustomFood.self, inMemory: true)
}
