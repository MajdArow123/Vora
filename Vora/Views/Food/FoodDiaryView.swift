//
//  FoodDiaryView.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import SwiftUI
import SwiftData

struct FoodDiaryView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = FoodDiaryViewModel()
    @State private var showingAISuggestion = false

    var body: some View {
        ZStack {
            DesignSystem.Colors.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                dateHeader
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    .padding(.vertical, DesignSystem.Spacing.sm)

                ScrollView {
                    VStack(spacing: DesignSystem.Spacing.lg) {
                        summaryCard

                        VStack(spacing: DesignSystem.Spacing.sm) {
                            ForEach(MealSlot.allCases) { slot in
                                MealSlotSection(
                                    slot: slot,
                                    entries: viewModel.entries(for: slot),
                                    onAdd: { viewModel.addingToSlot = slot },
                                    onDelete: { entry in
                                        withAnimation(.easeInOut(duration: 0.25)) {
                                            viewModel.delete(entry, context: modelContext)
                                        }
                                    }
                                )
                            }
                        }

                        NutrientBreakdownCard(
                            fibreG: viewModel.totalFibre,
                            sugarG: viewModel.totalSugar,
                            sodiumMg: viewModel.totalSodiumMg
                        )

                        WaterTrackerCard(
                            totalMl: viewModel.waterTotalMl,
                            targetMl: viewModel.waterTargetMl,
                            glassCount: viewModel.glassCount,
                            onAdd: { viewModel.addGlass(context: modelContext) },
                            onRemove: { viewModel.removeGlass(context: modelContext) }
                        )
                    }
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    .padding(.bottom, DesignSystem.Spacing.lg)
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 40)
                        .onEnded { value in
                            guard abs(value.translation.width) > 80,
                                  abs(value.translation.width) > abs(value.translation.height) * 2
                            else { return }
                            withAnimation(.easeInOut(duration: 0.25)) {
                                if value.translation.width > 0 {
                                    viewModel.goToPreviousDay(context: modelContext)
                                } else {
                                    viewModel.goToNextDay(context: modelContext)
                                }
                            }
                        }
                )
            }
        }
        .onAppear {
            viewModel.load(from: modelContext)
        }
        .sheet(item: $viewModel.addingToSlot, onDismiss: {
            viewModel.load(from: modelContext)
        }) { slot in
            FoodSearchView(
                mealSlot: slot,
                logDate: viewModel.logTimestamp
            )
        }
        .fullScreenCover(isPresented: $showingAISuggestion, onDismiss: {
            viewModel.load(from: modelContext)
        }) {
            AIMealSuggestionView(logDate: viewModel.logTimestamp)
        }
    }

    // MARK: - Header

    private var dateHeader: some View {
        HStack {
            navButton("chevron.left") {
                viewModel.goToPreviousDay(context: modelContext)
            }
            .accessibilityLabel("Previous day")

            Spacer()

            VStack(spacing: 0) {
                Text(viewModel.dateTitle)
                    .font(DesignSystem.Typography.headline)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Text(viewModel.dateSubtitle)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }

            Spacer()

            HStack(spacing: 0) {
                Button {
                    showingAISuggestion = true
                } label: {
                    Image(systemName: "sparkles")
                        .font(.headline)
                        .foregroundStyle(DesignSystem.Colors.accent)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("AI meal suggestion")

                Menu {
                    Button {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            viewModel.copyPreviousDay(context: modelContext)
                        }
                    } label: {
                        Label("Copy previous day", systemImage: "doc.on.doc")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.headline)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("More options")

                navButton("chevron.right") {
                    viewModel.goToNextDay(context: modelContext)
                }
                .accessibilityLabel("Next day")
            }
        }
    }

    private func navButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                action()
            }
        } label: {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .frame(width: 44, height: 44)
                .background(DesignSystem.Colors.card)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Summary

    private var summaryCard: some View {
        HStack(spacing: DesignSystem.Spacing.lg) {
            CalorieRingView(
                consumed: viewModel.totalCalories,
                target: viewModel.calorieTarget
            )

            VStack(spacing: DesignSystem.Spacing.md) {
                MacroProgressBar(
                    label: "Protein",
                    consumedG: viewModel.totalProtein,
                    targetG: viewModel.proteinTarget,
                    color: DesignSystem.Colors.macroProtein
                )
                MacroProgressBar(
                    label: "Carbs",
                    consumedG: viewModel.totalCarbs,
                    targetG: viewModel.carbsTarget,
                    color: DesignSystem.Colors.macroCarbs
                )
                MacroProgressBar(
                    label: "Fat",
                    consumedG: viewModel.totalFat,
                    targetG: viewModel.fatTarget,
                    color: DesignSystem.Colors.macroFat
                )
            }
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large))
    }
}

#Preview {
    FoodDiaryView()
        .modelContainer(
            for: [
                UserProfile.self, FoodEntry.self, WaterEntry.self, CustomFood.self,
                SavedMeal.self, SavedMealItem.self, Recipe.self, RecipeIngredient.self,
            ],
            inMemory: true
        )
}
