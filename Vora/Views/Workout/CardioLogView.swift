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
                                ForEach(CardioType.allCases) { type in
                                    typeCard(type)
                                }
                            }
                        }

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
                                Text("\(Int(viewModel.estimatedCalories.rounded())) kcal")
                                    .font(DesignSystem.Typography.title)
                                    .foregroundStyle(DesignSystem.Colors.textPrimary)
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

    private func typeCard(_ type: CardioType) -> some View {
        let isSelected = viewModel.type == type
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                viewModel.type = type
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
}

#Preview {
    CardioLogView()
        .modelContainer(for: [CardioEntry.self, WeightEntry.self], inMemory: true)
}
