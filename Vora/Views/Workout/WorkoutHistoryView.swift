//
//  WorkoutHistoryView.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import SwiftUI
import SwiftData

struct WorkoutHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = WorkoutHistoryViewModel()
    @Query private var profiles: [UserProfile]
    @State private var pendingDeletion: HistoryDeletionPrompt?
    @State private var showingDeleteError = false

    private var rowInsets: EdgeInsets {
        EdgeInsets(
            top: DesignSystem.Spacing.xs,
            leading: DesignSystem.Spacing.lg,
            bottom: DesignSystem.Spacing.xs,
            trailing: DesignSystem.Spacing.lg
        )
    }

    var body: some View {
        ZStack {
            DesignSystem.Colors.background
                .ignoresSafeArea()

            if viewModel.items.isEmpty {
                VStack(spacing: DesignSystem.Spacing.sm) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.title)
                        .foregroundStyle(DesignSystem.Colors.textSecondary.opacity(0.5))
                        .accessibilityHidden(true)
                    Text("No workouts yet")
                        .font(DesignSystem.Typography.headline)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                    Text("Finished sessions and cardio will appear here.")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
            } else {
                List {
                    ForEach(viewModel.items) { item in
                        row(item)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(rowInsets)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    pendingDeletion = HistoryDeletionPrompt(item: item)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                .tint(DesignSystem.Colors.negative)
                            }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.load(from: modelContext)
        }
        .alert(
            pendingDeletion?.title ?? "",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            presenting: pendingDeletion
        ) { prompt in
            Button("Delete", role: .destructive) {
                confirmDeletion(prompt)
            }
            Button("Cancel", role: .cancel) {}
        } message: { prompt in
            Text(prompt.message)
        }
        .alert("Couldn't Delete", isPresented: $showingDeleteError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Nothing was removed. Please try again.")
        }
    }

    private func confirmDeletion(_ prompt: HistoryDeletionPrompt) {
        pendingDeletion = nil
        do {
            try viewModel.delete(prompt.item, context: modelContext)
        } catch {
            // The view model has logged it and restored the row.
            showingDeleteError = true
        }
    }

    @ViewBuilder
    private func row(_ item: HistoryItem) -> some View {
        switch item {
        case .lifting(let session):
            ZStack {
                NavigationLink {
                    WorkoutSessionDetailView(session: session) { deleted in
                        try viewModel.delete(deleted, context: modelContext)
                    }
                } label: {
                    EmptyView()
                }
                .opacity(0)

                liftingRow(session)
            }
        case .cardio(let entry):
            cardioRow(entry)
        }
    }

    private func liftingRow(_ session: WorkoutSession) -> some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            Image(systemName: "dumbbell.fill")
                .foregroundStyle(DesignSystem.Colors.accent)
                .frame(width: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.sessionName)
                    .font(DesignSystem.Typography.headline)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Text(session.date.formatted(.dateTime.weekday(.abbreviated).day().month()))
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(UnitConversion.volumeText(kg: session.totalVolumeKg, units: units))
                    .font(DesignSystem.Typography.headline)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Text("\(session.exercises.count) exercises · \(ActiveSessionView.timeString(session.durationSeconds))")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
    }

    private var units: UnitSystem {
        profiles.first?.preferredUnits ?? .metric
    }

    private func cardioRow(_ entry: CardioEntry) -> some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            Image(systemName: entry.type.iconName)
                .foregroundStyle(DesignSystem.Colors.macroCarbs)
                .frame(width: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.type.displayName)
                    .font(DesignSystem.Typography.headline)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Text(entry.statsLine)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Int(entry.estimatedCalories.rounded())) kcal")
                    .font(DesignSystem.Typography.headline)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Text(entry.date.formatted(.dateTime.weekday(.abbreviated).day().month()))
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
    }
}

#Preview {
    NavigationStack {
        WorkoutHistoryView()
    }
    .modelContainer(for: [WorkoutSession.self, CardioEntry.self], inMemory: true)
}
