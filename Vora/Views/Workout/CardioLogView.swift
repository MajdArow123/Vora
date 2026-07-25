//
//  CardioLogView.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import SwiftUI
import SwiftData

struct CardioLogView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = CardioLogViewModel()

    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.Colors.background
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                            Text("Activity")
                                .font(DesignSystem.Typography.caption)
                                .foregroundStyle(DesignSystem.Colors.textSecondary)
                                .textCase(.uppercase)

                            LazyVGrid(columns: columns, spacing: DesignSystem.Spacing.sm) {
                                ForEach(CardioType.loggableCases) { type in
                                    typeCard(type)
                                }
                            }
                        }

                        machineInputs

                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                            Text("Duration")
                                .font(DesignSystem.Typography.caption)
                                .foregroundStyle(DesignSystem.Colors.textSecondary)
                                .textCase(.uppercase)

                            Picker("Duration", selection: $viewModel.durationMinutes) {
                                ForEach(Array(stride(from: 5, through: 180, by: 5)), id: \.self) { minutes in
                                    Text("\(minutes) min").tag(minutes)
                                }
                            }
                            .pickerStyle(.wheel)
                            .frame(height: 110)
                            .clipped()
                            .background(DesignSystem.Colors.card)
                            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
                        }

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Estimated burn")
                                    .font(DesignSystem.Typography.caption)
                                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                                Text("≈ \(Int(viewModel.estimatedCalories.rounded())) kcal")
                                    .font(DesignSystem.Typography.title)
                                    .foregroundStyle(DesignSystem.Colors.accent)
                                    .contentTransition(.numericText())
                            }
                            Spacer()
                            Image(systemName: "flame.fill")
                                .font(.title2)
                                .foregroundStyle(DesignSystem.Colors.macroFat)
                                .accessibilityHidden(true)
                        }
                        .padding(DesignSystem.Spacing.md)
                        .background(DesignSystem.Colors.card)
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
                        .animation(.easeInOut(duration: 0.2), value: viewModel.estimatedCalories)

                        PrimaryButton(title: "Log Cardio") {
                            viewModel.save(in: modelContext)
                            dismiss()
                        }
                    }
                    .padding(DesignSystem.Spacing.lg)
                    .animation(.easeInOut(duration: 0.2), value: viewModel.type)
                }
            }
            .navigationTitle("Log Cardio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
            }
        }
        .onAppear {
            viewModel.load(from: modelContext)
        }
    }

    // MARK: - Activity picker

    private func typeCard(_ type: CardioType) -> some View {
        let isSelected = viewModel.type == type
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                viewModel.select(type)
            }
        } label: {
            VStack(spacing: DesignSystem.Spacing.xs) {
                Image(systemName: type.iconName)
                    .font(.title3)
                    .foregroundStyle(isSelected ? .white : DesignSystem.Colors.accent)
                    .accessibilityHidden(true)
                Text(type.displayName)
                    .font(DesignSystem.Typography.caption)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                    .lineLimit(2, reservesSpace: true)
                    .foregroundStyle(isSelected ? .white : DesignSystem.Colors.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DesignSystem.Spacing.md)
            .background(isSelected ? DesignSystem.Colors.accent : DesignSystem.Colors.card)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Machine inputs

    @ViewBuilder
    private var machineInputs: some View {
        switch viewModel.type {
        case .treadmill:
            speedRow(range: CardioCalculator.treadmillSpeedRange, step: 0.5)
            inclineRow
        case .stairClimber:
            CardioSliderRow(
                title: "Steps per minute",
                value: intBinding($viewModel.stepsPerMinute),
                range: doubleRange(CardioCalculator.stepsPerMinuteRange),
                step: 5,
                unit: "spm"
            )
        case .elliptical:
            resistanceRow
        case .stationaryBike:
            resistanceRow
            CardioSliderRow(
                title: "Cadence",
                value: intBinding($viewModel.rpm),
                range: doubleRange(CardioCalculator.rpmRange),
                step: 5,
                unit: "rpm"
            )
        case .row:
            CardioSliderRow(
                title: "Stroke rate",
                value: intBinding($viewModel.strokesPerMinute),
                range: doubleRange(CardioCalculator.strokeRateRange),
                step: 1,
                unit: "spm"
            )
        case .run:
            runInputs
        case .cycle:
            speedRow(range: CardioCalculator.cyclingSpeedRange, step: 0.5)
        case .walk:
            speedRow(range: CardioCalculator.walkingSpeedRange, step: 0.25)
            inclineRow
        case .swim, .other:
            EmptyView()
        }
    }

    @ViewBuilder
    private var runInputs: some View {
        Picker("Input mode", selection: $viewModel.paceInputSelected) {
            Text("Speed").tag(false)
            Text("Pace").tag(true)
        }
        .pickerStyle(.segmented)

        if viewModel.paceInputSelected {
            CardioSliderRow(
                title: "Pace",
                value: $viewModel.paceMinPerKm,
                range: CardioCalculator.paceRange,
                step: 0.25,
                unit: "min/km",
                valueLabel: { Self.paceLabel($0) }
            )
        } else {
            speedRow(range: CardioCalculator.runningSpeedRange, step: 0.5)
        }

        if let distance = viewModel.distanceKm {
            Text("Distance ≈ \(distance.formatted(.number.precision(.fractionLength(0...1)))) km")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.2), value: distance)
        }
    }

    private func speedRow(range: ClosedRange<Double>, step: Double) -> some View {
        CardioSliderRow(
            title: "Speed",
            value: $viewModel.speedKmh,
            range: range,
            step: step,
            unit: "km/h",
            fractionDigits: 1
        )
    }

    private var inclineRow: some View {
        CardioSliderRow(
            title: "Incline",
            value: $viewModel.inclinePercent,
            range: CardioCalculator.inclineRange,
            step: 1,
            unit: "%"
        )
    }

    private var resistanceRow: some View {
        CardioSliderRow(
            title: "Resistance",
            value: intBinding($viewModel.resistanceLevel),
            range: doubleRange(CardioCalculator.resistanceRange),
            step: 1,
            unit: "",
            valueLabel: { "Level \(Int($0.rounded()))" }
        )
    }

    // MARK: - Helpers

    /// "6:30 min/km" from fractional minutes per kilometre.
    private static func paceLabel(_ pace: Double) -> String {
        let totalSeconds = Int((pace * 60).rounded())
        return String(format: "%d:%02d min/km", totalSeconds / 60, totalSeconds % 60)
    }

    private func intBinding(_ source: Binding<Int>) -> Binding<Double> {
        Binding(
            get: { Double(source.wrappedValue) },
            set: { source.wrappedValue = Int($0.rounded()) }
        )
    }

    private func doubleRange(_ range: ClosedRange<Int>) -> ClosedRange<Double> {
        Double(range.lowerBound)...Double(range.upperBound)
    }
}

#Preview {
    CardioLogView()
        .modelContainer(for: [CardioEntry.self, WeightEntry.self], inMemory: true)
}
