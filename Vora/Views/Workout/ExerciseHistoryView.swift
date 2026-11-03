//
//  ExerciseHistoryView.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-24.
//

import Charts
import OSLog
import SwiftData
import SwiftUI

struct ExerciseHistoryView: View {
    private static let logger = Logger(subsystem: "com.majdarow.Vora", category: "Workout")

    @Environment(\.modelContext) private var modelContext
    let record: PersonalRecord
    @Query private var profiles: [UserProfile]

    @State private var entries: [ExerciseSessionStat] = []

    private var units: UnitSystem {
        profiles.first?.preferredUnits ?? .metric
    }

    var body: some View {
        ZStack {
            DesignSystem.Colors.background
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: DesignSystem.Spacing.md) {
                    recordsCard

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

    // MARK: - Records

    private var records: ExerciseRecords {
        StrengthProgression.records(from: entries.flatMap(\.sets).filter(\.setType.countsTowardRecords).map {
            RecordSet(weightKg: $0.weightKg, reps: $0.reps)
        })
    }

    @ViewBuilder
    private var recordsCard: some View {
        let records = records
        if let heaviest = records.heaviest {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                Text("Records")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .textCase(.uppercase)

                recordLine("Heaviest", "\(UnitConversion.liftWeightText(kg: heaviest.weightKg, units: units)) × \(heaviest.reps)")
                if let best = records.bestE1RMKg {
                    recordLine("Est. 1RM", UnitConversion.liftWeightText(kg: best, units: units))
                }
                ForEach(records.repBests.prefix(Self.visibleRepBests)) { best in
                    recordLine("Most reps at \(UnitConversion.liftWeightText(kg: best.weightKg, units: units))", "\(best.reps)")
                }
            }
            .padding(DesignSystem.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DesignSystem.Colors.card)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
        }
    }

    private static let visibleRepBests = 5

    private func recordLine(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
            Spacer()
            Text(value)
                .font(DesignSystem.Typography.headline)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
        }
        .accessibilityElement(children: .combine)
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
                    y: .value("Weight", UnitConversion.displayWeight(kg: entry.bestWeightKg, units: units))
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
                    y: .value("Weight", UnitConversion.displayWeight(kg: entry.bestWeightKg, units: units))
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
        let weights = entries.map { UnitConversion.displayWeight(kg: $0.bestWeightKg, units: units) }
        guard let min = weights.min(), let max = weights.max() else { return 0...1 }
        let pad = Swift.max((max - min) * 0.15, 0.5)
        return (min - pad)...(max + pad)
    }

    private var chartSummary: String {
        guard let first = entries.first, let last = entries.last else { return "" }
        return "From \(UnitConversion.weightNumberText(kg: first.bestWeightKg, units: units)) to \(UnitConversion.weightNumberText(kg: last.bestWeightKg, units: units)) \(UnitConversion.spokenWeightUnit(units)) across \(entries.count) sessions"
    }

    // MARK: - Session rows

    private func sessionRow(_ entry: ExerciseSessionStat) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            HStack(spacing: DesignSystem.Spacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.date.formatted(.dateTime.month(.abbreviated).day().year()))
                        .font(DesignSystem.Typography.headline)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                    Text(entry.setsSummary)
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
            }

            VStack(spacing: 2) {
                let labels = SetCounting.labels(entry.sets.map(\.setType))
                ForEach(Array(entry.sets.enumerated()), id: \.element.id) { index, set in
                    setRow(set, label: labels[index])
                }
            }
        }
        .padding(DesignSystem.Spacing.md)
        .background(entry.isPR
                    ? DesignSystem.Colors.macroFat.opacity(0.15)
                    : DesignSystem.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.date.formatted(.dateTime.month(.wide).day().year()))
        .accessibilityValue(
            "\(entry.spokenSetsSummary), best \(UnitConversion.weightNumberText(kg: entry.bestWeightKg, units: units)) \(UnitConversion.spokenWeightUnit(units))\(entry.isPR ? ", personal record" : "")\(Self.spokenRIR(entry.sets))"
        )
    }

    /// "Set 2", or the type's name for other types, with the side's letter.
    private func setCaption(_ set: SetDetail, label: String) -> String {
        let name = set.setType == .normal ? "Set \(label)" : set.setType.displayName
        return set.side.map { "\(name) \($0.badge)" } ?? name
    }

    /// Only the sets with RIR logged, e.g. ", set 1 2 reps in reserve".
    private static func spokenRIR(_ sets: [SetDetail]) -> String {
        sets.compactMap { set in
            set.rir.map { ", set \(set.setNumber) \(RIRScale.spokenText($0))" }
        }.joined()
    }

    private func setRow(_ set: SetDetail, label: String) -> some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            Text(setCaption(set, label: label))
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(set.setType.tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: 52, alignment: .leading)

            Text(UnitConversion.liftWeightText(kg: set.weightKg, units: units))
                .font(DesignSystem.Typography.headline)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            Text("× \(set.reps)")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)

            Spacer()

            if let rir = set.rir {
                Text("RIR \(RIRScale.text(rir))")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Data

    private func load() {
        let sessions: [WorkoutSession]
        do {
            sessions = try modelContext.fetch(ExerciseIdentity.candidateSessions(exerciseId: record.exerciseId))
        } catch {
            Self.logger.error("Failed to load exercise history: \(String(describing: error), privacy: .public)")
            return
        }

        var stats = StrengthProgression.sessionStats(forKey: record.id, sessions: sessions)

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
