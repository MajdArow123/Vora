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
    @State private var showingTemplateEditor = false

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
            ActiveSessionView(
                sessionName: viewModel.todaySplitDay.map {
                    $0.isRest ? "Extra Session" : $0.title
                } ?? "Session",
                templateExercises: viewModel.todaySplitDay?.isRest == false
                    ? WorkoutTemplateStore.template(
                        for: viewModel.trainingSplit,
                        dayIndex: viewModel.todayIndex
                    )
                    : []
            )
        }
        .sheet(isPresented: $showingTemplateEditor) {
            TemplateEditorView(
                split: viewModel.trainingSplit,
                dayIndex: viewModel.todayIndex,
                dayTitle: viewModel.todaySplitDay?.title ?? "Today"
            )
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
                            .accessibilityHidden(true)
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

            if day?.isRest == false {
                Button {
                    showingTemplateEditor = true
                } label: {
                    HStack(spacing: DesignSystem.Spacing.xs) {
                        Image(systemName: "square.and.pencil")
                            .accessibilityHidden(true)
                        Text("Edit Template")
                    }
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.accent)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
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
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityLabel(for: day, state: state))
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

    private func accessibilityLabel(for day: SplitDay, state: SplitDayState) -> String {
        let fullDayNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        let name = fullDayNames[day.dayIndex]
        if day.isRest {
            return "\(name), rest day"
        }
        let status = switch state {
        case .done: "completed"
        case .today: "today"
        case .upcoming: "upcoming"
        case .missed: "missed"
        case .rest: "rest day"
        }
        return "\(name), \(day.title), \(status)"
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

            if viewModel.personalRecords.isEmpty {
                Text("Records appear after your first logged session.")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(DesignSystem.Spacing.md)
                    .background(DesignSystem.Colors.card)
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
            } else {
                VStack(spacing: DesignSystem.Spacing.sm) {
                    ForEach(viewModel.personalRecords) { record in
                        NavigationLink {
                            ExerciseHistoryView(record: record)
                        } label: {
                            personalRecordCard(record)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func personalRecordCard(_ record: PersonalRecord) -> some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            Image(systemName: "trophy.fill")
                .font(.subheadline)
                .foregroundStyle(DesignSystem.Colors.accent)
                .frame(width: 36, height: 36)
                .background(DesignSystem.Colors.accent.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(record.exerciseName)
                    .font(DesignSystem.Typography.headline)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                    .lineLimit(1)
                Text("Est. 1RM \(ActiveSessionViewModel.weightString(record.estimatedOneRepMax)) kg")
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                Text(record.date.formatted(.dateTime.month(.abbreviated).day().year()))
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }

            Spacer()

            HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.xs) {
                Text("\(ActiveSessionViewModel.weightString(record.weightKg)) kg")
                    .font(DesignSystem.Typography.title)
                    .foregroundStyle(DesignSystem.Colors.accent)
                Text("× \(record.reps)")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(DesignSystem.Colors.accent)
                .frame(width: 3)
                .padding(.vertical, DesignSystem.Spacing.sm)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(record.exerciseName)
        .accessibilityValue(
            "Personal record \(ActiveSessionViewModel.weightString(record.weightKg)) kilograms by \(record.reps) reps, estimated one rep max \(ActiveSessionViewModel.weightString(record.estimatedOneRepMax)) kilograms, \(record.date.formatted(.dateTime.month(.wide).day().year()))"
        )
        .accessibilityHint("Shows history for this exercise")
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
                .accessibilityHidden(true)
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
