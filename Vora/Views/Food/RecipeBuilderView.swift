//
//  RecipeBuilderView.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-25.
//

import SwiftUI
import SwiftData

struct RecipeBuilderView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = RecipeBuilderViewModel()
    @State private var showingIngredientPicker = false

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.Colors.background
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                        recipeCard
                        ingredientsCard
                        if !viewModel.ingredients.isEmpty {
                            Text("Total \(Int(viewModel.totalCalories.rounded())) kcal · \(Int(viewModel.perServingCalories.rounded())) per serving")
                                .font(DesignSystem.Typography.caption)
                                .foregroundStyle(DesignSystem.Colors.textSecondary)
                                .contentTransition(.numericText())
                                .animation(.easeInOut(duration: 0.2), value: viewModel.perServingCalories)
                        }
                    }
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    .padding(.vertical, DesignSystem.Spacing.md)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Create Recipe")
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
            .sheet(isPresented: $showingIngredientPicker) {
                FoodSearchView(mode: .pick(onPick: { item, grams in
                    viewModel.addIngredient(from: item, grams: grams)
                }))
            }
        }
    }

    // MARK: - Recipe card

    private var recipeCard: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text("Recipe")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .textCase(.uppercase)

            VStack(spacing: DesignSystem.Spacing.sm) {
                HStack {
                    Text("Name")
                        .font(DesignSystem.Typography.body)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                    Spacer()
                    TextField("e.g. Protein Pancakes", text: $viewModel.name)
                        .font(DesignSystem.Typography.body)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                        .multilineTextAlignment(.trailing)
                        .autocorrectionDisabled()
                }
                Divider()
                HStack {
                    Text("Servings")
                        .font(DesignSystem.Typography.body)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                    Spacer()
                    HStack(spacing: DesignSystem.Spacing.sm) {
                        stepButton("minus") { viewModel.adjustServings(by: -1) }
                            .accessibilityLabel("Fewer servings")
                        Text("\(viewModel.servings)")
                            .font(DesignSystem.Typography.headline)
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                            .frame(minWidth: 28)
                            .contentTransition(.numericText())
                        stepButton("plus") { viewModel.adjustServings(by: 1) }
                            .accessibilityLabel("More servings")
                    }
                }
            }
            .padding(DesignSystem.Spacing.md)
            .background(DesignSystem.Colors.card)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
        }
    }

    private func stepButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                action()
            }
        } label: {
            Image(systemName: "\(icon).circle.fill")
                .font(.title2)
                .foregroundStyle(DesignSystem.Colors.accent)
                .frame(width: 40, height: 40)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Ingredients

    private var ingredientsCard: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text("Ingredients")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .textCase(.uppercase)

            VStack(spacing: DesignSystem.Spacing.sm) {
                ForEach(viewModel.ingredients) { ingredient in
                    ingredientRow(ingredient)
                }

                Button {
                    showingIngredientPicker = true
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(DesignSystem.Colors.accent)
                            .accessibilityHidden(true)
                        Text("Add Ingredient")
                            .font(DesignSystem.Typography.headline)
                            .foregroundStyle(DesignSystem.Colors.accent)
                        Spacer()
                    }
                    .padding(DesignSystem.Spacing.md)
                    .background(DesignSystem.Colors.card)
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func ingredientRow(_ ingredient: RecipeBuilderViewModel.DraftIngredient) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(ingredient.foodName)
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                    .lineLimit(1)
                Text("\(Int(ingredient.servingGrams.rounded())) g")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Int(ingredient.calories.rounded())) kcal")
                    .font(DesignSystem.Typography.headline)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Text("P \(Int(ingredient.proteinG.rounded())) · C \(Int(ingredient.carbsG.rounded())) · F \(Int(ingredient.fatG.rounded()))")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
        .contextMenu {
            Button(role: .destructive) {
                withAnimation {
                    viewModel.remove(ingredient)
                }
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

#Preview {
    RecipeBuilderView()
        .modelContainer(
            for: [
                Recipe.self, RecipeIngredient.self, CustomFood.self,
                FoodEntry.self, UserProfile.self,
                SavedMeal.self, SavedMealItem.self,
            ],
            inMemory: true
        )
}
