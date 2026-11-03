//
//  CycleEditorView.swift
//  Vora
//
//  Created by Majd Arow on 2026-11-03.
//

import OSLog
import SwiftUI
import SwiftData

/// Creates, reorders and removes the days of a training cycle. Every change
/// saves straight away through TrainingProgramService.
struct CycleEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CycleDay.orderIndex) private var days: [CycleDay]
    @Query private var programs: [TrainingProgram]
    @State private var selectedDay: CycleDay?
    @State private var showingRebuildConfirmation = false
    @State private var errorMessage: String?

    private static let logger = Logger(subsystem: "com.majdarow.Vora", category: "Workout")

    private var entries: [CycleEngine.Entry] {
        days.map { CycleEngine.Entry(id: $0.id, isRest: $0.isRest) }
    }

    private var nextDayID: UUID? {
        CycleEngine.current(in: entries, id: programs.first?.currentDayID)?.id
    }

    var body: some View {
        List {
            ForEach(days) { day in
                Button {
                    selectedDay = day
                } label: {
                    dayRow(day)
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(rowInsets)
            }
            .onDelete(perform: remove)
            .onMove(perform: move)

            HStack(spacing: DesignSystem.Spacing.sm) {
                addButton("Add Day", icon: "plus.circle.fill", isRest: false)
                addButton("Add Rest", icon: "moon.zzz.fill", isRest: true)
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(rowInsets)

            Button {
                showingRebuildConfirmation = true
            } label: {
                Text("Rebuild from Weekly Split")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(rowInsets)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.editMode, .constant(.active))
        .navigationDestination(item: $selectedDay) { day in
            CycleDayEditorView(day: day, number: CycleEngine.dayNumber(of: day.id, in: entries))
        }
        .confirmationDialog(
            "Replace this cycle?",
            isPresented: $showingRebuildConfirmation,
            titleVisibility: .visible
        ) {
            Button("Rebuild", role: .destructive) { rebuild() }
        } message: {
            Text("Its days and templates are replaced with a copy of your weekly split, starting at Day 1.")
        }
        .alert(
            "Couldn't Update the Cycle",
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

    private var rowInsets: EdgeInsets {
        EdgeInsets(
            top: DesignSystem.Spacing.xs,
            leading: DesignSystem.Spacing.lg,
            bottom: DesignSystem.Spacing.xs,
            trailing: DesignSystem.Spacing.lg
        )
    }

    private func dayRow(_ day: CycleDay) -> some View {
        let number = CycleEngine.dayNumber(of: day.id, in: entries)
        return HStack(spacing: DesignSystem.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(number.map { CycleEngine.displayName(number: $0, title: day.title) } ?? "Rest")
                    .font(DesignSystem.Typography.headline)
                    .foregroundStyle(day.isRest
                                     ? DesignSystem.Colors.textSecondary
                                     : DesignSystem.Colors.textPrimary)
                if !day.isRest {
                    Text(exerciseCount(day))
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
            }
            Spacer()
            if day.id == nextDayID {
                Text("Next")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.accent)
                    .padding(.horizontal, DesignSystem.Spacing.sm)
                    .padding(.vertical, DesignSystem.Spacing.xs)
                    .background(DesignSystem.Colors.accent.opacity(0.12))
                    .clipShape(Capsule())
            }
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
        .contentShape(Rectangle())
    }

    private func exerciseCount(_ day: CycleDay) -> String {
        let count = day.template?.exercises.count ?? 0
        return "\(count) exercise\(count == 1 ? "" : "s")"
    }

    private func addButton(_ title: String, icon: String, isRest: Bool) -> some View {
        Button {
            perform("add a day") {
                try TrainingProgramService.addDay(isRest: isRest, context: modelContext)
            }
        } label: {
            HStack {
                Image(systemName: icon)
                    .accessibilityHidden(true)
                Text(title)
                    .font(DesignSystem.Typography.headline)
            }
            .foregroundStyle(DesignSystem.Colors.accent)
            .frame(maxWidth: .infinity)
            .padding(DesignSystem.Spacing.md)
            .background(DesignSystem.Colors.card)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func remove(at offsets: IndexSet) {
        for id in offsets.map({ days[$0].id }) {
            do {
                try TrainingProgramService.remove(dayID: id, context: modelContext)
            } catch CycleEditError.lastTrainingDay {
                errorMessage = "A cycle needs at least one training day."
            } catch {
                report(error, action: "remove a day")
            }
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        perform("reorder the days") {
            var ids = days.map(\.id)
            ids.move(fromOffsets: source, toOffset: destination)
            try TrainingProgramService.reorder(dayIDs: ids, context: modelContext)
        }
    }

    private func rebuild() {
        perform("rebuild the cycle") {
            try TrainingProgramService.rebuildFromWeekly(context: modelContext)
        }
    }

    private func perform(_ action: String, _ change: () throws -> Void) {
        do {
            try change()
        } catch {
            report(error, action: action)
        }
    }

    private func report(_ error: Error, action: String) {
        Self.logger.error("Failed to \(action, privacy: .public): \(String(describing: error), privacy: .public)")
        errorMessage = "Your change wasn't saved. Please try again."
    }
}

/// Renames a cycle day, sets its muscle groups and template, or makes it next.
private struct CycleDayEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var day: CycleDay
    let number: Int?
    @State private var showingTemplateEditor = false
    @State private var errorMessage: String?

    private static let logger = Logger(subsystem: "com.majdarow.Vora", category: "Workout")

    private var name: String {
        number.map { CycleEngine.displayName(number: $0, title: day.title) } ?? "Rest"
    }

    var body: some View {
        ZStack {
            DesignSystem.Colors.background
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                    if !day.isRest {
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                            sectionTitle("Day name")
                            TextField("e.g. Push", text: Binding(
                                get: { day.title },
                                set: { TrainingProgramService.rename(day, to: $0) }
                            ))
                            .padding(DesignSystem.Spacing.md)
                            .background(DesignSystem.Colors.card)
                            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
                        }

                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                            sectionTitle("Muscle groups")
                            MuscleGroupChips(selection: $day.muscleGroups)
                        }

                        PrimaryButton(title: "Edit Template") {
                            showingTemplateEditor = true
                        }
                    }

                    Button {
                        setAsNext()
                    } label: {
                        Text("Set as Next Day")
                            .font(DesignSystem.Typography.headline)
                            .foregroundStyle(DesignSystem.Colors.accent)
                            .frame(maxWidth: .infinity)
                            .padding(DesignSystem.Spacing.md)
                            .background(DesignSystem.Colors.card)
                            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(DesignSystem.Spacing.lg)
            }
        }
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingTemplateEditor) {
            TemplateEditorView(slot: TemplateSlot(cycleDayID: day.id), dayTitle: name)
        }
        .alert(
            "Couldn't Update the Cycle",
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

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(DesignSystem.Typography.caption)
            .foregroundStyle(DesignSystem.Colors.textSecondary)
            .textCase(.uppercase)
    }

    private func setAsNext() {
        do {
            try TrainingProgramService.setNext(dayID: day.id, context: modelContext)
            dismiss()
        } catch {
            Self.logger.error("Failed to set the next day: \(String(describing: error), privacy: .public)")
            errorMessage = "Your change wasn't saved. Please try again."
        }
    }
}
