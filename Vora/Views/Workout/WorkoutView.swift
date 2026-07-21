//
//  WorkoutView.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import SwiftUI
import SwiftData

struct WorkoutView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = WorkoutHomeViewModel()
    @State private var showingSession = false
    @State private var showingCardio = false
    @State private var showingSplitBuilder = false

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.Colors.background
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                        Text("Train")
                            .font(DesignSystem.Typography.screenTitle)
                            .foregroundStyle(DesignSystem.Colors.textPrimary)

                        todayCard
                        weekStrip
                        personalRecordsCard
                        actionsRow
                    }
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    .padding(.vertical, DesignSystem.Spacing.md)
                }
            }
            .navigationBarHidden(true)
        }
        .onAppear {
            viewModel.load(from: modelContext)
        }
        .fullScreenCover(isPresented: $showingSession, onDismiss: {
            viewModel.load(from: modelContext)
        }) {
            ActiveSessionView(sessionName: viewModel.todaySplitDay.map {
                $0.isRest ? "Extra Session" : $0.title
            } ?? "Session")
        }
        .sheet(isPresented: $showingCardio, onDismiss: {
            viewModel.load(from: modelContext)
        }) {
            CardioLogView()
        }
        .sheet(isPresented: $showingSplitBuilder, onDismiss: {
            viewModel.load(from: modelContext)
        }) {
            SplitBuilderView()
        }
    }

    // MARK: - Today card

    @ViewBuilder
    private var todayCard: some View {
        let day = viewModel.todaySplitDay
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Today")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .textCase(.uppercase)
                    Text(day?.isRest == false ? (day?.title ?? "Session") : "Rest Day")
                        .font(DesignSystem.Typography.title)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                }
                Spacer()
                if viewModel.hasTrainedToday {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Done")
                    }
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.accent)
                }
            }

            if let day, !day.isRest, !day.muscleGroups.isEmpty {
                muscleChips(day.muscleGroups)
            }

            PrimaryButton(
                title: day?.isRest == false ? "Start Session" : "Start Session Anyway"
            ) {
                showingSession = true
            }
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large))
    }

    private func muscleChips(_ groups: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DesignSystem.Spacing.xs) {
                ForEach(groups, id: \.self) { group in
                    Text(MuscleGroup(rawValue: group)?.displayName ?? group.capitalized)
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.accent)
                        .padding(.horizontal, DesignSystem.Spacing.sm)
                        .padding(.vertical, 4)
                        .background(DesignSystem.Colors.accent.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
        }
    }

    // MARK: - Week strip

    private var weekStrip: some View {
        HStack(spacing: 0) {
            ForEach(viewModel.splitDays) { day in
                let state = viewModel.state(for: day)
                VStack(spacing: DesignSystem.Spacing.xs) {
                    Text(SplitDay.dayNames[day.dayIndex])
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(state == .today
                                         ? DesignSystem.Colors.accent
                                         : DesignSystem.Colors.textSecondary)

                    ZStack {
                        Circle()
                            .fill(fillColor(for: state))
                        if state == .today {
                            Circle()
                                .strokeBorder(DesignSystem.Colors.accent, lineWidth: 2)
                        }
                        icon(for: state)
                    }
                    .frame(width: 34, height: 34)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
    }

    private func fillColor(for state: SplitDayState) -> Color {
        switch state {
        case .done: DesignSystem.Colors.accent
        case .today: DesignSystem.Colors.accent.opacity(0.1)
        case .upcoming: DesignSystem.Colors.background
        case .missed: DesignSystem.Colors.background
        case .rest: DesignSystem.Colors.background.opacity(0.5)
        }
    }

    @ViewBuilder
    private func icon(for state: SplitDayState) -> some View {
        switch state {
        case .done:
            Image(systemName: "checkmark")
                .font(.caption.bold())
                .foregroundStyle(.white)
        case .rest:
            Image(systemName: "moon.zzz")
                .font(.caption2)
                .foregroundStyle(DesignSystem.Colors.textSecondary.opacity(0.5))
        case .missed:
            Image(systemName: "minus")
                .font(.caption2)
                .foregroundStyle(DesignSystem.Colors.textSecondary.opacity(0.5))
        case .today, .upcoming:
            EmptyView()
        }
    }

    // MARK: - Personal records

    private var personalRecordsCard: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text("Personal Records")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .textCase(.uppercase)

            VStack(spacing: DesignSystem.Spacing.sm) {
                if viewModel.personalRecords.isEmpty {
                    Text("Records appear after your first logged session.")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, DesignSystem.Spacing.sm)
                } else {
                    ForEach(viewModel.personalRecords) { record in
                        HStack {
                            Image(systemName: "trophy.fill")
                                .font(.caption)
                                .foregroundStyle(DesignSystem.Colors.macroFat)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(record.exerciseName)
                                    .font(DesignSystem.Typography.body)
                                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                                    .lineLimit(1)
                                Text("Est. 1RM \(Int(record.estimatedOneRepMax.rounded())) kg")
                                    .font(DesignSystem.Typography.caption)
                                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                            }
                            Spacer()
                            Text("\(ActiveSessionViewModel.weightString(record.weightKg)) kg × \(record.reps)")
                                .font(DesignSystem.Typography.headline)
                                .foregroundStyle(DesignSystem.Colors.textPrimary)
                        }
                        if record.id != viewModel.personalRecords.last?.id {
                            Divider()
                        }
                    }
                }
            }
            .padding(DesignSystem.Spacing.md)
            .background(DesignSystem.Colors.card)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
        }
    }

    // MARK: - Actions

    private var actionsRow: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            actionButton("Cardio", icon: "heart.fill") { showingCardio = true }
            NavigationLink {
                WorkoutHistoryView()
            } label: {
                actionLabel("History", icon: "clock.arrow.circlepath")
            }
            .buttonStyle(.plain)
            actionButton("Edit Split", icon: "calendar") { showingSplitBuilder = true }
        }
    }

    private func actionButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            actionLabel(title, icon: icon)
        }
        .buttonStyle(.plain)
    }

    private func actionLabel(_ title: String, icon: String) -> some View {
        VStack(spacing: DesignSystem.Spacing.xs) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(DesignSystem.Colors.accent)
            Text(title)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
    }
}

#Preview {
    WorkoutView()
        .modelContainer(
            for: [UserProfile.self, WorkoutSession.self, SplitDay.self, CardioEntry.self],
            inMemory: true
        )
}
