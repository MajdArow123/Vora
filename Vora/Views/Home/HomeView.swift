//
//  HomeView.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import SwiftUI
import SwiftData
import Charts

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = HomeViewModel()
    @State private var showingSession = false
    @State private var quickLogSlot: MealSlot?
    @State private var showingLogWeight = false
    @State private var showingSupplementManagement = false
    @State private var showingAddSupplement = false
    @State private var suggestionViewModel = MealSuggestionViewModel()
    @State private var showingAISuggestion = false
    @State private var showingCheckIn = false

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.Colors.background
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: DesignSystem.Spacing.md) {
                        header
                        WeeklyCheckInCard(state: viewModel.checkInState) {
                            showingCheckIn = true
                        }
                        VStack(spacing: DesignSystem.Spacing.xs) {
                            calorieCard
                            macroMiniCards
                            quickLogFoodButton
                        }
                        todayWorkoutCard
                        weightTrendCard
                        WaterTrackerCard(
                            totalMl: viewModel.waterTotalMl,
                            targetMl: viewModel.waterTargetMl,
                            glassCount: viewModel.glassCount,
                            onAdd: { viewModel.addGlass(context: modelContext) },
                            onRemove: { viewModel.removeGlass(context: modelContext) }
                        )
                        SupplementsCard(
                            supplements: viewModel.activeSupplements,
                            takenIDs: viewModel.takenSupplementIDs,
                            onToggle: { viewModel.toggleSupplement($0, context: modelContext) },
                            onManage: { showingSupplementManagement = true },
                            onAdd: { showingAddSupplement = true }
                        )
                        StreakDotsView(
                            weekDots: viewModel.weekDots,
                            streakDays: viewModel.streakDays,
                            foodDots: viewModel.foodWeekDots,
                            foodStreakDays: viewModel.foodStreakDays
                        )
                        if let insight = viewModel.insight {
                            InsightCard(
                                insight: insight,
                                onTap: insight.rule == .aiProteinSuggestion
                                    ? { showingAISuggestion = true }
                                    : nil
                            )
                        }
                        if showsMealSuggestionCard {
                            MealSuggestionCard(
                                state: suggestionViewModel.state,
                                onViewAndLog: { showingAISuggestion = true },
                                onRefresh: { refreshSuggestion(force: true) }
                            )
                            .task { await loadSuggestion() }
                        }
                    }
                    .padding(.horizontal, DesignSystem.Spacing.md)
                    .padding(.bottom, DesignSystem.Spacing.xl)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .onAppear {
            viewModel.load(from: modelContext)
        }
        .task {
            if await WeightImportService().sync(context: modelContext) > 0 {
                viewModel.load(from: modelContext)
            }
        }
        .fullScreenCover(isPresented: $showingSession, onDismiss: {
            viewModel.load(from: modelContext)
            // A finished session moved the cycle, and reminders name its next day.
            if viewModel.cycleToday != nil {
                NotificationService.shared.refreshAll(context: modelContext)
            }
        }) {
            ActiveSessionView(
                sessionName: viewModel.sessionName,
                templatePlan: viewModel.templatePlan(context: modelContext),
                templateSlot: viewModel.templateSlot,
                units: viewModel.profile?.preferredUnits ?? .metric
            )
        }
        .sheet(item: $quickLogSlot, onDismiss: {
            viewModel.load(from: modelContext)
        }) { slot in
            FoodSearchView(mealSlot: slot, logDate: .now)
        }
        .sheet(isPresented: $showingLogWeight, onDismiss: {
            viewModel.load(from: modelContext)
        }) {
            LogWeightSheet()
                .presentationDetents([.height(380)])
        }
        .sheet(isPresented: $showingSupplementManagement, onDismiss: {
            viewModel.load(from: modelContext)
        }) {
            SupplementManagementView()
        }
        .sheet(isPresented: $showingAddSupplement, onDismiss: {
            viewModel.load(from: modelContext)
        }) {
            SupplementEditView(supplement: nil)
        }
        .fullScreenCover(isPresented: $showingAISuggestion, onDismiss: {
            // Foods can be logged inside the sheet, and the sheet may have
            // refreshed the shared day cache — reconverge both.
            viewModel.load(from: modelContext)
            refreshSuggestion(force: false)
        }) {
            AIMealSuggestionView(logDate: .now)
        }
        .sheet(isPresented: $showingCheckIn, onDismiss: {
            // Applied targets change what's left to eat today.
            refreshSuggestion(force: false)
        }) {
            if case .ready(let proposal) = viewModel.checkInState {
                WeeklyCheckInSheet(
                    proposal: proposal,
                    units: units,
                    onApply: { try viewModel.applyCheckIn(proposal, context: modelContext) },
                    onSkip: { try viewModel.skipCheckIn(proposal, context: modelContext) }
                )
            }
        }
    }

    // MARK: - AI meal suggestion

    /// Only worth showing once the day is under way, there is a real
    /// calorie gap left to close, and the suggested slot still has room —
    /// the card's auto-load must never fire a request the backend rejects.
    private var showsMealSuggestionCard: Bool {
        viewModel.remainingMacros.calories > 200
            && Calendar.current.component(.hour, from: .now) >= 11
            && viewModel.mealRemaining(for: suggestedMealType).calories
                >= MealAllocation.minimumMealCalories
    }

    private func loadSuggestion() async {
        await suggestionViewModel.load(
            remaining: viewModel.mealRemaining(for: suggestedMealType),
            goal: viewModel.profile?.goalType ?? .maintain,
            mealType: suggestedMealType
        )
    }

    private func refreshSuggestion(force: Bool) {
        Task {
            await suggestionViewModel.load(
                remaining: viewModel.mealRemaining(for: suggestedMealType),
                goal: viewModel.profile?.goalType ?? .maintain,
                mealType: suggestedMealType,
                force: force
            )
        }
    }

    private var suggestedMealType: MealSlot {
        MealSuggestionContext.mealType(
            hour: Calendar.current.component(.hour, from: .now),
            hasTrainedToday: viewModel.hasTrainedToday,
            loggedSlots: viewModel.todayMealSlots
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                Text(viewModel.profile?.name.split(separator: " ").first.map(String.init) ?? "Welcome")
                    .font(DesignSystem.Typography.screenTitle)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
            }
            Spacer()
            Text(Date.now.formatted(.dateTime.weekday(.wide).day().month()))
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
        }
        .padding(.top, DesignSystem.Spacing.sm)
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Good morning"
        case 12..<18: "Good afternoon"
        default: "Good evening"
        }
    }

    // MARK: - Calories & macros

    private var calorieCard: some View {
        HStack(spacing: DesignSystem.Spacing.lg) {
            CalorieRingView(
                consumed: viewModel.totalCalories,
                target: viewModel.profile?.dailyCalorieTarget ?? 0
            )

            VStack(alignment: .leading, spacing: 6) {
                Text("Today")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .textCase(.uppercase)
                Text("\(Int(viewModel.totalCalories.rounded())) kcal")
                    .font(DesignSystem.Typography.title)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Text("of \(viewModel.profile?.dailyCalorieTarget ?? 0) kcal target")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
            Spacer()
        }
        .padding(DesignSystem.Spacing.md)
        .frame(maxWidth: .infinity)
        .background(DesignSystem.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Calories")
        .accessibilityValue("\(Int(viewModel.totalCalories.rounded())) of \(viewModel.profile?.dailyCalorieTarget ?? 0) kilocalories")
    }

    private var macroMiniCards: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            macroMiniCard("Protein", viewModel.totalProtein, viewModel.profile?.proteinTargetG ?? 0, DesignSystem.Colors.macroProtein)
            macroMiniCard("Carbs", viewModel.totalCarbs, viewModel.profile?.carbsTargetG ?? 0, DesignSystem.Colors.macroCarbs)
            macroMiniCard("Fat", viewModel.totalFat, viewModel.profile?.fatTargetG ?? 0, DesignSystem.Colors.macroFat)
        }
    }

    private var quickLogFoodButton: some View {
        HStack {
            Spacer()
            Button {
                quickLogSlot = MealSlot.suggested()
            } label: {
                Label("Log Food", systemImage: "plus")
                    .font(DesignSystem.Typography.caption.weight(.semibold))
                    .foregroundStyle(DesignSystem.Colors.accent)
                    .padding(.horizontal, DesignSystem.Spacing.sm + 4)
                    .padding(.vertical, 6)
                    .background(DesignSystem.Colors.accent.opacity(0.12))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Log food")
        }
    }

    private func macroMiniCard(_ label: String, _ consumed: Double, _ target: Int, _ color: Color) -> some View {
        let progress = target > 0 ? min(consumed / Double(target), 1) : 0
        return VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            Text(label)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)

            Text("\(Int(consumed.rounded())) / \(target) g")
                .font(DesignSystem.Typography.body.weight(.bold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(color.opacity(0.15))
                    Capsule()
                        .fill(color)
                        .frame(width: max(geo.size.width * progress, progress > 0 ? 6 : 0))
                        .animation(.easeOut(duration: 0.5), value: progress)
                }
            }
            .frame(height: 6)
        }
        .padding(DesignSystem.Spacing.md)
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
        .background(DesignSystem.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(Int(consumed.rounded())) of \(target) grams")
    }

    // MARK: - Today's workout

    @ViewBuilder
    private var todayWorkoutCard: some View {
        let muscleGroups = viewModel.todayMuscleGroups
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.workoutCardLabel)
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .textCase(.uppercase)
                    Text(viewModel.todayTitle ?? "No plan")
                        .font(DesignSystem.Typography.title)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                    if !muscleGroups.isEmpty {
                        Text(muscleGroups.map(\.capitalized).joined(separator: " · "))
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                    }
                }
                Spacer()
                Image(systemName: viewModel.isRestToday ? "moon.zzz.fill" : "dumbbell.fill")
                    .font(.title2)
                    .foregroundStyle(DesignSystem.Colors.accent)
                    .accessibilityHidden(true)
            }

            if viewModel.hasTrainedToday {
                Label("Session logged", systemImage: "checkmark.circle.fill")
                    .font(DesignSystem.Typography.headline)
                    .foregroundStyle(DesignSystem.Colors.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DesignSystem.Spacing.sm)
            } else if viewModel.isRestToday {
                Text("Rest and recover — your streak carries through rest days.")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            } else {
                Button {
                    showingSession = true
                } label: {
                    Text("Start Session")
                        .font(DesignSystem.Typography.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DesignSystem.Spacing.sm + 4)
                        .background(DesignSystem.Colors.accent)
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large))
    }

    // MARK: - Weight trend

    private var units: UnitSystem { viewModel.profile?.preferredUnits ?? .metric }

    private var weightTrendCard: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            HStack {
                Text("Weight trend")
                    .font(DesignSystem.Typography.headline)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Spacer()
                Button {
                    showingLogWeight = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(DesignSystem.Colors.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Log weight")
            }

            if let trend = viewModel.weightTrend {
                HStack(alignment: .firstTextBaseline) {
                    Text(UnitConversion.bodyWeightText(kg: trend.currentKg, units: units))
                        .font(DesignSystem.Typography.title)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                    Spacer()
                    if let change = viewModel.weekTrendChangeKg {
                        HStack(spacing: 3) {
                            Image(systemName: change <= 0 ? "arrow.down.right" : "arrow.up.right")
                                .font(.caption2)
                                .accessibilityHidden(true)
                            Text("\(UnitConversion.bodyWeightChangeText(kg: change, units: units)) this week")
                                .font(DesignSystem.Typography.caption)
                        }
                        .foregroundStyle(change <= 0 ? DesignSystem.Colors.accent : DesignSystem.Colors.macroFat)
                    }
                }
            }

            if viewModel.recentTrendPoints.count >= 2 {
                Chart(viewModel.recentTrendPoints) { point in
                    LineMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value("Trend", UnitConversion.displayWeight(kg: point.trendKg, units: units))
                    )
                    .foregroundStyle(DesignSystem.Colors.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                }
                .chartYScale(domain: weightDomain)
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 3)) {
                        AxisGridLine().foregroundStyle(DesignSystem.Colors.textSecondary.opacity(0.15))
                        AxisValueLabel().foregroundStyle(DesignSystem.Colors.textSecondary)
                    }
                }
                .frame(height: 90)
                .accessibilityLabel("Weight trend chart")
                .accessibilityValue(weightTrendSummary)
            } else {
                Text("Log your weight on the Progress tab to see your trend here.")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            }
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
    }

    private var weightDomain: ClosedRange<Double> {
        let weights = viewModel.recentTrendPoints.map { UnitConversion.displayWeight(kg: $0.trendKg, units: units) }
        guard let min = weights.min(), let max = weights.max() else { return 0...1 }
        let pad = Swift.max((max - min) * 0.3, 0.5)
        return (min - pad)...(max + pad)
    }

    private var weightTrendSummary: String {
        guard let first = viewModel.recentTrendPoints.first, let last = viewModel.recentTrendPoints.last else { return "" }
        return String(
            format: "Trend from %.1f to %.1f %@ over the last two weeks",
            UnitConversion.displayWeight(kg: first.trendKg, units: units),
            UnitConversion.displayWeight(kg: last.trendKg, units: units),
            UnitConversion.spokenWeightUnit(units)
        )
    }
}

#Preview {
    HomeView()
        .modelContainer(for: UserProfile.self, inMemory: true)
}
