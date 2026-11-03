//
//  PlateCalculatorSheet.swift
//  Vora
//
//  Created by Majd Arow on 2026-11-02.
//

import SwiftUI

/// Text for a per-side plate stack, shared by the set row and the sheet.
enum PlateStackText {
    /// "25 + 5", with repeats as "25 ×2 + 5"; "Bar only" for an empty stack.
    static func summary(_ stack: [PlateCount], units: UnitSystem) -> String {
        guard !stack.isEmpty else { return "Bar only" }
        return stack.map { plate in
            let weight = UnitConversion.weightNumberText(kg: plate.weightKg, units: units)
            return plate.countPerSide > 1 ? "\(weight) ×\(plate.countPerSide)" : weight
        }.joined(separator: " + ")
    }
}

/// Shows what to put on each side of the bar for a set's weight. Read-only:
/// it never changes the set.
struct PlateCalculatorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let totalKg: Double
    let equipment: EquipmentType
    let inventory: LoadingInventory
    let units: UnitSystem
    @Binding var selectedBarName: String?

    private var bars: [GymBar] { inventory.bars(for: equipment) }

    private var bar: GymBar? {
        bars.first { $0.name == selectedBarName }
            ?? LoadCalculator.preferredBar(forKg: totalKg, equipment: equipment, profile: inventory)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.Colors.background
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                        Text(UnitConversion.liftWeightText(kg: totalKg, units: units))
                            .font(DesignSystem.Typography.title)
                            .foregroundStyle(DesignSystem.Colors.textPrimary)

                        if let bar {
                            barPicker(selected: bar)
                            stackCard(bar: bar)
                        } else {
                            noBarsCard
                        }
                    }
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    .padding(.vertical, DesignSystem.Spacing.md)
                }
            }
            .navigationTitle("Plate Calculator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(DesignSystem.Typography.headline)
                        .foregroundStyle(DesignSystem.Colors.accent)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func barPicker(selected: GymBar) -> some View {
        Picker("Bar", selection: Binding(
            get: { selected.name },
            set: { selectedBarName = $0 }
        )) {
            ForEach(bars, id: \.self) { bar in
                Text("\(bar.name) (\(UnitConversion.liftWeightText(kg: bar.weightKg, units: units)))")
                    .tag(bar.name)
            }
        }
        .pickerStyle(.menu)
        .tint(DesignSystem.Colors.accent)
    }

    @ViewBuilder
    private func stackCard(bar: GymBar) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            if let stack = LoadCalculator.plateBreakdown(totalKg: totalKg, bar: bar, profile: inventory) {
                Text("Per side")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textPrimary.opacity(0.5))
                    .textCase(.uppercase)
                if stack.isEmpty {
                    Text("Bar only, no plates")
                        .font(DesignSystem.Typography.body)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                } else {
                    ForEach(stack, id: \.weightKg) { plate in
                        HStack {
                            Text(UnitConversion.liftWeightText(kg: plate.weightKg, units: units))
                                .font(DesignSystem.Typography.headline)
                                .foregroundStyle(DesignSystem.Colors.textPrimary)
                            Spacer()
                            Text("× \(plate.countPerSide)")
                                .font(DesignSystem.Typography.body)
                                .foregroundStyle(DesignSystem.Colors.textSecondary)
                        }
                        .frame(minHeight: 32)
                        .accessibilityElement(children: .combine)
                    }
                }
            } else {
                impossibleContent(bar: bar)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
    }

    @ViewBuilder
    private func impossibleContent(bar: GymBar) -> some View {
        Label("Nearest loadable weights", systemImage: "exclamationmark.triangle")
            .font(DesignSystem.Typography.headline)
            .foregroundStyle(DesignSystem.Colors.warning)

        let nearest = LoadCalculator.nearestLoads(aroundKg: totalKg, bar: bar, profile: inventory)
        if let below = nearest.below {
            nearbyRow(title: "Below", kg: below)
        }
        if let above = nearest.above {
            nearbyRow(title: "Above", kg: above)
        }
    }

    private func nearbyRow(title: String, kg: Double) -> some View {
        HStack {
            Text(title)
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
            Spacer()
            Text(UnitConversion.liftWeightText(kg: kg, units: units))
                .font(DesignSystem.Typography.headline)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
        }
        .accessibilityElement(children: .combine)
    }

    private var noBarsCard: some View {
        Text("This gym has no bars yet. Add them under Profile > My Gym.")
            .font(DesignSystem.Typography.body)
            .foregroundStyle(DesignSystem.Colors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DesignSystem.Spacing.md)
            .background(DesignSystem.Colors.card)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
    }
}

#Preview {
    PlateCalculatorSheet(
        totalKg: 102.5,
        equipment: .barbell,
        inventory: .standard(units: .metric),
        units: .metric,
        selectedBarName: .constant(nil)
    )
}
