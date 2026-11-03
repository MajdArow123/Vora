//
//  LogWeightSheet.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-26.
//

import SwiftUI
import SwiftData
import OSLog

/// Compact weigh-in sheet shared by the Progress tab and the Home
/// quick-action. Always logs against today and pre-fills the most
/// recent weigh-in so a stable weight is a two-tap log.
struct LogWeightSheet: View {
    private static let logger = Logger(subsystem: "com.majdarow.Vora", category: "LogWeight")

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var units: UnitSystem = .metric
    @State private var weight = WeightField(kg: nil, units: .metric)
    @State private var saveFailed = false
    @State private var bodyFatText = ""
    @FocusState private var focused: Bool

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
                        TextField("0.0", text: $weight.text)
                            .keyboardType(.decimalPad)
                            .focused($focused)
                            .accessibilityLabel("Weight in \(UnitConversion.spokenWeightUnit(units))")
                            .font(.system(size: 44, weight: .bold))
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 160)
                        Text(UnitConversion.weightUnitSymbol(units))
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
                        log()
                    }
                    .disabled(weight.bodyWeightKg == nil || !bodyFatIsValid)
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
                prefill()
                focused = true
            }
            .alert("Couldn't save your weight", isPresented: $saveFailed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Please try again.")
            }
        }
    }

    private func log() {
        guard let kg = weight.bodyWeightKg else { return }
        modelContext.insert(WeightEntry(date: .now, weightKg: kg, bodyFatPercent: parsedBodyFat))
        do {
            try modelContext.save()
            dismiss()
        } catch {
            Self.logger.error("Failed to save weigh-in: \(String(describing: error), privacy: .public)")
            modelContext.rollback()
            saveFailed = true
        }
    }

    /// Takes the unit from the profile and the most recent weigh-in, whose
    /// exact kg is kept while its text stays untouched.
    private func prefill() {
        guard weight.text.isEmpty else { return }
        var descriptor = FetchDescriptor<WeightEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 1
        do {
            units = try modelContext.fetch(FetchDescriptor<UserProfile>()).first?.preferredUnits ?? .metric
            weight = WeightField(kg: try modelContext.fetch(descriptor).first?.weightKg, units: units)
        } catch {
            Self.logger.error("Failed to prefill weigh-in: \(String(describing: error), privacy: .public)")
        }
    }
}

#Preview {
    LogWeightSheet()
        .modelContainer(for: WeightEntry.self, inMemory: true)
}
