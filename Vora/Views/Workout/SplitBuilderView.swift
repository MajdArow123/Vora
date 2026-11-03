//
//  SplitBuilderView.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import OSLog
import SwiftUI
import SwiftData

/// Schedule editor: the weekly split or the training cycle, with the mode
/// picker above them. Edits the persisted SplitDay rows directly; changes are
/// saved on Done. Switching mode never touches the other mode's days.
struct SplitBuilderView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SplitDay.dayIndex) private var days: [SplitDay]
    @Query private var programs: [TrainingProgram]
    @State private var errorMessage: String?

    private static let logger = Logger(subsystem: "com.majdarow.Vora", category: "Workout")

    private var mode: ScheduleMode {
        programs.first?.mode ?? .weekly
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.Colors.background
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                        Picker("Schedule", selection: Binding(get: { mode }, set: { setMode($0) })) {
                            ForEach(ScheduleMode.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        Text(mode == .cycle
                             ? "Train in order, on any day. A missed day just waits for you."
                             : "Each workout belongs to a weekday.")
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                    }
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    .padding(.vertical, DesignSystem.Spacing.sm)

                    if mode == .cycle {
                        CycleEditorView()
                    } else {
                        ScrollView {
                            VStack(spacing: DesignSystem.Spacing.sm) {
                                ForEach(days) { day in
                                    NavigationLink {
                                        SplitDayEditorView(day: day)
                                    } label: {
                                        dayRow(day)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, DesignSystem.Spacing.lg)
                            .padding(.vertical, DesignSystem.Spacing.md)
                        }
                    }
                }
            }
            .navigationTitle(mode == .cycle ? "Training Cycle" : "Weekly Split")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        do {
                            try modelContext.save()
                        } catch {
                            Self.logger.error("Failed to save the schedule: \(String(describing: error), privacy: .public)")
                        }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(DesignSystem.Colors.accent)
                }
            }
            .alert(
                "Couldn't Switch Schedule",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func setMode(_ mode: ScheduleMode) {
        do {
            try TrainingProgramService.setMode(mode, context: modelContext)
        } catch {
            Self.logger.error("Failed to switch schedule mode: \(String(describing: error), privacy: .public)")
            modelContext.rollback()
            errorMessage = "Your schedule wasn't changed. Please try again."
        }
    }

    private func dayRow(_ day: SplitDay) -> some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            Text(SplitDay.dayNames[day.dayIndex])
                .font(DesignSystem.Typography.headline)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .frame(width: 44, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(day.isRest ? "Rest" : day.title)
                    .font(DesignSystem.Typography.headline)
                    .foregroundStyle(day.isRest
                                     ? DesignSystem.Colors.textSecondary
                                     : DesignSystem.Colors.textPrimary)
                if !day.isRest, !day.muscleGroups.isEmpty {
                    Text(day.muscleGroups
                        .map { MuscleGroup(rawValue: $0)?.displayName ?? $0.capitalized }
                        .joined(separator: ", "))
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary.opacity(0.5))
                .accessibilityHidden(true)
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
        .contentShape(Rectangle())
    }
}

struct SplitDayEditorView: View {
    @Bindable var day: SplitDay

    var body: some View {
        ZStack {
            DesignSystem.Colors.background
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                    Toggle(isOn: Binding(
                        get: { day.isRest },
                        set: { newValue in
                            day.isRest = newValue
                            if newValue {
                                day.title = "Rest"
                                day.muscleGroups = []
                            } else if day.title == "Rest" {
                                day.title = "Workout"
                            }
                        }
                    )) {
                        Text("Rest day")
                            .font(DesignSystem.Typography.headline)
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                    }
                    .tint(DesignSystem.Colors.accent)
                    .padding(DesignSystem.Spacing.md)
                    .background(DesignSystem.Colors.card)
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))

                    if !day.isRest {
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                            Text("Day name")
                                .font(DesignSystem.Typography.caption)
                                .foregroundStyle(DesignSystem.Colors.textSecondary)
                                .textCase(.uppercase)
                            TextField("e.g. Push", text: $day.title)
                                .padding(DesignSystem.Spacing.md)
                                .background(DesignSystem.Colors.card)
                                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
                        }

                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                            Text("Muscle groups")
                                .font(DesignSystem.Typography.caption)
                                .foregroundStyle(DesignSystem.Colors.textSecondary)
                                .textCase(.uppercase)

                            MuscleGroupChips(selection: $day.muscleGroups)
                        }
                    }
                }
                .padding(DesignSystem.Spacing.lg)
            }
        }
        .navigationTitle(SplitDay.dayNames[day.dayIndex])
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Toggleable muscle-group chips in a simple two-column grid.
struct MuscleGroupChips: View {
    @Binding var selection: [String]

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(MuscleGroup.allCases) { group in
                let isSelected = selection.contains(group.rawValue)
                Button {
                    if isSelected {
                        selection.removeAll { $0 == group.rawValue }
                    } else {
                        selection.append(group.rawValue)
                    }
                } label: {
                    Text(group.displayName)
                        .font(DesignSystem.Typography.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(isSelected ? .white : DesignSystem.Colors.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DesignSystem.Spacing.sm)
                        .background(isSelected ? DesignSystem.Colors.accent : DesignSystem.Colors.card)
                        .clipShape(Capsule())
                        .contentShape(Rectangle().inset(by: -8))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}

#Preview {
    SplitBuilderView()
        .modelContainer(for: [SplitDay.self, TrainingProgram.self], inMemory: true)
}
