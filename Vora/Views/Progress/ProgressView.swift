//
//  ProgressView.swift
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

struct ProgressView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = ProgressViewModel()
    @State private var strengthViewModel = StrengthProgressViewModel()
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
                            bodyFatChartCard
                            statRow
                            goalProjectionCard
                            StreakDotsView(weekDots: viewModel.weekDots, streakDays: viewModel.streakDays)
                            weeklyAveragesCard
                            measurementsCard
                            weightLogCard
                        case .strength:
                            StrengthProgressSection(viewModel: strengthViewModel)
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
        case .nutrition:
            nutritionViewModel.load(from: modelContext)
        }
    }

    // MARK: - Weight chart

    private var weightChartCard: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack {
                Text("Weight")
                    .font(DesignSystem.Typography.headline)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Spacer()
                if let latest = viewModel.rangeWeights.last {
                    Text(String(format: "%.1f kg", latest.weightKg))
                        .font(DesignSystem.Typography.headline)
                        .foregroundStyle(DesignSystem.Colors.accent)
                }
            }

            Picker("Range", selection: $viewModel.selectedRange) {
                ForEach(ChartRange.allCases) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: viewModel.selectedRange) {
                viewModel.rangeChanged()
            }

            if viewModel.rangeWeights.count >= 2 {
                Chart(viewModel.rangeWeights, id: \.id) { entry in
                    AreaMark(
                        x: .value("Date", entry.date, unit: .day),
                        y: .value("Weight", entry.weightKg)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [DesignSystem.Colors.accent.opacity(0.3), .clear],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.monotone)

                    LineMark(
                        x: .value("Date", entry.date, unit: .day),
                        y: .value("Weight", entry.weightKg)
                    )
                    .foregroundStyle(DesignSystem.Colors.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .interpolationMethod(.monotone)
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

    private var weightDomain: ClosedRange<Double> {
        let weights = viewModel.rangeWeights.map(\.weightKg)
        guard let min = weights.min(), let max = weights.max() else { return 0...1 }
        let pad = Swift.max((max - min) * 0.15, 0.5)
        return (min - pad)...(max + pad)
    }

    private var weightChartSummary: String {
        guard let first = viewModel.rangeWeights.first, let last = viewModel.rangeWeights.last else { return "" }
        let delta = last.weightKg - first.weightKg
        return String(format: "From %.1f to %.1f kilograms, %+.1f kilograms over this range", first.weightKg, last.weightKg, delta)
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
        if (viewModel.profile?.goalWeightKg ?? 0) <= 0 {
            return "Set a goal weight in your Profile to see a projection."
        }
        guard let projection = viewModel.goalProjection else {
            return "Log weigh-ins across a few days to project when you will reach your goal."
        }
        let goal = String(format: "%.1f kg", projection.goalWeightKg)
        let date = projection.projectedDate.formatted(.dateTime.day().month(.wide).year())
        return "At this rate you will reach \(goal) by \(date)."
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
                        Text(String(format: "%+.1f", delta))
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
        if let bodyFat = entry.bodyFatPercent, bodyFat > 0 {
            return String(format: "%.1f kg · %.1f%%", entry.weightKg, bodyFat)
        }
        return String(format: "%.1f kg", entry.weightKg)
    }
}

#Preview {
    ProgressView()
        .modelContainer(for: UserProfile.self, inMemory: true)
}
