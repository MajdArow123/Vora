//
//  NutritionProgressSection.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-25.
//

import SwiftUI
import Charts

struct NutritionProgressSection: View {
    @Bindable var viewModel: NutritionProgressViewModel

    var body: some View {
        caloriesCard
        proteinCard
    }

    // MARK: - Calories vs target

    private var caloriesCard: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack {
                Text("Calories")
                    .font(DesignSystem.Typography.headline)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Spacer()
                if viewModel.calorieTarget > 0 {
                    Text("Target \(viewModel.calorieTarget) kcal")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
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

            if viewModel.dailyPoints.count >= 2 {
                caloriesChart
            } else {
                emptyState(
                    icon: "fork.knife",
                    message: "Log meals on at least two days to see your calorie trend."
                )
            }
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large))
    }

    private var caloriesChart: some View {
        Chart {
            ForEach(viewModel.dailyPoints) { point in
                BarMark(
                    x: .value("Date", point.day, unit: .day),
                    y: .value("Calories", point.calories)
                )
                .foregroundStyle(DesignSystem.Colors.accent)
                .cornerRadius(2)
            }

            if viewModel.calorieTarget > 0 {
                RuleMark(y: .value("Target", Double(viewModel.calorieTarget)))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .annotation(position: .topTrailing) {
                        Text("Target")
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                    }
            }
        }
        .chartYScale(domain: caloriesDomain)
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
        .accessibilityLabel("Daily calories chart")
        .accessibilityValue(caloriesSummary)
    }

    private var caloriesDomain: ClosedRange<Double> {
        let maxCalories = viewModel.dailyPoints.map(\.calories).max() ?? 0
        let top = Swift.max(maxCalories, Double(viewModel.calorieTarget)) * 1.1
        return 0...Swift.max(top, 1)
    }

    private var caloriesSummary: String {
        let points = viewModel.dailyPoints
        guard !points.isEmpty else { return "" }
        let average = points.map(\.calories).reduce(0, +) / Double(points.count)
        var summary = "Averaging \(Int(average.rounded())) calories per day over \(points.count) days"
        if viewModel.calorieTarget > 0 {
            summary += " against a target of \(viewModel.calorieTarget)"
        }
        return summary
    }

    // MARK: - Protein trend

    private var proteinCard: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack {
                Text("Protein")
                    .font(DesignSystem.Typography.headline)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Spacer()
                if viewModel.proteinTarget > 0 {
                    Text("Target \(viewModel.proteinTarget) g")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
            }

            if viewModel.dailyPoints.count >= 2 {
                proteinChart
            } else {
                emptyState(
                    icon: "fork.knife",
                    message: "Log meals on at least two days to see your protein trend."
                )
            }
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
    }

    private var proteinChart: some View {
        Chart {
            ForEach(viewModel.dailyPoints) { point in
                AreaMark(
                    x: .value("Date", point.day, unit: .day),
                    y: .value("Protein", point.proteinG)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [DesignSystem.Colors.macroProtein.opacity(0.3), .clear],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .interpolationMethod(.monotone)

                LineMark(
                    x: .value("Date", point.day, unit: .day),
                    y: .value("Protein", point.proteinG)
                )
                .foregroundStyle(DesignSystem.Colors.macroProtein)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .interpolationMethod(.monotone)
            }

            if viewModel.proteinTarget > 0 {
                RuleMark(y: .value("Target", Double(viewModel.proteinTarget)))
                    .foregroundStyle(DesignSystem.Colors.macroProtein.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            }
        }
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
        .frame(height: 160)
        .accessibilityLabel("Daily protein chart")
        .accessibilityValue(proteinSummary)
    }

    private var proteinSummary: String {
        let points = viewModel.dailyPoints
        guard !points.isEmpty else { return "" }
        let average = points.map(\.proteinG).reduce(0, +) / Double(points.count)
        var summary = "Averaging \(Int(average.rounded())) grams of protein per day over \(points.count) days"
        if viewModel.proteinTarget > 0 {
            summary += " against a target of \(viewModel.proteinTarget)"
        }
        return summary
    }

    // MARK: - Empty state

    private func emptyState(icon: String, message: String) -> some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: icon)
                .font(.title)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .accessibilityHidden(true)
            Text(message)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 140)
    }
}

#Preview {
    ScrollView {
        VStack(spacing: DesignSystem.Spacing.md) {
            NutritionProgressSection(viewModel: NutritionProgressViewModel())
        }
        .padding()
    }
    .background(DesignSystem.Colors.background)
}
