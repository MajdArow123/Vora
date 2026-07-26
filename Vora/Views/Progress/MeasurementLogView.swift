//
//  MeasurementLogView.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-26.
//

import SwiftUI
import SwiftData

struct MeasurementLogView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = MeasurementLogViewModel()
    @State private var expandedField: MeasurementField?
    @FocusState private var focusedField: MeasurementField?

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.Colors.background
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                        InfoCallout(text: MeasurementField.generalTip)

                        fieldsCard

                        notesCard

                        PrimaryButton(title: "Save Measurements") {
                            viewModel.save(in: modelContext)
                            dismiss()
                        }
                        .disabled(!viewModel.canSave)
                    }
                    .padding(DesignSystem.Spacing.lg)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Log Measurements")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
            }
        }
        .onAppear {
            viewModel.load(from: modelContext)
        }
    }

    // MARK: - Fields

    private var fieldsCard: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            ForEach(MeasurementField.allCases) { field in
                fieldRow(field)

                if expandedField == field {
                    InfoCallout(text: field.instruction)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if field != MeasurementField.allCases.last {
                    Divider()
                }
            }
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
    }

    private func fieldRow(_ field: MeasurementField) -> some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Text(field.label)
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expandedField = expandedField == field ? nil : field
                }
            } label: {
                Image(systemName: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(DesignSystem.Colors.accent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("How to measure \(field.label.lowercased())")

            Spacer()

            TextField("—", text: binding(for: field))
                .keyboardType(.decimalPad)
                .focused($focusedField, equals: field)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
                .font(DesignSystem.Typography.body)
                .foregroundStyle(
                    viewModel.fieldIsInvalid(field)
                        ? DesignSystem.Colors.negative
                        : DesignSystem.Colors.textPrimary
                )
                .accessibilityLabel("\(field.label) in \(field.unitLabel(for: viewModel.units))")

            Text(field.unitLabel(for: viewModel.units))
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .frame(minWidth: 22, alignment: .leading)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Notes

    private var notesCard: some View {
        TextField("Notes (optional)", text: $viewModel.notes, axis: .vertical)
            .lineLimit(1...4)
            .font(DesignSystem.Typography.body)
            .foregroundStyle(DesignSystem.Colors.textPrimary)
            .padding(DesignSystem.Spacing.md)
            .background(DesignSystem.Colors.card)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
    }

    private func binding(for field: MeasurementField) -> Binding<String> {
        Binding(
            get: { viewModel.texts[field] ?? "" },
            set: { viewModel.texts[field] = $0 }
        )
    }
}

#Preview {
    MeasurementLogView()
        .modelContainer(for: [BodyMeasurement.self, UserProfile.self], inMemory: true)
}
