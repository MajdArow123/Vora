//
//  SupplementManagementView.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-26.
//

import SwiftUI
import SwiftData

/// Manages the supplement list: reorder via Edit, swipe to delete, tap a
/// row to edit, plus to add. Deleting is a soft delete that keeps history.
struct SupplementManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = SupplementListViewModel()
    @State private var editingSupplement: Supplement?
    @State private var showingAdd = false

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.Colors.background
                    .ignoresSafeArea()

                List {
                    if viewModel.supplements.isEmpty {
                        Text("No supplements yet. Tap + to add your first one.")
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, DesignSystem.Spacing.sm)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }

                    ForEach(viewModel.supplements) { supplement in
                        Button {
                            editingSupplement = supplement
                        } label: {
                            row(supplement)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(rowInsets)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                viewModel.deactivate(supplement, context: modelContext)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    .onMove { viewModel.move(from: $0, to: $1, context: modelContext) }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Supplements")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: DesignSystem.Spacing.xs) {
                        if viewModel.supplements.count > 1 {
                            EditButton()
                                .foregroundStyle(DesignSystem.Colors.accent)
                        }
                        Button {
                            showingAdd = true
                        } label: {
                            Image(systemName: "plus")
                                .foregroundStyle(DesignSystem.Colors.accent)
                        }
                        .accessibilityLabel("Add supplement")
                    }
                }
            }
        }
        .onAppear {
            viewModel.load(from: modelContext)
        }
        .sheet(item: $editingSupplement, onDismiss: {
            viewModel.load(from: modelContext)
        }) { supplement in
            SupplementEditView(supplement: supplement)
        }
        .sheet(isPresented: $showingAdd, onDismiss: {
            viewModel.load(from: modelContext)
        }) {
            SupplementEditView(supplement: nil)
        }
    }

    private var rowInsets: EdgeInsets {
        EdgeInsets(
            top: DesignSystem.Spacing.xs,
            leading: DesignSystem.Spacing.lg,
            bottom: DesignSystem.Spacing.xs,
            trailing: DesignSystem.Spacing.lg
        )
    }

    private func row(_ supplement: Supplement) -> some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            VStack(alignment: .leading, spacing: 4) {
                Text(supplement.name)
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                HStack(spacing: DesignSystem.Spacing.sm) {
                    Text(supplement.dose)
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)

                    Text(supplement.timing.displayName)
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.accent)
                        .padding(.horizontal, DesignSystem.Spacing.sm)
                        .padding(.vertical, 2)
                        .background(DesignSystem.Colors.accent.opacity(0.12))
                        .clipShape(Capsule())

                    if supplement.reminderEnabled {
                        HStack(spacing: 2) {
                            Image(systemName: "clock")
                                .font(.caption2)
                            Text(reminderTimeText(supplement.reminderMinutes))
                                .font(DesignSystem.Typography.caption)
                        }
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                    }
                }
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
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(supplement.name)
        .accessibilityValue(
            "\(supplement.dose), \(supplement.timing.displayName)"
            + (supplement.reminderEnabled ? ", reminder at \(reminderTimeText(supplement.reminderMinutes))" : "")
        )
        .accessibilityHint("Tap to edit")
    }

    private func reminderTimeText(_ minutes: Int) -> String {
        let date = Calendar.current.date(
            bySettingHour: minutes / 60,
            minute: minutes % 60,
            second: 0,
            of: .now
        ) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }
}

#Preview {
    SupplementManagementView()
        .modelContainer(for: [Supplement.self, SupplementLog.self], inMemory: true)
}
