//
//  MeasurementHistoryView.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-26.
//

import SwiftUI
import SwiftData
import Charts

struct MeasurementHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    let viewModel: ProgressViewModel

    private var rowInsets: EdgeInsets {
        EdgeInsets(
            top: DesignSystem.Spacing.xs,
            leading: DesignSystem.Spacing.md,
            bottom: DesignSystem.Spacing.xs,
            trailing: DesignSystem.Spacing.md
        )
    }

    var body: some View {
        ZStack {
            DesignSystem.Colors.background
                .ignoresSafeArea()

            if viewModel.allMeasurementsDescending.isEmpty {
                emptyState
            } else {
                List {
                    if viewModel.waistPoints.count >= 2 {
                        waistChartCard
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(rowInsets)
                    }

                    ForEach(viewModel.allMeasurementsDescending, id: \.id) { measurement in
                        ZStack {
                            NavigationLink {
                                MeasurementDetailView(measurement: measurement, units: viewModel.unitSystem)
                            } label: {
                                EmptyView()
                            }
                            .opacity(0)

                            row(measurement)
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(rowInsets)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                viewModel.deleteMeasurement(measurement, in: modelContext)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Measurements")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Rows

    private func row(_ measurement: BodyMeasurement) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(measurement.date.formatted(.dateTime.day().month(.abbreviated).year()))
                    .font(DesignSystem.Typography.headline)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Text(MeasurementField.summary(for: measurement, units: viewModel.unitSystem))
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .lineLimit(2)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .accessibilityHidden(true)
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
    }

    // MARK: - Waist trend

    /// Waist samples in the user's display unit.
    private var displayWaistPoints: [MetricPoint] {
        let points = viewModel.waistPoints
        guard viewModel.unitSystem == .imperial else { return points }
        return points.map {
            MetricPoint(id: $0.id, date: $0.date, value: UnitConversion.inches(fromCm: $0.value))
        }
    }

    private var waistChartCard: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack {
                Text("Waist trend")
                    .font(DesignSystem.Typography.headline)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Spacer()
                if let latest = viewModel.waistPoints.last {
                    Text(UnitConversion.lengthText(cm: latest.value, units: viewModel.unitSystem))
                        .font(DesignSystem.Typography.headline)
                        .foregroundStyle(DesignSystem.Colors.accent)
                }
            }

            Chart(displayWaistPoints) { point in
                AreaMark(
                    x: .value("Date", point.date, unit: .day),
                    y: .value("Waist", point.value)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [DesignSystem.Colors.accent.opacity(0.3), .clear],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .interpolationMethod(.monotone)

                LineMark(
                    x: .value("Date", point.date, unit: .day),
                    y: .value("Waist", point.value)
                )
                .foregroundStyle(DesignSystem.Colors.accent)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .interpolationMethod(.monotone)
            }
            .chartYScale(domain: waistDomain)
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
            .accessibilityLabel("Waist trend chart")
            .accessibilityValue(waistChartSummary)
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large))
    }

    private var waistDomain: ClosedRange<Double> {
        let values = displayWaistPoints.map(\.value)
        guard let min = values.min(), let max = values.max() else { return 0...1 }
        let pad = Swift.max((max - min) * 0.15, 0.5)
        return (min - pad)...(max + pad)
    }

    private var waistChartSummary: String {
        guard let first = viewModel.waistPoints.first, let last = viewModel.waistPoints.last else { return "" }
        let units = viewModel.unitSystem
        let from = UnitConversion.lengthText(cm: first.value, units: units)
        let to = UnitConversion.lengthText(cm: last.value, units: units)
        return "From \(from) to \(to)"
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: "ruler")
                .font(.title)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .accessibilityHidden(true)
            Text("No measurements yet")
                .font(DesignSystem.Typography.headline)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
            Text("Log your first measurement from the Progress tab.")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
        }
        .padding(DesignSystem.Spacing.lg)
    }
}

#Preview {
    NavigationStack {
        MeasurementHistoryView(viewModel: ProgressViewModel())
    }
    .modelContainer(for: [BodyMeasurement.self, UserProfile.self, WeightEntry.self], inMemory: true)
}
