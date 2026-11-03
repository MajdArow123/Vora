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
    @Binding var resumeDraft: ActiveSessionDraft?
    @State private var viewModel = WorkoutHomeViewModel()
    @Query private var profiles: [UserProfile]
    @State private var restoringDraft: ActiveSessionDraft?
    @State private var showingSession = false
    @State private var showingCardio = false
    @State private var showingSplitBuilder = false
    @State private var showingTemplateEditor = false
    @State private var showingDayPicker = false
    /// The day picked with "Start a different day"; nil starts the next day.
    @State private var chosenCycleDay: CycleDayInfo?

    init(resumeDraft: Binding<ActiveSessionDraft?> = .constant(nil)) {
        _resumeDraft = resumeDraft
    }

    private var units: UnitSystem {
        profiles.first?.preferredUnits ?? .metric
    }

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
            // On the root, not the stack, so this also runs on the way back
            // from History, where sessions can be deleted.
            .onAppear {
                viewModel.load(from: modelContext)
                presentResumedSession()
            }
        }
        .onChange(of: resumeDraft) {
            presentResumedSession()
        }
        .fullScreenCover(isPresented: $showingSession, onDismiss: {
            restoringDraft = nil
            chosenCycleDay = nil
            viewModel.load(from: modelContext)
            // A finished session moved the cycle, and reminders name its next day.
            if viewModel.isCycleMode {
                NotificationService.shared.refreshAll(context: modelContext)
            }
        }) {
            if let restoringDraft {
                ActiveSessionView(restoring: restoringDraft, units: units)
            } else if let cycleDay = chosenCycleDay ?? viewModel.nextCycleDay {
                ActiveSessionView(
                    sessionName: cycleDay.name,
                    templatePlan: WorkoutTemplateService.sessionPlan(for: cycleDay.slot, context: modelContext),
                    templateSlot: cycleDay.slot,
                    units: units
                )
            } else {
                ActiveSessionView(
                    sessionName: viewModel.todaySplitDay.map {
                        $0.isRest ? "Extra Session" : $0.title
                    } ?? "Session",
                    templatePlan: viewModel.templatePlan(context: modelContext),
                    templateSlot: viewModel.templateSlot,
                    units: units
                )
            }
        }
        .sheet(isPresented: $showingTemplateEditor) {
            TemplateEditorView(
                slot: viewModel.templateSlot,
                dayTitle: viewModel.nextCycleDay?.name ?? viewModel.todaySplitDay?.title ?? "Today"
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

    /// Opens a session the launch prompt chose to resume.
    private func presentResumedSession() {
        guard let draft = resumeDraft, !showingSession else { return }
        resumeDraft = nil
        restoringDraft = draft
        showingSession = true
    }

    // MARK: - Today card

    @ViewBuilder
    private var todayCard: some View {
        if let cycle = viewModel.cycleToday {
            cycleCard(cycle)
        } else {
            weeklyTodayCard
        }
    }

    @ViewBuilder
    private var weeklyTodayCard: some View {
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

    private func cycleCard(_ cycle: CycleToday) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.hasTrainedToday ? "Up Next" : "Today")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .textCase(.uppercase)
                    Text(cycle.current.isRest ? "Rest Day" : cycle.current.name)
                        .font(DesignSystem.Typography.title)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                    if let progress = viewModel.cycleProgressText, !cycle.current.isRest {
                        Text(progress)
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                    }
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

            if !cycle.current.muscleGroups.isEmpty {
                muscleChips(cycle.current.muscleGroups)
            }

            PrimaryButton(title: cycle.current.isRest
                          ? "Start \(cycle.nextTraining?.name ?? "Session")"
                          : "Start Session") {
                showingSession = true
            }

            HStack(spacing: DesignSystem.Spacing.sm) {
                cycleAction("Skip to Next Day", icon: "forward.end") {
                    viewModel.skipCycleDay(context: modelContext)
                    NotificationService.shared.refreshAll(context: modelContext)
                }
                cycleAction("Start a Different Day", icon: "list.number") {
                    showingDayPicker = true
                }
            }

            if !cycle.current.isRest {
                cycleAction("Edit Template", icon: "square.and.pencil") {
                    showingTemplateEditor = true
                }
            }
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large))
        .confirmationDialog("Start a different day", isPresented: $showingDayPicker, titleVisibility: .visible) {
            ForEach(cycle.trainingDays) { day in
                Button(day.name) {
                    chosenCycleDay = day
                    showingSession = true
                }
            }
        } message: {
            Text("The cycle carries on from whichever day you finish.")
        }
    }

    private func cycleAction(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DesignSystem.Spacing.xs) {
                Image(systemName: icon)
                    .accessibilityHidden(true)
                Text(title)
            }
            .font(DesignSystem.Typography.caption)
            .foregroundStyle(DesignSystem.Colors.accent)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
        case .open: DesignSystem.Colors.background
        }
    }

    private func accessibilityLabel(for day: SplitDay, state: SplitDayState) -> String {
        let fullDayNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        let name = fullDayNames[day.dayIndex]
        if viewModel.isCycleMode {
            // The strip is only the calendar here: no day has a planned workout.
            return switch state {
            case .done: "\(name), trained"
            case .today: "\(name), today"
            default: "\(name), no session"
            }
        }
        if day.isRest {
            return "\(name), rest day"
        }
        let status = switch state {
        case .done: "completed"
        case .today: "today"
        case .upcoming: "upcoming"
        case .missed: "missed"
        case .rest: "rest day"
        case .open: "no session"
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
        case .today, .upcoming, .open:
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
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                // Wraps beside the fixed-size sets stat on 6.1-inch widths
                // (minimumScaleFactor does not engage in this hierarchy);
                // "228.33\u{00A0}kg" stays together when it does wrap.
                Text("Est. 1RM · \(UnitConversion.weightNumberText(kg: record.estimatedOneRepMax, units: units))\u{00A0}\(UnitConversion.weightUnitSymbol(units))")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(record.date.formatted(.dateTime.month(.abbreviated).day().year()))
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
            // Claims all width left over by the fixed-size sets stat, so
            // the Est. 1RM line scales instead of truncating.
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            Spacer(minLength: 0)

            HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.xs) {
                Text(StrengthProgression.setsPart(count: record.totalSets))
                    .font(DesignSystem.Typography.headline)
                    .foregroundStyle(DesignSystem.Colors.accent)
                Text("× \(StrengthProgression.repsPart(minReps: record.minReps, maxReps: record.maxReps))")
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
            .lineLimit(1)
            .fixedSize()
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
            "Personal record \(record.spokenSetsSummary), estimated one rep max \(UnitConversion.weightNumberText(kg: record.estimatedOneRepMax, units: units)) \(UnitConversion.spokenWeightUnit(units)), \(record.date.formatted(.dateTime.month(.wide).day().year()))"
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
            actionButton(viewModel.isCycleMode ? "Edit Cycle" : "Edit Split", icon: "calendar") { showingSplitBuilder = true }
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
