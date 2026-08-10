//
//  AIMealSuggestionView.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-26.
//

import SwiftUI
import SwiftData

/// Full AI meal suggestion sheet: per-meal budget summary, meal-type
/// override, preference input, the generated meal with editable foods, and
/// one-tap logging of everything. Opened from the Food diary header, the
/// Home suggestion card, and the evening protein insight on Home.
struct AIMealSuggestionView: View {
    let logDate: Date

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = MealSuggestionViewModel()
    @State private var computedMealType: MealSlot = .snack
    @State private var mealTypeOverride: MealSlot?
    @State private var preferenceText = ""
    @State private var searchFood: EnrichedFood?
    @State private var showingSlotPicker = false
    @State private var selectedSlot: MealSlot = .dinner
    @State private var logAllState: LogAllState = .idle
    @State private var profile: UserProfile?
    @State private var dayEntries: [FoodEntry] = []
    @State private var trainedToday = false

    private enum LogAllState: Equatable {
        case idle
        case success(count: Int, slot: MealSlot, usedEstimates: Bool)
    }

    private static let preferenceChips = [
        "Chicken", "Fish", "Beef", "Vegetarian",
        "Quick meal", "High protein", "Pasta", "Salad",
    ]

    /// Within this many kcal of the daily target the day counts as done —
    /// no meaningful meal fits, so never call the API below this.
    private static let doneThreshold = 200

    private static let gramStep: Double = 10
    private static let minimumGrams: Double = 10

    private var effectiveMealType: MealSlot { mealTypeOverride ?? computedMealType }
    private var isLoading: Bool { viewModel.state == .loading }
    private var goal: GoalType { profile?.goalType ?? .maintain }

    private var dailyTargets: MacroTargets {
        MacroTargets(
            calories: profile?.dailyCalorieTarget ?? 0,
            proteinG: profile?.proteinTargetG ?? 0,
            carbsG: profile?.carbsTargetG ?? 0,
            fatG: profile?.fatTargetG ?? 0
        )
    }

    private var targetsHit: Bool {
        let consumed = Int(dayEntries.reduce(0) { $0 + $1.calories }.rounded())
        return dailyTargets.calories - consumed <= Self.doneThreshold
    }

    /// What's left of this slot's share of the daily targets — the numbers
    /// the backend is asked to fill.
    private var mealRemaining: RemainingMacros {
        MealAllocation.remaining(
            for: effectiveMealType,
            daily: dailyTargets,
            slotConsumed: dayEntries
                .filter { $0.mealSlot == effectiveMealType }
                .map { ($0.calories, $0.proteinG, $0.carbsG, $0.fatG) }
        )
    }

    private var slotHit: Bool { MealAllocation.isSlotHit(mealRemaining) }

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
                            mealTypeIndicator
                            // The success card outranks the slot-hit gate:
                            // logging can fill the slot moments before the
                            // sheet auto-dismisses.
                            if case .success = logAllState {
                                successCard
                            } else if slotHit {
                                slotHitCard
                            } else {
                                mealBudgetRow
                                preferenceSection
                                generateButton
                                resultSection
                            }
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
        // Presented via fullScreenCover: an opaque cover stops the
        // presenting tab's content bleeding through during re-renders.
        .background(DesignSystem.Colors.background)
        .onAppear {
            loadDayContext()
            computedMealType = MealSuggestionContext.mealType(
                hour: Calendar.current.component(.hour, from: logDate),
                hasTrainedToday: trainedToday,
                loggedSlots: Set(dayEntries.map(\.mealSlot))
            )
            viewModel.loadCached()
        }
        // Fresh suggestions only arrive while the card is visible, so this
        // never enriches behind a hidden card.
        .onChange(of: viewModel.state) { _, newState in
            if case .loaded = newState {
                viewModel.enrich()
            }
        }
        .onDisappear {
            viewModel.cancelEnrichment()
        }
        .sheet(item: $searchFood, onDismiss: {
            // A food may have been logged in the search sheet, changing
            // this slot's remaining budget.
            loadDayContext()
        }) { food in
            FoodSearchView(
                mealSlot: effectiveMealType,
                logDate: logDate,
                // The AI's clean generic name seeds better searches than a
                // brand-noisy OpenFoodFacts product name.
                initialQuery: food.suggestedName
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

    private var slotHitCard: some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: "checkmark.seal.fill")
                .font(.largeTitle)
                .foregroundStyle(DesignSystem.Colors.accent)
                .accessibilityHidden(true)
            Text("You've already hit your \(effectiveMealType.displayName.lowercased()) target.\nPick another meal above.")
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(DesignSystem.Spacing.lg)
        .background(DesignSystem.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
    }

    private var mealBudgetRow: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            Text("\(Text("~\(mealRemaining.calories) kcal").foregroundStyle(DesignSystem.Colors.accent)) suggested for \(effectiveMealType.displayName.lowercased())")
                .font(DesignSystem.Typography.headline)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
            Text("\(mealRemaining.proteinG)g protein · \(mealRemaining.carbsG)g carbs · \(mealRemaining.fatG)g fat for this meal")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
            Text("(based on your daily targets)")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Meal budget")
        .accessibilityValue("\(mealRemaining.calories) kilocalories, \(mealRemaining.proteinG) grams protein, \(mealRemaining.carbsG) grams carbs, \(mealRemaining.fatG) grams fat suggested for \(effectiveMealType.displayName), based on your daily targets")
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
            suggestionCard(suggestion)

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

            if !viewModel.activeFoods.isEmpty {
                mealTotalLine
            }

            Text("What you'll need:")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .textCase(.uppercase)

            if viewModel.activeFoods.isEmpty {
                Text("All foods removed — refresh for a new suggestion")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, DesignSystem.Spacing.sm)
            } else {
                ForEach(viewModel.activeFoods) { food in
                    foodRow(food)
                }
            }

            if !suggestion.cookingTip.isEmpty {
                InfoCallout(text: suggestion.cookingTip)
            }

            Divider()

            if !viewModel.activeFoods.isEmpty {
                logAllButton
            }
            GhostButton(title: "Refresh suggestion") {
                Task { await generate() }
            }
            .disabled(isLoading || logAllState != .idle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
        // Covers a cached suggestion revealed after appear (or after a
        // slot switch away from a hit slot) — a hidden card never enriches.
        .onAppear {
            if viewModel.enrichedFoods.isEmpty {
                viewModel.enrich()
            }
        }
    }

    /// Live total over the non-removed foods; turns amber once the user
    /// has edited grams or removed a food, so what changed is obvious.
    private var mealTotalLine: some View {
        let totals = viewModel.mealTotals
        let macros = "\(Int(totals.proteinG.rounded()))g P · \(Int(totals.carbsG.rounded()))g C · \(Int(totals.fatG.rounded()))g F"
        return Group {
            if viewModel.hasEdits {
                Text("Edited: ~\(Int(totals.calories.rounded())) kcal · \(macros)")
                    .font(DesignSystem.Typography.caption.weight(.semibold))
                    .foregroundStyle(DesignSystem.Colors.warning)
            } else {
                Text("This meal: \(Text("~\(Int(totals.calories.rounded())) kcal").foregroundStyle(DesignSystem.Colors.accent)) · \(macros)")
                    .font(DesignSystem.Typography.caption.weight(.semibold))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(viewModel.hasEdits ? "Edited meal total" : "Meal total")
        .accessibilityValue("\(Int(totals.calories.rounded())) kilocalories, \(Int(totals.proteinG.rounded())) grams protein, \(Int(totals.carbsG.rounded())) grams carbs, \(Int(totals.fatG.rounded())) grams fat")
    }

    private func foodRow(_ food: EnrichedFood) -> some View {
        SwipeToRemoveRow(removeLabel: "Remove \(food.suggestedName)", onRemove: {
            viewModel.removeFood(id: food.id)
        }) {
            HStack(spacing: DesignSystem.Spacing.xs) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: DesignSystem.Spacing.xs) {
                        Text(food.displayName)
                            .font(DesignSystem.Typography.body)
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                            .lineLimit(1)
                        if food.isLoading {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                    Text(macroLine(for: food))
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .monospacedDigit()
                }
                Spacer(minLength: DesignSystem.Spacing.sm)
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.adjustGrams(id: food.id, by: -Self.gramStep, minimum: Self.minimumGrams)
                    }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(food.editedGrams > Self.minimumGrams
                                         ? DesignSystem.Colors.accent
                                         : DesignSystem.Colors.textSecondary.opacity(0.3))
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .disabled(food.editedGrams <= Self.minimumGrams)
                .accessibilityLabel("Decrease \(food.suggestedName) amount")
                Text("\(Int(food.editedGrams.rounded()))g")
                    .font(DesignSystem.Typography.headline)
                    .foregroundStyle(DesignSystem.Colors.accent)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .accessibilityLabel("\(food.suggestedName) amount")
                    .accessibilityValue(foodAccessibilityValue(for: food))
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.adjustGrams(id: food.id, by: Self.gramStep, minimum: Self.minimumGrams)
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(DesignSystem.Colors.accent)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Increase \(food.suggestedName) amount")
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
                .accessibilityLabel("Search for \(food.suggestedName)")
            }
        }
    }

    /// "~" marks every value that comes from the generic estimate rather
    /// than real OpenFoodFacts data (including while the lookup runs).
    private func macroLine(for food: EnrichedFood) -> String {
        let n = food.nutrition
        let mark = food.isApproximate ? "~" : ""
        return "\(mark)\(Int(n.proteinG.rounded()))g P · \(mark)\(Int(n.carbsG.rounded()))g C · \(mark)\(Int(n.fatG.rounded()))g F"
    }

    private func foodAccessibilityValue(for food: EnrichedFood) -> String {
        let n = food.nutrition
        let quality = food.isLoading
            ? "loading nutrition"
            : (food.isApproximate ? "estimated" : "")
        return [
            "\(Int(food.editedGrams.rounded())) grams",
            "\(Int(n.proteinG.rounded())) grams protein",
            "\(Int(n.carbsG.rounded())) grams carbs",
            "\(Int(n.fatG.rounded())) grams fat",
            quality,
        ].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    @ViewBuilder
    private var logAllButton: some View {
        if viewModel.isEnriching {
            // Logging uses the enrichment results, so it waits for them —
            // the numbers logged are exactly the numbers shown.
            Button {} label: {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    ProgressView()
                        .tint(.white)
                    Text("Loading nutrition...")
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
        // The button isn't rendered when the slot is hit; this guard
        // documents the <100 kcal contract above the service's <=0 guard.
        guard !slotHit else { return }
        logAllState = .idle
        await viewModel.load(
            remaining: mealRemaining,
            goal: goal,
            mealType: effectiveMealType,
            preference: MealSuggestionService.normalizedPreference(preferenceText),
            force: true
        )
    }

    private func logAll(to slot: MealSlot) async {
        // Pure local mapping of the enrichment results — no network, so
        // the logged entries are exactly what the sheet displayed.
        let drafts = viewModel.activeFoods.map { SuggestedFoodsLogger.draft(for: $0) }
        guard !drafts.isEmpty else { return }

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

    /// One pass over the store for everything the sheet derives from the
    /// day: profile targets, the day's food entries (logged slots, daily
    /// gate, per-slot budget), and whether a workout happened.
    private func loadDayContext() {
        profile = (try? modelContext.fetch(FetchDescriptor<UserProfile>()))?.first

        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: logDate)
        guard let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else { return }

        let foodDescriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate { $0.date >= dayStart && $0.date < dayEnd }
        )
        dayEntries = (try? modelContext.fetch(foodDescriptor)) ?? []

        let workoutDescriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.date >= dayStart && $0.date < dayEnd }
        )
        trainedToday = ((try? modelContext.fetch(workoutDescriptor)) ?? []).isEmpty == false
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
    let container = try! ModelContainer(
        for: UserProfile.self, FoodEntry.self, WorkoutSession.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    container.mainContext.insert(UserProfile(
        name: "Preview",
        dateOfBirth: .now,
        heightCm: 180,
        biologicalSex: .male,
        goalType: .muscleGain,
        activityLevel: .moderatelyActive,
        trainingSplit: .fullBody,
        dailyCalorieTarget: 2600,
        proteinTargetG: 180,
        carbsTargetG: 280,
        fatTargetG: 80
    ))
    return AIMealSuggestionView(logDate: .now)
        .modelContainer(container)
}
