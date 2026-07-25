//
//  SavedMealDetailView.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-25.
//

import SwiftUI
import SwiftData

struct SavedMealDetailView: View {
    let mealSlot: MealSlot
    let logDate: Date
    let onLogged: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: SavedMealDetailViewModel
    @State private var justLogged = false

    init(meal: SavedMeal, mealSlot: MealSlot, logDate: Date, onLogged: @escaping () -> Void) {
        self.mealSlot = mealSlot
        self.logDate = logDate
        self.onLogged = onLogged
        _viewModel = State(initialValue: SavedMealDetailViewModel(meal: meal))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.Colors.background
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                        totalsCard
                        itemsCard
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
            .navigationTitle(viewModel.meal.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
            }
        }
    }

    private var totalsCard: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text("Total")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .textCase(.uppercase)

            HStack(alignment: .firstTextBaseline) {
                Text("\(Int(viewModel.meal.totalCalories.rounded())) kcal")
                    .font(DesignSystem.Typography.title)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Spacer()
                macroLabel("P", viewModel.meal.totalProteinG, DesignSystem.Colors.macroProtein)
                macroLabel("C", viewModel.meal.totalCarbsG, DesignSystem.Colors.macroCarbs)
                macroLabel("F", viewModel.meal.totalFatG, DesignSystem.Colors.macroFat)
            }
            .padding(DesignSystem.Spacing.md)
            .background(DesignSystem.Colors.card)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
        }
    }

    private var itemsCard: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text("Items")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .textCase(.uppercase)

            VStack(spacing: 0) {
                let items = viewModel.meal.sortedItems
                ForEach(items) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.foodName)
                                .font(DesignSystem.Typography.body)
                                .foregroundStyle(DesignSystem.Colors.textPrimary)
                                .lineLimit(1)
                            Text("\(Int(item.servingGrams.rounded())) g")
                                .font(DesignSystem.Typography.caption)
                                .foregroundStyle(DesignSystem.Colors.textSecondary)
                        }
                        Spacer()
                        Text("\(Int(item.calories.rounded())) kcal")
                            .font(DesignSystem.Typography.headline)
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                    }
                    .padding(.vertical, DesignSystem.Spacing.sm)
                    if item.id != items.last?.id {
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

    private func macroLabel(_ letter: String, _ grams: Double, _ color: Color) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text("\(letter) \(Int(grams.rounded()))")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
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
    SavedMealDetailView(
        meal: SavedMeal(name: "Typical Breakfast", items: [
            SavedMealItem(foodName: "Oats", servingGrams: 80, calories: 300,
                          proteinG: 10, carbsG: 54, fatG: 6, orderIndex: 0),
            SavedMealItem(foodName: "Greek Yogurt", servingGrams: 170, calories: 165,
                          proteinG: 15, carbsG: 7, fatG: 8, orderIndex: 1),
        ]),
        mealSlot: .breakfast,
        logDate: .now,
        onLogged: {}
    )
    .modelContainer(for: [SavedMeal.self, SavedMealItem.self, FoodEntry.self], inMemory: true)
}
