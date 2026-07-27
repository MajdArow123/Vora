//
//  AIMealSuggestionView.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-26.
//

import SwiftUI
import SwiftData

/// Full AI meal suggestion sheet: remaining-macro summary, meal-type
/// override, preference input, the generated meal with its foods, and
/// one-tap logging of everything. Opened from the Food diary header, the
/// Home suggestion card, and the evening protein insight on Home.
struct AIMealSuggestionView: View {
    let remaining: RemainingMacros
    let goal: GoalType
    let logDate: Date

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = MealSuggestionViewModel()
    @State private var computedMealType: MealSlot = .snack
    @State private var mealTypeOverride: MealSlot?
    @State private var preferenceText = ""
    @State private var searchFood: SuggestedFood?
    @State private var showingSlotPicker = false
    @State private var selectedSlot: MealSlot = .dinner
    @State private var logAllState: LogAllState = .idle

    private enum LogAllState: Equatable {
        case idle
        case logging(completed: Int, total: Int)
        case success(count: Int, slot: MealSlot, usedEstimates: Bool)
    }

    private static let preferenceChips = [
        "Chicken", "Fish", "Beef", "Vegetarian",
        "Quick meal", "High protein", "Pasta", "Salad",
    ]

    /// Within this many kcal of the daily target the day counts as done.
    private static let doneThreshold = 50

    private var effectiveMealType: MealSlot { mealTypeOverride ?? computedMealType }
    private var isLoading: Bool { viewModel.state == .loading }
    private var targetsHit: Bool { remaining.calories < Self.doneThreshold }

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.Colors.background
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                        if targetsHit {
                            targetsHitCard
                        } else {
                            remainingRow
                            mealTypeIndicator
                            preferenceSection
                            generateButton
                            resultSection
                        }
                    }
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    .padding(.top, DesignSystem.Spacing.md)
                    .padding(.bottom, DesignSystem.Spacing.xl)
                }
            }
            .navigationTitle("Meal Suggestion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
            }
        }
        .onAppear {
            computedMealType = MealSuggestionContext.mealType(
                hour: Calendar.current.component(.hour, from: logDate),
                hasTrainedToday: hasTrainedToday(),
                loggedSlots: loggedSlotsToday()
            )
            viewModel.loadCached()
        }
        .sheet(item: $searchFood) { food in
            FoodSearchView(
                mealSlot: effectiveMealType,
                logDate: logDate,
                initialQuery: food.name
            )
        }
        .sheet(isPresented: $showingSlotPicker) {
            MealSlotPickerSheet(selected: $selectedSlot) {
                showingSlotPicker = false
                Task { await logAll(to: selectedSlot) }
            }
            .presentationDetents([.height(440)])
        }
    }

    // MARK: - Sections

    private var targetsHitCard: some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: "checkmark.seal.fill")
                .font(.largeTitle)
                .foregroundStyle(DesignSystem.Colors.accent)
                .accessibilityHidden(true)
            Text("You've hit your targets for today.\nCome back tomorrow for a fresh suggestion.")
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(DesignSystem.Spacing.lg)
        .background(DesignSystem.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
    }

    private var remainingRow: some View {
        HStack(spacing: 0) {
            remainingColumn("\(max(0, remaining.calories))", "kcal")
            remainingColumn("\(max(0, remaining.proteinG))g", "protein")
            remainingColumn("\(max(0, remaining.carbsG))g", "carbs")
            remainingColumn("\(max(0, remaining.fatG))g", "fat")
        }
        .padding(.vertical, DesignSystem.Spacing.sm)
        .background(DesignSystem.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Remaining today")
        .accessibilityValue("\(max(0, remaining.calories)) kilocalories, \(max(0, remaining.proteinG)) grams protein, \(max(0, remaining.carbsG)) grams carbs, \(max(0, remaining.fatG)) grams fat")
    }

    private func remainingColumn(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(DesignSystem.Typography.headline)
                .foregroundStyle(DesignSystem.Colors.accent)
            Text(label)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var mealTypeIndicator: some View {
        Menu {
            ForEach(MealSlot.allCases) { slot in
                Button {
                    mealTypeOverride = slot
                } label: {
                    if slot == effectiveMealType {
                        Label(slot.displayName, systemImage: "checkmark")
                    } else {
                        Text(slot.displayName)
                    }
                }
            }
        } label: {
            HStack(spacing: DesignSystem.Spacing.xs) {
                Text("Suggesting your \(effectiveMealType.displayName.lowercased())")
                    .font(DesignSystem.Typography.headline)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(DesignSystem.Colors.accent)
        }
        .accessibilityLabel("Meal type: \(effectiveMealType.displayName). Tap to change.")
    }

    private var preferenceSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text("What are you feeling? (optional)")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .textCase(.uppercase)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    ForEach(Self.preferenceChips, id: \.self) { chip in
                        preferenceChip(chip)
                    }
                }
            }
            .scrollClipDisabled()

            TextField("Or type your preference...", text: $preferenceText)
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .padding(DesignSystem.Spacing.md)
                .background(DesignSystem.Colors.card)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
                .onChange(of: preferenceText) { _, newValue in
                    if newValue.count > 100 {
                        preferenceText = String(newValue.prefix(100))
                    }
                }
        }
    }

    private func preferenceChip(_ chip: String) -> some View {
        let isSelected = preferenceText.compare(chip, options: .caseInsensitive) == .orderedSame
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                preferenceText = chip
            }
        } label: {
            Text(chip)
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

    private var generateButton: some View {
        Button {
            Task { await generate() }
        } label: {
            HStack(spacing: DesignSystem.Spacing.sm) {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                    Text("Thinking...")
                } else {
                    Text("Get suggestion")
                }
            }
            .font(DesignSystem.Typography.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DesignSystem.Spacing.md)
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(isLoading)
    }

    @ViewBuilder
    private var resultSection: some View {
        switch viewModel.state {
        case .idle, .loading:
            EmptyView()

        case .loaded(let suggestion):
            if case .success = logAllState {
                successCard
            } else {
                suggestionCard(suggestion)
            }

        case .failed(let message):
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                Text(message)
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DesignSystem.Spacing.md)
            .background(DesignSystem.Colors.card)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
        }
    }

    private func suggestionCard(_ suggestion: MealSuggestion) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text(suggestion.mealName)
                .font(DesignSystem.Typography.title)
                .bold()
                .foregroundStyle(DesignSystem.Colors.textPrimary)
            if !suggestion.description.isEmpty {
                Text(suggestion.description)
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            Text("What you'll need:")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .textCase(.uppercase)

            ForEach(suggestion.foods) { food in
                foodRow(food)
            }

            if !suggestion.cookingTip.isEmpty {
                InfoCallout(text: suggestion.cookingTip)
            }

            Divider()

            logAllButton(total: suggestion.foods.count)
            GhostButton(title: "Refresh suggestion") {
                Task { await generate() }
            }
            .disabled(isLoading || logAllState != .idle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
    }

    private func foodRow(_ food: SuggestedFood) -> some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Text(food.name.capitalized)
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
            Spacer()
            Text("\(Int(food.grams.rounded()))g")
                .font(DesignSystem.Typography.headline)
                .foregroundStyle(DesignSystem.Colors.accent)
            Button {
                searchFood = food
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Search for \(food.name)")
        }
    }

    @ViewBuilder
    private func logAllButton(total: Int) -> some View {
        if case .logging(let completed, let loggingTotal) = logAllState {
            Button {} label: {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    ProgressView()
                        .tint(.white)
                    Text("Adding \(min(completed + 1, loggingTotal)) of \(loggingTotal)...")
                }
                .font(DesignSystem.Typography.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DesignSystem.Spacing.md)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(true)
        } else {
            PrimaryButton(title: "Log all foods") {
                guard case .loaded(let suggestion) = viewModel.state else { return }
                selectedSlot = suggestion.slot
                showingSlotPicker = true
            }
        }
    }

    private var successCard: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            if case .success(let count, let slot, let usedEstimates) = logAllState {
                ZStack {
                    Circle()
                        .fill(DesignSystem.Colors.positive.opacity(0.15))
                        .frame(width: 96, height: 96)
                    Image(systemName: "checkmark")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(DesignSystem.Colors.positive)
                }
                .transition(.scale.combined(with: .opacity))
                .accessibilityHidden(true)

                Text("Added \(count) items to \(slot.displayName)")
                    .font(DesignSystem.Typography.headline)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                if usedEstimates {
                    Label("Some items used estimates", systemImage: "exclamationmark.triangle")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.warning)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(DesignSystem.Spacing.lg)
        .background(DesignSystem.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
    }

    // MARK: - Actions

    private func generate() async {
        logAllState = .idle
        await viewModel.load(
            remaining: remaining,
            goal: goal,
            mealType: effectiveMealType,
            preference: MealSuggestionService.normalizedPreference(preferenceText),
            force: true
        )
    }

    private func logAll(to slot: MealSlot) async {
        guard case .loaded(let suggestion) = viewModel.state, !suggestion.foods.isEmpty else { return }

        let logger = SuggestedFoodsLogger()
        var drafts: [LoggedFoodDraft] = []
        // Sequential on purpose: OpenFoodFacts search is rate-limited, and
        // one request at a time gives natural per-food progress.
        for (index, food) in suggestion.foods.enumerated() {
            logAllState = .logging(completed: index, total: suggestion.foods.count)
            drafts.append(await logger.draft(for: food))
        }

        for draft in drafts {
            modelContext.insert(FoodEntry(
                date: logDate,
                mealSlot: slot,
                foodName: draft.foodName,
                servingGrams: draft.servingGrams,
                calories: draft.calories,
                proteinG: draft.proteinG,
                carbsG: draft.carbsG,
                fatG: draft.fatG,
                fibreG: draft.fibreG,
                sugarG: draft.sugarG,
                sodiumMg: draft.sodiumMg,
                barcode: draft.barcode
            ))
        }
        do {
            try modelContext.save()
        } catch {
            assertionFailure("Failed to save suggested foods: \(error)")
        }

        withAnimation(.spring(duration: 0.4)) {
            logAllState = .success(
                count: drafts.count,
                slot: slot,
                usedEstimates: drafts.contains(where: \.isEstimated)
            )
        }
        try? await Task.sleep(for: .seconds(1.4))
        dismiss()
    }

    // MARK: - Today's context

    private func hasTrainedToday() -> Bool {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: logDate)
        guard let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else { return false }
        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.date >= dayStart && $0.date < dayEnd }
        )
        return ((try? modelContext.fetch(descriptor)) ?? []).isEmpty == false
    }

    private func loggedSlotsToday() -> Set<MealSlot> {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: logDate)
        guard let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else { return [] }
        let descriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate { $0.date >= dayStart && $0.date < dayEnd }
        )
        return Set(((try? modelContext.fetch(descriptor)) ?? []).map(\.mealSlot))
    }
}

// MARK: - Meal slot picker

/// Bottom sheet asking which meal slot the suggested foods should join,
/// pre-selected to the suggestion's meal type.
private struct MealSlotPickerSheet: View {
    @Binding var selected: MealSlot
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Text("Add to which meal?")
                .font(DesignSystem.Typography.headline)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .padding(.top, DesignSystem.Spacing.lg)

            VStack(spacing: DesignSystem.Spacing.xs) {
                ForEach(MealSlot.allCases) { slot in
                    slotRow(slot)
                }
            }

            PrimaryButton(title: "Add foods", action: onConfirm)
        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(DesignSystem.Colors.background)
    }

    private func slotRow(_ slot: MealSlot) -> some View {
        Button {
            selected = slot
        } label: {
            HStack(spacing: DesignSystem.Spacing.sm) {
                Image(systemName: slot.iconName)
                    .font(.subheadline)
                    .foregroundStyle(DesignSystem.Colors.accent)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                Text(slot.displayName)
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Spacer()
                Image(systemName: selected == slot ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected == slot ? DesignSystem.Colors.accent : DesignSystem.Colors.textSecondary)
            }
            .padding(DesignSystem.Spacing.md)
            .background(DesignSystem.Colors.card)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected == slot ? .isSelected : [])
    }
}

#Preview {
    AIMealSuggestionView(
        remaining: RemainingMacros(calories: 700, proteinG: 55, carbsG: 60, fatG: 20),
        goal: .muscleGain,
        logDate: .now
    )
    .modelContainer(for: FoodEntry.self, inMemory: true)
}
