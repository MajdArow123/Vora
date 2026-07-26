//
//  LogWeightSheet.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-26.
//

import SwiftUI
import SwiftData

/// Compact weigh-in sheet shared by the Progress tab and the Home
/// quick-action. Always logs against today and pre-fills the most
/// recent weigh-in so a stable weight is a two-tap log.
struct LogWeightSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var weightText = ""
    @State private var bodyFatText = ""
    @FocusState private var focused: Bool

    private var parsedKg: Double? {
        guard let value = Double(weightText.replacingOccurrences(of: ",", with: ".")),
              (20...400).contains(value) else { return nil }
        return value
    }

    /// nil when the optional field is empty, unparseable, or out of range.
    private var parsedBodyFat: Double? {
        guard let value = Double(bodyFatText.replacingOccurrences(of: ",", with: ".")),
              (2...80).contains(value) else { return nil }
        return value
    }

    private var bodyFatIsValid: Bool {
        bodyFatText.trimmingCharacters(in: .whitespaces).isEmpty || parsedBodyFat != nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.Colors.background
                    .ignoresSafeArea()

                VStack(spacing: DesignSystem.Spacing.lg) {
                    Text(Date.now.formatted(.dateTime.weekday(.wide).day().month()))
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)

                    HStack {
                        TextField("0.0", text: $weightText)
                            .keyboardType(.decimalPad)
                            .focused($focused)
                            .accessibilityLabel("Weight in kilograms")
                            .font(.system(size: 44, weight: .bold))
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 160)
                        Text("kg")
                            .font(DesignSystem.Typography.title)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                    }

                    HStack(spacing: DesignSystem.Spacing.sm) {
                        Text("Body fat %")
                            .font(DesignSystem.Typography.body)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                        Spacer()
                        TextField("Optional", text: $bodyFatText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 100)
                            .font(DesignSystem.Typography.body)
                            .foregroundStyle(
                                bodyFatIsValid
                                    ? DesignSystem.Colors.textPrimary
                                    : DesignSystem.Colors.negative
                            )
                            .accessibilityLabel("Body fat percentage, optional")
                        Text("%")
                            .font(DesignSystem.Typography.body)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                    }
                    .padding(.horizontal, DesignSystem.Spacing.lg)

                    PrimaryButton(title: "Log") {
                        guard let kg = parsedKg else { return }
                        modelContext.insert(WeightEntry(date: .now, weightKg: kg, bodyFatPercent: parsedBodyFat))
                        try? modelContext.save()
                        dismiss()
                    }
                    .disabled(parsedKg == nil || !bodyFatIsValid)
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                }
                .padding(.top, DesignSystem.Spacing.lg)
            }
            .navigationTitle("Log Weight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
            }
            .onAppear {
                prefillLastWeight()
                focused = true
            }
        }
    }

    private func prefillLastWeight() {
        guard weightText.isEmpty else { return }
        var descriptor = FetchDescriptor<WeightEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 1
        guard let last = (try? modelContext.fetch(descriptor))?.first else { return }
        weightText = String(format: "%.1f", last.weightKg)
    }
}

#Preview {
    LogWeightSheet()
        .modelContainer(for: WeightEntry.self, inMemory: true)
}
