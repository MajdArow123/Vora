//
//  ProgressScreen.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import SwiftUI
import SwiftData
import Charts

private enum ProgressSegment: String, CaseIterable, Identifiable {
    case weight = "Weight"
    case strength = "Strength"
    case nutrition = "Nutrition"

    var id: String { rawValue }
}

struct ProgressScreen: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = ProgressViewModel()
    @State private var strengthViewModel = StrengthProgressViewModel()
    @State private var levelsViewModel = LevelsViewModel()
    @State private var nutritionViewModel = NutritionProgressViewModel()
    @State private var segment: ProgressSegment = .weight
    @State private var showingLogWeight = false
    @State private var showingLogMeasurement = false

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.Colors.background
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: DesignSystem.Spacing.md) {
                        segmentPicker

                        switch segment {
                        case .weight:
                            weightChartCard
                            expenditureChartCard
                            bodyFatChartCard
                            statRow
                            goalProjectionCard
                            StreakDotsView(weekDots: viewModel.weekDots, streakDays: viewModel.streakDays)
                            weeklyAveragesCard
                            measurementsCard
                            if viewModel.hasActiveSupplements {
                                SupplementConsistencyCard(
                                    streakDays: viewModel.supplementStreakDays,
                                    weekDots: viewModel.supplementWeekDots,
                                    monthPercent: viewModel.supplementMonthPercent
                                )
                            }
                            weightLogCard
                        case .strength:
                            StrengthProgressSection(
                                viewModel: strengthViewModel,
                                levelsViewModel: levelsViewModel,
                                units: viewModel.unitSystem
                            )
                        case .nutrition:
                            NutritionProgressSection(viewModel: nutritionViewModel)
                        }
                    }
                    .padding(.horizontal, DesignSystem.Spacing.md)
                    .padding(.bottom, DesignSystem.Spacing.xl)
                }
            }
            .navigationTitle("Progress")
            .toolbar {
                if segment == .weight {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingLogWeight = true
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(DesignSystem.Colors.accent)
                        }
                        .accessibilityLabel("Log weight")
                    }
                }
            }
        }
        .onAppear { loadActiveSegment() }
        .task {
            if await WeightImportService().sync(context: modelContext) > 0 {
                loadActiveSegment()
            }
        }
        .onChange(of: segment) { loadActiveSegment() }
        .sheet(isPresented: $showingLogWeight, onDismiss: {
            loadActiveSegment()
        }) {
            LogWeightSheet()
                .presentationDetents([.height(380)])
        }
        .sheet(isPresented: $showingLogMeasurement, onDismiss: {
            loadActiveSegment()
        }) {
            MeasurementLogView()
        }
    }

    private var segmentPicker: some View {
        Picker("Section", selection: $segment) {
            ForEach(ProgressSegment.allCases) { section in
                Text(section.rawValue).tag(section)
            }
        }
        .pickerStyle(.segmented)
    }

    private func loadActiveSegment() {
        switch segment {
        case .weight:
            viewModel.load(from: modelContext)
        case .strength:
            strengthViewModel.load(from: modelContext)
            levelsViewModel.load(from: modelContext)
        case .nutrition:
            nutritionViewModel.load(from: modelContext)
        }
    }

    // MARK: - Weight chart

    private var weightChartCard: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack(alignment: .firstTextBaseline) {
                Text("Weight trend")
                    .font(DesignSystem.Typography.headline)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Spacer()
                if let trend = viewModel.weightTrend {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(UnitConversion.bodyWeightText(kg: trend.currentKg, units: viewModel.unitSystem))
                            .font(DesignSystem.Typography.headline)
                            .foregroundStyle(DesignSystem.Colors.accent)
                        if let weekly = trend.result.change7Kg {
                            Text("\(UnitConversion.bodyWeightChangeText(kg: weekly, units: viewModel.unitSystem))/week")
                                .font(DesignSystem.Typography.caption)
                                .foregroundStyle(DesignSystem.Colors.textSecondary)
                        }
                    }
                }
            }

            Picker("Range", selection: $viewModel.selectedRange) {
                ForEach(ChartRange.allCases) { range in
                    Text(range.displayName).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: viewModel.selectedRange) {
                viewModel.rangeChanged()
            }

            if viewModel.rangeTrendPoints.count >= 2 {
                Chart(viewModel.rangeTrendPoints) { point in
                    if let scaleKg = point.scaleKg {
                        PointMark(
                            x: .value("Date", point.date, unit: .day),
                            y: .value("Scale weight", displayWeight(scaleKg))
                        )
                        .foregroundStyle(DesignSystem.Colors.accent.opacity(0.3))
                        .symbolSize(24)
                    }

                    LineMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value("Trend", displayWeight(point.trendKg))
                    )
                    .foregroundStyle(DesignSystem.Colors.accent)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                }
                .chartYScale(domain: weightDomain)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) {
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                    }
                }
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) {
                        AxisGridLine().foregroundStyle(DesignSystem.Colors.textSecondary.opacity(0.15))
                        AxisValueLabel().foregroundStyle(DesignSystem.Colors.textSecondary)
                    }
                }
                .frame(height: 200)
                .accessibilityLabel("Weight trend chart")
                .accessibilityValue(weightChartSummary)
            } else {
                VStack(spacing: DesignSystem.Spacing.sm) {
                    Image(systemName: "scalemass")
                        .font(.title)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .accessibilityHidden(true)
                    Text("Log at least two weigh-ins to see your trend.")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity, minHeight: 140)
            }
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large))
    }

    private func displayWeight(_ kg: Double) -> Double {
        UnitConversion.displayWeight(kg: kg, units: viewModel.unitSystem)
    }

    /// Fits both the trend and the scale dots.
    private var weightDomain: ClosedRange<Double> {
        let weights = viewModel.rangeTrendPoints.flatMap { point in
            [point.trendKg, point.scaleKg].compactMap { $0 }
        }.map(displayWeight)
        guard let min = weights.min(), let max = weights.max() else { return 0...1 }
        let pad = Swift.max((max - min) * 0.15, 0.5)
        return (min - pad)...(max + pad)
    }

    private var weightChartSummary: String {
        guard let first = viewModel.rangeTrendPoints.first, let last = viewModel.rangeTrendPoints.last else { return "" }
        let units = viewModel.unitSystem
        return String(
            format: "Trend from %.1f to %.1f %@, %@ %@ over this range",
            displayWeight(first.trendKg),
            displayWeight(last.trendKg),
            UnitConversion.spokenWeightUnit(units),
            UnitConversion.bodyWeightChangeNumberText(kg: last.trendKg - first.trendKg, units: units),
            UnitConversion.spokenWeightUnit(units)
        )
    }

    // MARK: - Expenditure chart

    private var expenditureChartCard: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack(alignment: .firstTextBaseline) {
                Text("Expenditure")
                    .font(DesignSystem.Typography.headline)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Spacer()
                if let latest = viewModel.allCheckIns.last {
                    Text("\(ExpenditureExplanation.kcal(latest.estimateKcal))/day")
                        .font(DesignSystem.Typography.headline)
                        .foregroundStyle(DesignSystem.Colors.accent)
                }
            }

            if viewModel.rangeCheckIns.count >= 2 {
                Chart(viewModel.rangeCheckIns) { checkIn in
                    LineMark(
                        x: .value("Date", checkIn.date, unit: .day),
                        y: .value("Expenditure", checkIn.estimateKcal)
                    )
                    .foregroundStyle(DesignSystem.Colors.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))

                    PointMark(
                        x: .value("Date", checkIn.date, unit: .day),
                        y: .value("Expenditure", checkIn.estimateKcal)
                    )
                    .foregroundStyle(DesignSystem.Colors.accent)
                    .symbolSize(30)
                }
                .chartYScale(domain: expenditureDomain)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) {
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                    }
                }
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) {
                        AxisGridLine().foregroundStyle(DesignSystem.Colors.textSecondary.opacity(0.15))
                        AxisValueLabel().foregroundStyle(DesignSystem.Colors.textSecondary)
                    }
                }
                .frame(height: 140)
                .accessibilityLabel("Expenditure chart")
                .accessibilityValue(expenditureChartSummary)
            } else {
                Text("Your expenditure appears here after two weekly check-ins in this range.")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large))
    }

    private var expenditureDomain: ClosedRange<Double> {
        let values = viewModel.rangeCheckIns.map(\.estimateKcal)
        guard let min = values.min(), let max = values.max() else { return 0...1 }
        let pad = Swift.max((max - min) * 0.15, 50)
        return (min - pad)...(max + pad)
    }

    private var expenditureChartSummary: String {
        guard let first = viewModel.rangeCheckIns.first, let last = viewModel.rangeCheckIns.last else { return "" }
        return "From \(Int(first.estimateKcal.rounded())) to \(Int(last.estimateKcal.rounded())) kilocalories a day over this range"
    }

    // MARK: - Body fat chart

    @ViewBuilder
    private var bodyFatChartCard: some View {
        if viewModel.hasAnyBodyFat {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                HStack {
                    Text("Body Fat")
                        .font(DesignSystem.Typography.headline)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                    Spacer()
                    if let latest = viewModel.bodyFatPoints.last {
                        Text(String(format: "%.1f%%", latest.value))
                            .font(DesignSystem.Typography.headline)
                            .foregroundStyle(DesignSystem.Colors.accent)
                    }
                }

                if viewModel.bodyFatPoints.count >= 2 {
                    Chart(viewModel.bodyFatPoints) { point in
                        LineMark(
                            x: .value("Date", point.date, unit: .day),
                            y: .value("Body fat", point.value)
                        )
                        .foregroundStyle(DesignSystem.Colors.accent)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .interpolationMethod(.monotone)
                    }
                    .chartYScale(domain: bodyFatDomain)
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) {
                            AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                                .foregroundStyle(DesignSystem.Colors.textSecondary)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) {
                            AxisGridLine().foregroundStyle(DesignSystem.Colors.textSecondary.opacity(0.15))
                            AxisValueLabel().foregroundStyle(DesignSystem.Colors.textSecondary)
                        }
                    }
                    .frame(height: 120)
                    .accessibilityLabel("Body fat trend chart")
                    .accessibilityValue(bodyFatChartSummary)
                } else {
                    Text("Log body fat with a couple more weigh-ins to see a trend.")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
            }
            .padding(DesignSystem.Spacing.md)
            .background(DesignSystem.Colors.card)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large))
        }
    }

    private var bodyFatDomain: ClosedRange<Double> {
        let values = viewModel.bodyFatPoints.map(\.value)
        guard let min = values.min(), let max = values.max() else { return 0...1 }
        let pad = Swift.max((max - min) * 0.15, 0.5)
        return (min - pad)...(max + pad)
    }

    private var bodyFatChartSummary: String {
        guard let first = viewModel.bodyFatPoints.first, let last = viewModel.bodyFatPoints.last else { return "" }
        let delta = last.value - first.value
        return String(format: "From %.1f to %.1f percent, %+.1f percent over this range", first.value, last.value, delta)
    }

    // MARK: - Stat row

    private var statRow: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            statTile(
                value: "\(viewModel.daysTracked)",
                label: "Days tracked",
                icon: "calendar"
            )
            statTile(
                value: "\(viewModel.streakDays)",
                label: "Day streak",
                icon: "flame.fill"
            )
        }
    }

    private func statTile(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(DesignSystem.Colors.accent)
                    .accessibilityHidden(true)
                Text(value)
                    .font(DesignSystem.Typography.title)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
            }
            Text(label)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Goal projection

    @ViewBuilder
    private var goalProjectionCard: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            Image(systemName: "target")
                .font(.title3)
                .foregroundStyle(DesignSystem.Colors.accent)
                .frame(width: 36, height: 36)
                .background(DesignSystem.Colors.accent.opacity(0.12))
                .clipShape(Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Goal projection")
                    .font(DesignSystem.Typography.headline)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Text(projectionText)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
    }

    private var projectionText: String {
        switch viewModel.goalProjection {
        case .noGoal:
            return "Set a goal weight in your Profile to see a projection."
        case .notEnoughData(let loggedDays, let needed) where loggedDays < needed:
            return "Not enough data yet: \(loggedDays) of \(needed) days logged."
        case .notEnoughData:
            return "Not enough recent data. Log a weigh-in to update your projection."
        case .notMovingTowardGoal:
            return "Your trend isn't moving toward your goal right now."
        case .goalReached(let goalKg):
            return "You've reached your goal of \(UnitConversion.bodyWeightText(kg: goalKg, units: viewModel.unitSystem))."
        case .projected(let goalKg, let date):
            let goal = UnitConversion.bodyWeightText(kg: goalKg, units: viewModel.unitSystem)
            return "At this rate you will reach \(goal) by \(date.formatted(.dateTime.day().month(.wide).year()))."
        }
    }

    // MARK: - Weekly averages

    private var weeklyAveragesCard: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text("Weekly Averages")
                .font(DesignSystem.Typography.headline)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            ForEach(viewModel.weeklyAverages) { item in
                HStack {
                    Text(item.label)
                        .font(DesignSystem.Typography.body)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                    Spacer()
                    Text("\(Int(item.average.rounded())) / \(item.target) \(item.unit)")
                        .font(DesignSystem.Typography.body)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                }
                if item.id != viewModel.weeklyAverages.last?.id {
                    Divider()
                }
            }
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
    }

    // MARK: - Body measurements

    private var measurementsCard: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            HStack {
                Text("Body measurements")
                    .font(DesignSystem.Typography.headline)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Spacer()
                Button {
                    showingLogMeasurement = true
                } label: {
                    Label("Log", systemImage: "plus")
                        .font(DesignSystem.Typography.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(DesignSystem.Colors.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Log measurements")
            }

            if let latest = viewModel.latestMeasurement {
                NavigationLink {
                    MeasurementHistoryView(viewModel: viewModel)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(latest.date.formatted(.dateTime.day().month(.abbreviated).year()))
                                .font(DesignSystem.Typography.caption)
                                .foregroundStyle(DesignSystem.Colors.textSecondary)
                            Text(MeasurementField.summary(for: latest, units: viewModel.unitSystem, limit: 3))
                                .font(DesignSystem.Typography.body)
                                .foregroundStyle(DesignSystem.Colors.textPrimary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                            .accessibilityHidden(true)
                    }
                    .padding(.vertical, 2)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows measurement history")
            } else {
                Text("No measurements yet. Tap Log to record your first.")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .padding(.vertical, DesignSystem.Spacing.sm)
            }
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
    }

    // MARK: - Weight log

    private var weightLogCard: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text("Weight Log")
                .font(DesignSystem.Typography.headline)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            if viewModel.allWeightsDescending.isEmpty {
                Text("No weigh-ins yet. Tap + to log your first.")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .padding(.vertical, DesignSystem.Spacing.sm)
            }

            ForEach(viewModel.allWeightsDescending.prefix(10), id: \.id) { entry in
                HStack {
                    Text(entry.date.formatted(.dateTime.day().month(.abbreviated).year()))
                        .font(DesignSystem.Typography.body)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                    Spacer()
                    if let delta = viewModel.delta(for: entry) {
                        Text(UnitConversion.bodyWeightChangeNumberText(kg: delta, units: viewModel.unitSystem))
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(delta <= 0 ? DesignSystem.Colors.positive : DesignSystem.Colors.negative)
                    }
                    Text(weightRowText(entry))
                        .font(DesignSystem.Typography.body)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                        .frame(minWidth: 70, alignment: .trailing)
                }
                .padding(.vertical, 2)
            }
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
    }

    /// "78.8 kg" or "78.8 kg · 12.4%" when body fat was recorded.
    private func weightRowText(_ entry: WeightEntry) -> String {
        let weight = UnitConversion.bodyWeightText(kg: entry.weightKg, units: viewModel.unitSystem)
        if let bodyFat = entry.bodyFatPercent, bodyFat > 0 {
            return "\(weight) · \(String(format: "%.1f%%", bodyFat))"
        }
        return weight
    }
}

#Preview {
    ProgressScreen()
        .modelContainer(for: UserProfile.self, inMemory: true)
}
