//
//  MeasurementDetailView.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-26.
//

import SwiftUI
import SwiftData

struct MeasurementDetailView: View {
    let measurement: BodyMeasurement
    let units: UnitSystem

    private var recorded: [(field: MeasurementField, value: Double)] {
        MeasurementField.recordedValues(measurement)
    }

    var body: some View {
        ZStack {
            DesignSystem.Colors.background
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                    valuesCard

                    if let notes = measurement.notes, !notes.isEmpty {
                        notesCard(notes)
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.md)
                .padding(.bottom, DesignSystem.Spacing.xl)
            }
        }
        .navigationTitle(measurement.date.formatted(.dateTime.day().month(.abbreviated).year()))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var valuesCard: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            ForEach(recorded, id: \.field) { item in
                HStack {
                    Text(item.field.label)
                        .font(DesignSystem.Typography.body)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                    Spacer()
                    Text(item.field.displayText(item.value, units: units))
                        .font(DesignSystem.Typography.body)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                }
                if item.field != recorded.last?.field {
                    Divider()
                }
            }
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
    }

    private func notesCard(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text("Notes")
                .font(DesignSystem.Typography.headline)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
            Text(notes)
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
    }
}

#Preview {
    NavigationStack {
        MeasurementDetailView(
            measurement: BodyMeasurement(date: .now, waistCm: 82.5, chestCm: 101.2, bodyFatPercent: 14.2, notes: "Morning, before breakfast."),
            units: .metric
        )
    }
    .modelContainer(for: [BodyMeasurement.self], inMemory: true)
}
