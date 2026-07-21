//
//  FoodSearchView.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import SwiftUI
import SwiftData

struct FoodSearchView: View {
    let mealSlot: MealSlot
    let logDate: Date

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = FoodSearchViewModel()
    @State private var path: [FoodItem] = []
    @State private var showingScanner = false
    @State private var showingCustomFoodForm = false

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
            .navigationTitle("Add to \(mealSlot.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: FoodItem.self) { item in
                FoodDetailView(
                    item: item,
                    mealSlot: mealSlot,
                    logDate: logDate,
                    onAdded: { dismiss() }
                )
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
        }
        .sheet(isPresented: $showingScanner) {
            BarcodeScannerView { item in
                showingScanner = false
                path.append(item)
            }
        }
        .sheet(isPresented: $showingCustomFoodForm, onDismiss: {
            viewModel.loadLocal(from: modelContext)
        }) {
            CustomFoodFormView()
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
                ForEach(SearchFilter.allCases) { filter in
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
            emptyPlaceholder(
                icon: "book.closed",
                title: "Recipes",
                message: "Build multi-ingredient recipes in a later phase."
            )
        case .meals:
            emptyPlaceholder(
                icon: "square.stack.3d.up",
                title: "Meals",
                message: "Save full meals for one-tap logging in a later phase."
            )
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
                emptyPlaceholder(
                    icon: "magnifyingglass",
                    title: "No results",
                    message: "Try a different name, or create it as a custom food."
                )
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
                Button {
                    showingCustomFoodForm = true
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(DesignSystem.Colors.accent)
                            .accessibilityHidden(true)
                        Text("Create Food")
                            .font(DesignSystem.Typography.headline)
                            .foregroundStyle(DesignSystem.Colors.accent)
                        Spacer()
                    }
                    .padding(DesignSystem.Spacing.md)
                    .background(DesignSystem.Colors.card)
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
                }
                .buttonStyle(.plain)

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

    // MARK: - Rows

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
        .modelContainer(for: [UserProfile.self, FoodEntry.self, CustomFood.self], inMemory: true)
}
