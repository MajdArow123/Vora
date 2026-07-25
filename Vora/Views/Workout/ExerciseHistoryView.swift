//
//  ExerciseHistoryView.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-24.
//

import SwiftUI
import SwiftData
import Charts

struct ExerciseHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    let record: PersonalRecord

    @State private var entries: [ExerciseSessionStat] = []

    var body: some View {
        ZStack {
            DesignSystem.Colors.background
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: DesignSystem.Spacing.md) {
                    if entries.count >= 2 {
                        chartCard
                    }

                    ForEach(entries.reversed()) { entry in
                        sessionRow(entry)
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.lg)
                .padding(.vertical, DesignSystem.Spacing.md)
            }
        }
        .navigationTitle(record.exerciseName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            load()
        }
    }

    // MARK: - Chart

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text("Weight Progression")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .textCase(.uppercase)

            Chart(entries) { entry in
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
            .accessibilityLabel("Weight progression chart")
            .accessibilityValue(chartSummary)
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large))
    }

    private var weightDomain: ClosedRange<Double> {
        let weights = entries.map(\.bestWeightKg)
        guard let min = weights.min(), let max = weights.max() else { return 0...1 }
        let pad = Swift.max((max - min) * 0.15, 0.5)
        return (min - pad)...(max + pad)
    }

    private var chartSummary: String {
        guard let first = entries.first, let last = entries.last else { return "" }
        return "From \(ActiveSessionViewModel.weightString(first.bestWeightKg)) to \(ActiveSessionViewModel.weightString(last.bestWeightKg)) kilograms across \(entries.count) sessions"
    }

    // MARK: - Session rows

    private func sessionRow(_ entry: ExerciseSessionStat) -> some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.date.formatted(.dateTime.month(.abbreviated).day().year()))
                    .font(DesignSystem.Typography.headline)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Text("\(entry.completedSets) sets")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }

            Spacer()

            if entry.isPR {
                Image(systemName: "trophy.fill")
                    .font(.caption)
                    .foregroundStyle(DesignSystem.Colors.macroFat)
                    .accessibilityHidden(true)
            }

            Text("\(ActiveSessionViewModel.weightString(entry.bestWeightKg)) kg × \(entry.bestReps)")
                .font(DesignSystem.Typography.headline)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
        }
        .padding(DesignSystem.Spacing.md)
        .background(entry.isPR
                    ? DesignSystem.Colors.macroFat.opacity(0.15)
                    : DesignSystem.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.date.formatted(.dateTime.month(.wide).day().year()))
        .accessibilityValue(
            "Best set \(ActiveSessionViewModel.weightString(entry.bestWeightKg)) kilograms by \(entry.bestReps) reps, \(entry.completedSets) sets completed\(entry.isPR ? ", personal record" : "")"
        )
    }

    // MARK: - Data

    private func load() {
        let descriptor = FetchDescriptor<WorkoutSession>(sortBy: [SortDescriptor(\.date)])
        guard let sessions = try? modelContext.fetch(descriptor) else { return }

        var stats = StrengthProgression.sessionStats(for: record.exerciseName, sessions: sessions)

        if let prIndex = stats.firstIndex(where: {
            $0.bestWeightKg == record.weightKg && $0.bestReps == record.reps
        }) {
            stats[prIndex].isPR = true
        }
        entries = stats
    }
}

#Preview {
    NavigationStack {
        ExerciseHistoryView(record: PersonalRecord(
            exerciseName: "Bench Press",
            weightKg: 85,
            reps: 8,
            date: .now
        ))
    }
    .modelContainer(for: WorkoutSession.self, inMemory: true)
}
