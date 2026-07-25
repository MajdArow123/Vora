//
//  StrengthProgressSection.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-25.
//

import SwiftUI
import Charts

struct StrengthProgressSection: View {
    @Bindable var viewModel: StrengthProgressViewModel

    var body: some View {
        progressionCard
        weeklyVolumeCard
        cardioCard
    }

    // MARK: - Exercise progression

    private var progressionCard: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            if viewModel.exerciseNames.isEmpty {
                emptyState(
                    icon: "dumbbell",
                    message: "Log a workout to unlock strength analytics."
                )
            } else {
                HStack {
                    exercisePicker
                    Spacer()
                    if let latest = viewModel.progression.last {
                        Text("e1RM \(String(format: "%.1f", latest.estimatedOneRepMax)) kg")
                            .font(DesignSystem.Typography.headline)
                            .foregroundStyle(DesignSystem.Colors.accent)
                    }
                }

                // This range picker drives all three cards in the section.
                Picker("Range", selection: $viewModel.selectedRange) {
                    ForEach(ChartRange.allCases) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: viewModel.selectedRange) {
                    viewModel.rangeChanged()
                }

                if viewModel.progression.count >= 2 {
                    progressionChart
                } else {
                    emptyState(
                        icon: "dumbbell",
                        message: "Complete this exercise in at least two sessions to see progression."
                    )
                }
            }
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large))
    }

    private var exercisePicker: some View {
        Menu {
            ForEach(viewModel.exerciseNames, id: \.self) { name in
                Button(name) {
                    viewModel.selectedExercise = name
                    viewModel.exerciseChanged()
                }
            }
        } label: {
            HStack(spacing: DesignSystem.Spacing.xs) {
                Text(viewModel.selectedExercise ?? "Exercise")
                    .font(DesignSystem.Typography.headline)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
        }
        .accessibilityLabel("Choose exercise")
        .accessibilityValue(viewModel.selectedExercise ?? "None")
    }

    private var progressionChart: some View {
        Chart(viewModel.progression) { entry in
            AreaMark(
                x: .value("Date", entry.date, unit: .day),
                y: .value("Weight", entry.bestWeightKg)
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
                y: .value("Weight", entry.bestWeightKg)
            )
            .foregroundStyle(DesignSystem.Colors.accent)
            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
            .interpolationMethod(.monotone)
        }
        .chartYScale(domain: progressionDomain)
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
        .accessibilityLabel("Strength progression chart")
        .accessibilityValue(progressionSummary)
    }

    private var progressionDomain: ClosedRange<Double> {
        let weights = viewModel.progression.map(\.bestWeightKg)
        guard let min = weights.min(), let max = weights.max() else { return 0...1 }
        let pad = Swift.max((max - min) * 0.15, 0.5)
        return (min - pad)...(max + pad)
    }

    private var progressionSummary: String {
        guard let first = viewModel.progression.first,
              let last = viewModel.progression.last else { return "" }
        return "From \(ActiveSessionViewModel.weightString(first.bestWeightKg)) to \(ActiveSessionViewModel.weightString(last.bestWeightKg)) kilograms across \(viewModel.progression.count) sessions"
    }

    // MARK: - Weekly volume

    private var weeklyVolumeCard: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Text("Weekly Volume")
                .font(DesignSystem.Typography.headline)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            if viewModel.weeklyVolume.count >= 2 {
                Chart(viewModel.weeklyVolume) { point in
                    BarMark(
                        x: .value("Week", point.weekStart, unit: .weekOfYear),
                        y: .value("Volume", point.volumeKg)
                    )
                    .foregroundStyle(DesignSystem.Colors.accent)
                    .cornerRadius(4)
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
                .accessibilityLabel("Weekly training volume chart")
                .accessibilityValue(volumeSummary)
            } else {
                emptyState(
                    icon: "chart.bar",
                    message: "Log workouts across two weeks to see volume trends."
                )
            }
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
    }

    private var volumeSummary: String {
        let points = viewModel.weeklyVolume
        guard !points.isEmpty else { return "" }
        let average = points.map(\.volumeKg).reduce(0, +) / Double(points.count)
        return "Averaging \(Int(average.rounded())) kilograms per week over \(points.count) weeks"
    }

    // MARK: - Cardio

    private var cardioCard: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack {
                Text("Cardio")
                    .font(DesignSystem.Typography.headline)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Spacer()
                if let latest = viewModel.weeklyCardio.last {
                    Text("\(Int(latest.minutes.rounded())) min · \(Int(latest.calories.rounded())) kcal")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
            }

            if viewModel.weeklyCardio.count >= 2 {
                Chart(viewModel.weeklyCardio) { point in
                    BarMark(
                        x: .value("Week", point.weekStart, unit: .weekOfYear),
                        y: .value("Minutes", point.minutes)
                    )
                    .foregroundStyle(DesignSystem.Colors.positive)
                    .cornerRadius(4)
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
                .accessibilityLabel("Weekly cardio minutes chart")
                .accessibilityValue(cardioSummary)
            } else {
                emptyState(
                    icon: "figure.run",
                    message: "Log cardio across two weeks to see trends."
                )
            }
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
    }

    private var cardioSummary: String {
        let points = viewModel.weeklyCardio
        guard !points.isEmpty else { return "" }
        let average = points.map(\.minutes).reduce(0, +) / Double(points.count)
        return "Averaging \(Int(average.rounded())) minutes per week over \(points.count) weeks"
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
            StrengthProgressSection(viewModel: StrengthProgressViewModel())
        }
        .padding()
    }
    .background(DesignSystem.Colors.background)
}
