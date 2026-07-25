//
//  FoodDetailView.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import SwiftUI
import SwiftData

/// How the detail screen resolves its primary action: log a FoodEntry
/// (the diary flow) or hand the item + chosen grams back to a caller
/// (the recipe-ingredient picker).
enum FoodDetailMode {
    case log(mealSlot: MealSlot, logDate: Date, onAdded: () -> Void)
    case pick(buttonTitle: String, onPick: (FoodItem, Double) -> Void)
}

struct FoodDetailView: View {
    let mode: FoodDetailMode

    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: FoodDetailViewModel
    @State private var justAdded = false

    init(item: FoodItem, mode: FoodDetailMode) {
        self.mode = mode
        _viewModel = State(initialValue: FoodDetailViewModel(item: item))
    }

    init(item: FoodItem, mealSlot: MealSlot, logDate: Date, onAdded: @escaping () -> Void) {
        self.init(item: item, mode: .log(mealSlot: mealSlot, logDate: logDate, onAdded: onAdded))
    }

    var body: some View {
        ZStack {
            DesignSystem.Colors.background
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                    header
                    servingCard
                    nutritionCard
                }
                .padding(.horizontal, DesignSystem.Spacing.lg)
                .padding(.bottom, DesignSystem.Spacing.lg)
            }

            VStack {
                Spacer()
                addButton
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    .padding(.bottom, DesignSystem.Spacing.md)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            Text(viewModel.item.name)
                .font(DesignSystem.Typography.screenTitle)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
            if let brand = viewModel.item.brand {
                Text(brand)
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
        }
        .padding(.top, DesignSystem.Spacing.sm)
    }

    // MARK: - Serving stepper

    private var servingCard: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text("Serving size")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .textCase(.uppercase)

            HStack {
                stepButton("minus") { viewModel.adjustServing(by: -10) }
                    .accessibilityLabel("Decrease serving size")

                Spacer()

                VStack(spacing: 2) {
                    Text(viewModel.servingText)
                        .font(.system(.title2, weight: .bold))
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                        .contentTransition(.numericText())

                    HStack(spacing: DesignSystem.Spacing.sm) {
                        ForEach([50.0, 100, 150, 200], id: \.self) { grams in
                            Button("\(Int(grams))") {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    viewModel.setServing(grams)
                                }
                            }
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(viewModel.servingGrams == grams
                                             ? DesignSystem.Colors.accent
                                             : DesignSystem.Colors.textSecondary)
                            .contentShape(Rectangle().inset(by: -12))
                            .accessibilityLabel("\(Int(grams)) grams")
                        }
                    }
                }

                Spacer()

                stepButton("plus") { viewModel.adjustServing(by: 10) }
                    .accessibilityLabel("Increase serving size")
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

    // MARK: - Nutrition panel

    private var nutritionCard: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text("Nutrition")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .textCase(.uppercase)

            VStack(spacing: DesignSystem.Spacing.sm) {
                nutritionRow("Calories", "\(Int(viewModel.nutrition.calories.rounded())) kcal", color: DesignSystem.Colors.accent)
                Divider()
                nutritionRow("Protein", gramsText(viewModel.nutrition.proteinG), color: DesignSystem.Colors.macroProtein)
                Divider()
                nutritionRow("Carbs", gramsText(viewModel.nutrition.carbsG), color: DesignSystem.Colors.macroCarbs)
                Divider()
                nutritionRow("Fat", gramsText(viewModel.nutrition.fatG), color: DesignSystem.Colors.macroFat)
                Divider()
                nutritionRow("Fibre", gramsText(viewModel.nutrition.fibreG), color: nil)
                Divider()
                nutritionRow("Sugar", gramsText(viewModel.nutrition.sugarG), color: nil)
                Divider()
                nutritionRow("Sodium", "\(Int(viewModel.nutrition.sodiumMg.rounded())) mg", color: nil)
            }
            .padding(DesignSystem.Spacing.md)
            .background(DesignSystem.Colors.card)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
        }
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
                .contentTransition(.numericText())
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.servingGrams)
    }

    // MARK: - Add button

    private var buttonTitle: String {
        switch mode {
        case .log(let mealSlot, _, _): "Add to \(mealSlot.displayName)"
        case .pick(let title, _): title
        }
    }

    private var addButton: some View {
        Button {
            guard !justAdded else { return }
            switch mode {
            case .log(let mealSlot, let logDate, let onAdded):
                viewModel.log(to: mealSlot, on: logDate, context: modelContext)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                withAnimation(.spring(duration: 0.3)) {
                    justAdded = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                    onAdded()
                }
            case .pick(_, let onPick):
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                withAnimation(.spring(duration: 0.3)) {
                    justAdded = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                    onPick(viewModel.item, viewModel.servingGrams)
                }
            }
        } label: {
            HStack(spacing: DesignSystem.Spacing.sm) {
                Image(systemName: justAdded ? "checkmark.circle.fill" : "plus")
                    .accessibilityHidden(true)
                Text(justAdded ? "Added" : buttonTitle)
            }
            .font(DesignSystem.Typography.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DesignSystem.Spacing.md)
            .background(DesignSystem.Colors.accent)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
            .scaleEffect(justAdded ? 0.97 : 1)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        FoodDetailView(
            item: FoodItem(
                id: "preview",
                name: "Greek Yogurt",
                brand: "Fage",
                caloriesPer100g: 97,
                proteinPer100g: 9,
                carbsPer100g: 3.9,
                fatPer100g: 5,
                fibrePer100g: 0,
                sugarPer100g: 3.9,
                sodiumMgPer100g: 35,
                defaultServingGrams: 170
            ),
            mealSlot: .breakfast,
            logDate: .now,
            onAdded: {}
        )
    }
    .modelContainer(for: FoodEntry.self, inMemory: true)
}
