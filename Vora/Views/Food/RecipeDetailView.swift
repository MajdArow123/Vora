//
//  RecipeDetailView.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-25.
//

import SwiftUI
import SwiftData

struct RecipeDetailView: View {
    let mealSlot: MealSlot
    let logDate: Date
    let onLogged: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: RecipeDetailViewModel
    @State private var justLogged = false

    init(recipe: Recipe, mealSlot: MealSlot, logDate: Date, onLogged: @escaping () -> Void) {
        self.mealSlot = mealSlot
        self.logDate = logDate
        self.onLogged = onLogged
        _viewModel = State(initialValue: RecipeDetailViewModel(recipe: recipe))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.Colors.background
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                        header
                        perServingCard
                        ingredientsCard
                        servingsCard
                    }
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    .padding(.vertical, DesignSystem.Spacing.md)
                    .padding(.bottom, 72)
                }

                VStack {
                    Spacer()
                    logButton
                        .padding(.horizontal, DesignSystem.Spacing.lg)
                        .padding(.bottom, DesignSystem.Spacing.md)
                }
            }
            .navigationTitle(viewModel.recipe.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
            }
        }
    }

    private var header: some View {
        Text("Makes \(viewModel.recipe.servings) serving\(viewModel.recipe.servings == 1 ? "" : "s")")
            .font(DesignSystem.Typography.caption)
            .foregroundStyle(DesignSystem.Colors.textSecondary)
    }

    private var perServingCard: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text("Per serving")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .textCase(.uppercase)

            VStack(spacing: DesignSystem.Spacing.sm) {
                nutritionRow("Calories", "\(Int(viewModel.recipe.perServingCalories.rounded())) kcal", color: DesignSystem.Colors.accent)
                Divider()
                nutritionRow("Protein", gramsText(viewModel.recipe.perServingProteinG), color: DesignSystem.Colors.macroProtein)
                Divider()
                nutritionRow("Carbs", gramsText(viewModel.recipe.perServingCarbsG), color: DesignSystem.Colors.macroCarbs)
                Divider()
                nutritionRow("Fat", gramsText(viewModel.recipe.perServingFatG), color: DesignSystem.Colors.macroFat)
            }
            .padding(DesignSystem.Spacing.md)
            .background(DesignSystem.Colors.card)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
        }
    }

    private var ingredientsCard: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text("Ingredients")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .textCase(.uppercase)

            VStack(spacing: 0) {
                let ingredients = viewModel.recipe.sortedIngredients
                ForEach(ingredients) { ingredient in
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
                    .padding(.vertical, DesignSystem.Spacing.sm)
                    if ingredient.id != ingredients.last?.id {
                        Divider()
                    }
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.vertical, DesignSystem.Spacing.xs)
            .background(DesignSystem.Colors.card)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
        }
    }

    private var servingsCard: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text("Servings to log")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .textCase(.uppercase)

            VStack(spacing: DesignSystem.Spacing.xs) {
                HStack {
                    stepButton("minus") { viewModel.adjustServings(by: -1) }
                        .accessibilityLabel("Fewer servings")
                    Spacer()
                    Text("\(viewModel.servingsToLog)")
                        .font(.system(.title2, weight: .bold))
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                        .contentTransition(.numericText())
                    Spacer()
                    stepButton("plus") { viewModel.adjustServings(by: 1) }
                        .accessibilityLabel("More servings")
                }

                Text("Logs \(Int(viewModel.portion.calories.rounded())) kcal · P \(Int(viewModel.portion.proteinG.rounded())) · C \(Int(viewModel.portion.carbsG.rounded())) · F \(Int(viewModel.portion.fatG.rounded()))")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.2), value: viewModel.servingsToLog)
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
                .font(.title)
                .foregroundStyle(DesignSystem.Colors.accent)
                .frame(width: 52, height: 52)
        }
        .buttonStyle(.plain)
    }

    private func gramsText(_ value: Double) -> String {
        String(format: "%.1f g", value)
    }

    private func nutritionRow(_ label: String, _ value: String, color: Color?) -> some View {
        HStack {
            if let color {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
            }
            Text(label)
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
            Spacer()
            Text(value)
                .font(DesignSystem.Typography.headline)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
        }
    }

    private var logButton: some View {
        Button {
            guard !justLogged else { return }
            viewModel.log(to: mealSlot, on: logDate, context: modelContext)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(.spring(duration: 0.3)) {
                justLogged = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                onLogged()
            }
        } label: {
            HStack(spacing: DesignSystem.Spacing.sm) {
                Image(systemName: justLogged ? "checkmark.circle.fill" : "plus")
                    .accessibilityHidden(true)
                Text(justLogged ? "Added" : "Log to \(mealSlot.displayName)")
            }
            .font(DesignSystem.Typography.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DesignSystem.Spacing.md)
            .background(DesignSystem.Colors.accent)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
            .scaleEffect(justLogged ? 0.97 : 1)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    RecipeDetailView(
        recipe: Recipe(name: "Protein Pancakes", servings: 4, ingredients: [
            RecipeIngredient(foodName: "Oats", servingGrams: 200, calories: 750,
                             proteinG: 26, carbsG: 135, fatG: 14, orderIndex: 0),
            RecipeIngredient(foodName: "Whey", servingGrams: 60, calories: 240,
                             proteinG: 48, carbsG: 6, fatG: 3, orderIndex: 1),
        ]),
        mealSlot: .breakfast,
        logDate: .now,
        onLogged: {}
    )
    .modelContainer(for: [Recipe.self, RecipeIngredient.self, FoodEntry.self], inMemory: true)
}
