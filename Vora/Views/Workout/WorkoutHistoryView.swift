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
                ScrollView {
                    LazyVStack(spacing: DesignSystem.Spacing.sm) {
                        ForEach(viewModel.items) { item in
                            switch item {
                            case .lifting(let session):
                                NavigationLink {
                                    WorkoutSessionDetailView(session: session)
                                } label: {
                                    liftingRow(session)
                                }
                                .buttonStyle(.plain)
                            case .cardio(let entry):
                                cardioRow(entry)
                            }
                        }
                    }
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    .padding(.vertical, DesignSystem.Spacing.md)
                }
            }
        }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.load(from: modelContext)
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
                Text("\(Int(session.totalVolumeKg.rounded())) kg")
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
