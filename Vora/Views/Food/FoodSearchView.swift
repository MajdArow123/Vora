//
//  FoodSearchView.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import SwiftUI
import SwiftData

/// How the search screen is being used: logging foods into a meal slot
/// (the diary flow) or picking an ingredient for the recipe builder.
enum FoodSearchMode {
    case log(mealSlot: MealSlot, logDate: Date)
    case pick(onPick: (FoodItem, Double) -> Void)
}

struct FoodSearchView: View {
    let mode: FoodSearchMode
    /// Pre-fills the search field (used by AI meal suggestions to hand
    /// off the first suggested food into search).
    let initialQuery: String?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = FoodSearchViewModel()
    @State private var path: [FoodItem] = []
    @State private var showingScanner = false
    @State private var showingCustomFoodForm = false
    @State private var showingRecipeBuilder = false
    @State private var showingSaveMealPrompt = false
    @State private var showingEmptyDayAlert = false
    @State private var newMealName = ""
    @State private var mealForDetail: SavedMeal?
    @State private var recipeForDetail: Recipe?
    /// id of the item the scanner served from saved foods while offline;
    /// its detail screen shows a provenance banner.
    @State private var offlineItemID: String?

    init(mode: FoodSearchMode, initialQuery: String? = nil) {
        self.mode = mode
        self.initialQuery = initialQuery
    }

    init(mealSlot: MealSlot, logDate: Date, initialQuery: String? = nil) {
        self.init(mode: .log(mealSlot: mealSlot, logDate: logDate), initialQuery: initialQuery)
    }

    /// Slot and date when logging; nil in ingredient-picker mode.
    private var logContext: (slot: MealSlot, date: Date)? {
        if case .log(let slot, let date) = mode { return (slot, date) }
        return nil
    }

    /// Recipes and Meals are hidden while picking ingredients — recipes
    /// can't contain recipes, and there is no slot to log a meal into.
    private var visibleFilters: [SearchFilter] {
        logContext != nil ? SearchFilter.allCases : [.all, .myFoods]
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                DesignSystem.Colors.background
                    .ignoresSafeArea()

                VStack(spacing: DesignSystem.Spacing.md) {
                    searchBar
                    filterTabs
                    content
                }
                .padding(.top, DesignSystem.Spacing.md)
            }
            .navigationTitle(logContext.map { "Add to \($0.slot.displayName)" } ?? "Add Ingredient")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: FoodItem.self) { item in
                switch mode {
                case .log(let mealSlot, let logDate):
                    FoodDetailView(
                        item: item,
                        mealSlot: mealSlot,
                        logDate: logDate,
                        sourceBanner: item.id == offlineItemID
                            ? "Loaded from your saved foods (offline)"
                            : nil,
                        onAdded: { dismiss() }
                    )
                case .pick(let onPick):
                    FoodDetailView(
                        item: item,
                        mode: .pick(buttonTitle: "Add Ingredient", onPick: { picked, grams in
                            onPick(picked, grams)
                            path.removeAll()
                        })
                    )
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
            }
        }
        .task(id: "\(viewModel.query)|\(viewModel.filter.rawValue)") {
            await viewModel.search()
        }
        .onAppear {
            viewModel.loadLocal(from: modelContext)
            if let initialQuery, viewModel.query.isEmpty {
                viewModel.query = initialQuery
            }
        }
        .sheet(isPresented: $showingScanner) {
            BarcodeScannerView { item, source in
                offlineItemID = source == .offlineFallback ? item.id : nil
                showingScanner = false
                path.append(item)
            }
        }
        .sheet(isPresented: $showingCustomFoodForm, onDismiss: {
            viewModel.loadLocal(from: modelContext)
        }) {
            CustomFoodFormView()
        }
        .sheet(isPresented: $showingRecipeBuilder, onDismiss: {
            viewModel.loadLocal(from: modelContext)
        }) {
            RecipeBuilderView()
        }
        .sheet(item: $mealForDetail) { meal in
            if let logContext {
                SavedMealDetailView(
                    meal: meal,
                    mealSlot: logContext.slot,
                    logDate: logContext.date,
                    onLogged: { dismiss() }
                )
            }
        }
        .sheet(item: $recipeForDetail) { recipe in
            if let logContext {
                RecipeDetailView(
                    recipe: recipe,
                    mealSlot: logContext.slot,
                    logDate: logContext.date,
                    onLogged: { dismiss() }
                )
            }
        }
        .alert("Save as Meal", isPresented: $showingSaveMealPrompt) {
            TextField("Meal name", text: $newMealName)
            Button("Save") {
                if let logContext {
                    viewModel.saveDayAsMeal(
                        named: newMealName,
                        dayOf: logContext.date,
                        context: modelContext
                    )
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saves everything logged on this day as one reusable meal.")
        }
        .alert("Nothing to Save", isPresented: $showingEmptyDayAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Log some foods first, then save the day as a meal.")
        }
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            HStack(spacing: DesignSystem.Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .accessibilityHidden(true)
                TextField("Search foods", text: $viewModel.query)
                    .autocorrectionDisabled()
                if !viewModel.query.isEmpty {
                    Button {
                        viewModel.query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(DesignSystem.Colors.textSecondary.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle().inset(by: -14))
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(DesignSystem.Spacing.md)
            .background(DesignSystem.Colors.card)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))

            Button {
                showingScanner = true
            } label: {
                Image(systemName: "barcode.viewfinder")
                    .font(.title3)
                    .foregroundStyle(DesignSystem.Colors.accent)
                    .frame(width: 48, height: 48)
                    .background(DesignSystem.Colors.card)
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Scan barcode")
        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
    }

    // MARK: - Filter tabs

    private var filterTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DesignSystem.Spacing.sm) {
                ForEach(visibleFilters) { filter in
                    let isSelected = viewModel.filter == filter
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.filter = filter
                        }
                    } label: {
                        Text(filter.rawValue)
                            .font(DesignSystem.Typography.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(isSelected ? .white : DesignSystem.Colors.textPrimary)
                            .padding(.horizontal, DesignSystem.Spacing.md)
                            .padding(.vertical, DesignSystem.Spacing.sm)
                            .background(isSelected ? DesignSystem.Colors.accent : DesignSystem.Colors.card)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle().inset(by: -8))
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch viewModel.filter {
        case .all:
            allContent
        case .myFoods:
            myFoodsContent
        case .recipes:
            recipesContent
        case .meals:
            mealsContent
        }
    }

    @ViewBuilder
    private var allContent: some View {
        switch viewModel.state {
        case .idle:
            recentsList
        case .loading:
            VStack(spacing: DesignSystem.Spacing.md) {
                Spacer()
                SwiftUI.ProgressView()
                    .tint(DesignSystem.Colors.accent)
                Text("Searching…")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                Spacer()
            }
        case .loaded(let items):
            if items.isEmpty {
                ScrollView {
                    VStack(spacing: DesignSystem.Spacing.sm) {
                        emptyPlaceholder(
                            icon: "magnifyingglass",
                            title: "No results",
                            message: "Try a different name, or create it as a custom food."
                        )
                        .padding(.top, DesignSystem.Spacing.xl)
                        if viewModel.myFoods.isEmpty {
                            createFoodButton
                        }
                    }
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                }
            } else {
                resultsList(items)
            }
        case .failed(let message):
            emptyPlaceholder(icon: "wifi.slash", title: "Search failed", message: message)
        }
    }

    private var recentsList: some View {
        ScrollView {
            LazyVStack(spacing: DesignSystem.Spacing.sm) {
                if viewModel.myFoods.isEmpty {
                    createFoodButton
                }
                if viewModel.recents.isEmpty {
                    emptyPlaceholder(
                        icon: "clock",
                        title: "No recent foods",
                        message: "Foods you log will appear here for quick re-logging."
                    )
                    .padding(.top, DesignSystem.Spacing.xl)
                } else {
                    HStack {
                        Text("Recent")
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                            .textCase(.uppercase)
                        Spacer()
                    }
                    ForEach(viewModel.recents) { item in
                        foodRow(item)
                    }
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.bottom, DesignSystem.Spacing.lg)
        }
        .scrollDismissesKeyboard(.immediately)
    }

    private func resultsList(_ items: [FoodItem]) -> some View {
        ScrollView {
            LazyVStack(spacing: DesignSystem.Spacing.sm) {
                ForEach(items) { item in
                    foodRow(item)
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.bottom, DesignSystem.Spacing.lg)
        }
        .scrollDismissesKeyboard(.immediately)
    }

    private var myFoodsContent: some View {
        ScrollView {
            LazyVStack(spacing: DesignSystem.Spacing.sm) {
                createFoodButton

                if viewModel.filteredMyFoods.isEmpty {
                    emptyPlaceholder(
                        icon: "fork.knife",
                        title: "No custom foods yet",
                        message: "Create foods with your own macros for quick logging."
                    )
                    .padding(.top, DesignSystem.Spacing.xl)
                } else {
                    ForEach(viewModel.filteredMyFoods) { food in
                        foodRow(FoodItem(customFood: food))
                    }
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.bottom, DesignSystem.Spacing.lg)
        }
        .scrollDismissesKeyboard(.immediately)
    }

    // MARK: - Meals tab

    private var mealsContent: some View {
        ScrollView {
            LazyVStack(spacing: DesignSystem.Spacing.sm) {
                actionCard(icon: "square.and.arrow.down", title: "Save Today as Meal") {
                    guard let logContext else { return }
                    if viewModel.entries(onDayOf: logContext.date, context: modelContext).isEmpty {
                        showingEmptyDayAlert = true
                    } else {
                        newMealName = "Meal – \(logContext.date.formatted(.dateTime.day().month()))"
                        showingSaveMealPrompt = true
                    }
                }

                if viewModel.filteredSavedMeals.isEmpty {
                    emptyPlaceholder(
                        icon: "square.stack.3d.up",
                        title: "No saved meals yet",
                        message: "Save a full day of logging as a reusable meal."
                    )
                    .padding(.top, DesignSystem.Spacing.xl)
                } else {
                    ForEach(viewModel.filteredSavedMeals) { meal in
                        mealRow(meal)
                    }
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.bottom, DesignSystem.Spacing.lg)
        }
        .scrollDismissesKeyboard(.immediately)
    }

    private func mealRow(_ meal: SavedMeal) -> some View {
        Button {
            mealForDetail = meal
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(meal.name)
                        .font(DesignSystem.Typography.body)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                        .lineLimit(1)
                    Text("\(meal.items.count) item\(meal.items.count == 1 ? "" : "s") · \(macroSummary(meal.totalProteinG, meal.totalCarbsG, meal.totalFatG))")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                Text("\(Int(meal.totalCalories.rounded())) kcal")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
            .padding(DesignSystem.Spacing.md)
            .background(DesignSystem.Colors.card)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                mealForDetail = nil
                withAnimation {
                    viewModel.deleteMeal(meal, context: modelContext)
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Recipes tab

    private var recipesContent: some View {
        ScrollView {
            LazyVStack(spacing: DesignSystem.Spacing.sm) {
                actionCard(icon: "plus.circle.fill", title: "Create Recipe") {
                    showingRecipeBuilder = true
                }

                if viewModel.filteredRecipes.isEmpty {
                    emptyPlaceholder(
                        icon: "book.closed",
                        title: "No recipes yet",
                        message: "Build multi-ingredient recipes and log them in one tap."
                    )
                    .padding(.top, DesignSystem.Spacing.xl)
                } else {
                    ForEach(viewModel.filteredRecipes) { recipe in
                        recipeRow(recipe)
                    }
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.bottom, DesignSystem.Spacing.lg)
        }
        .scrollDismissesKeyboard(.immediately)
    }

    private func recipeRow(_ recipe: Recipe) -> some View {
        Button {
            recipeForDetail = recipe
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(recipe.name)
                        .font(DesignSystem.Typography.body)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                        .lineLimit(1)
                    Text("Makes \(recipe.servings) serving\(recipe.servings == 1 ? "" : "s")")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
                Spacer()
                Text("\(Int(recipe.perServingCalories.rounded())) kcal / serving")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
            .padding(DesignSystem.Spacing.md)
            .background(DesignSystem.Colors.card)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                recipeForDetail = nil
                withAnimation {
                    viewModel.deleteRecipe(recipe, context: modelContext)
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Rows & shared pieces

    private var createFoodButton: some View {
        actionCard(icon: "plus.circle.fill", title: "Create Food") {
            showingCustomFoodForm = true
        }
    }

    private func actionCard(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(DesignSystem.Colors.accent)
                    .accessibilityHidden(true)
                Text(title)
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

    private func macroSummary(_ protein: Double, _ carbs: Double, _ fat: Double) -> String {
        "P \(Int(protein.rounded())) · C \(Int(carbs.rounded())) · F \(Int(fat.rounded()))"
    }

    private func foodRow(_ item: FoodItem) -> some View {
        Button {
            path.append(item)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(DesignSystem.Typography.body)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                        .lineLimit(1)
                    if let brand = item.brand {
                        Text(brand)
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                            .lineLimit(1)
                    }
                    Text("\(macroSummary(item.proteinPer100g, item.carbsPer100g, item.fatPer100g)) per 100 g")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                Text("\(Int(item.caloriesPer100g.rounded())) kcal / 100 g")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
            .padding(DesignSystem.Spacing.md)
            .background(DesignSystem.Colors.card)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
        }
        .buttonStyle(.plain)
    }

    private func emptyPlaceholder(icon: String, title: String, message: String) -> some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: icon)
                .font(.title)
                .foregroundStyle(DesignSystem.Colors.textSecondary.opacity(0.5))
                .accessibilityHidden(true)
            Text(title)
                .font(DesignSystem.Typography.headline)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
            Text(message)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DesignSystem.Spacing.lg)
    }
}

#Preview {
    FoodSearchView(mealSlot: .breakfast, logDate: .now)
        .modelContainer(
            for: [
                UserProfile.self, FoodEntry.self, CustomFood.self,
                SavedMeal.self, SavedMealItem.self, Recipe.self, RecipeIngredient.self,
            ],
            inMemory: true
        )
}
