//
//  TemplateEditorView.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-24.
//

import OSLog
import SwiftUI
import SwiftData

/// Edits the exercises, superset links and per-exercise targets (sets, rep
/// range, target RIR, rest) for one split or cycle day. Changes apply to
/// future sessions only;
/// Close abandons edits, Save persists them via WorkoutTemplateService.
/// Exercises the active gym can't support stay in the template but are
/// flagged as unavailable.
struct TemplateEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let slot: TemplateSlot
    let dayTitle: String

    @Query(filter: #Predicate<GymProfile> { $0.isActive })
    private var activeProfiles: [GymProfile]
    @State private var specs: [TemplateExerciseSpec] = []
    @State private var expanded: Set<TemplateExerciseSpec.ID> = []
    @State private var didLoad = false
    /// The defaults assigned by Reset to Default. While the list still
    /// equals them, saving deletes the saved template instead of writing a
    /// copy of the defaults.
    @State private var resetSnapshot: [TemplateExerciseSpec]?
    @State private var showingExercisePicker = false
    @State private var errorMessage: String?

    private static let logger = Logger(subsystem: "com.majdarow.Vora", category: "Workout")

    init(slot: TemplateSlot, dayTitle: String) {
        self.slot = slot
        self.dayTitle = dayTitle
    }

    init(split: TrainingSplit, dayIndex: Int, dayTitle: String) {
        self.init(slot: TemplateSlot(split: split, dayIndex: dayIndex), dayTitle: dayTitle)
    }

    /// The weekly slot being edited. A cycle day has no built-in default to
    /// reset to.
    private var weeklySlot: (split: TrainingSplit, dayIndex: Int)? {
        guard slot.cycleDayID == nil, let split = TrainingSplit(rawValue: slot.splitRawValue) else { return nil }
        return (split, slot.dayIndex)
    }

    private func isAvailable(_ spec: TemplateExerciseSpec) -> Bool {
        guard let equipment = activeProfiles.first?.availableEquipment,
              let exerciseId = spec.exerciseId,
              let definition = ExerciseLibrary.definition(id: exerciseId)
        else { return true }
        return definition.isAvailable(with: equipment)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.Colors.background
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    List {
                        if specs.isEmpty {
                            Text("No exercises yet. Add some below.")
                                .font(DesignSystem.Typography.caption)
                                .foregroundStyle(DesignSystem.Colors.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, DesignSystem.Spacing.sm)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }

                        ForEach($specs) { $spec in
                            exerciseRow($spec)
                                .listRowBackground(SupersetBracket(position: supersetPosition(of: spec.id)))
                                .listRowSeparator(.hidden)
                                .listRowInsets(rowInsets)
                        }
                        .onDelete {
                            specs.remove(atOffsets: $0)
                            assignSupersetGroups(SetCounting.normalizedSupersetGroups(specs.map(\.supersetGroup)))
                        }
                        .onMove {
                            specs.move(fromOffsets: $0, toOffset: $1)
                            assignSupersetGroups(SetCounting.normalizedSupersetGroups(specs.map(\.supersetGroup)))
                        }

                        Button {
                            showingExercisePicker = true
                        } label: {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                    .accessibilityHidden(true)
                                Text("Add Exercise")
                                    .font(DesignSystem.Typography.headline)
                                Spacer()
                            }
                            .foregroundStyle(DesignSystem.Colors.accent)
                            .padding(DesignSystem.Spacing.md)
                            .background(DesignSystem.Colors.card)
                            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(rowInsets)

                        if let weeklySlot {
                            Button {
                                let defaults = WorkoutTemplateService.defaultPlan(for: weeklySlot.split, dayIndex: weeklySlot.dayIndex)
                                resetSnapshot = defaults
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    specs = defaults
                                    expanded = []
                                }
                            } label: {
                                Text("Reset to Default")
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
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .environment(\.editMode, .constant(.active))

                    PrimaryButton(title: "Save Template") {
                        save()
                    }
                    .padding(DesignSystem.Spacing.lg)
                }
            }
            .navigationTitle("\(dayTitle) Template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
            }
        }
        .sheet(isPresented: $showingExercisePicker) {
            ExercisePickerView { name, _ in
                let spec = TemplateExerciseSpec(pickedName: name)
                if !specs.contains(where: { $0.identityKey == spec.identityKey }) {
                    specs.append(spec)
                }
            }
        }
        .alert(
            "Couldn't Save Template",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .onChange(of: specs) {
            if let resetSnapshot, specs != resetSnapshot {
                self.resetSnapshot = nil
            }
        }
        .task {
            guard !didLoad else { return }
            didLoad = true
            load()
        }
    }

    // MARK: - Persistence

    private func load() {
        do {
            specs = try WorkoutTemplateService.plan(for: slot, context: modelContext)
        } catch {
            Self.logger.error("Failed to load template: \(String(describing: error), privacy: .public)")
            specs = weeklySlot.map { WorkoutTemplateService.defaultPlan(for: $0.split, dayIndex: $0.dayIndex) } ?? []
        }
    }

    private func save() {
        do {
            if let resetSnapshot, specs == resetSnapshot, let weeklySlot {
                try WorkoutTemplateService.reset(for: weeklySlot.split, dayIndex: weeklySlot.dayIndex, context: modelContext)
            } else {
                try WorkoutTemplateService.save(specs, for: slot, context: modelContext)
            }
            dismiss()
        } catch {
            Self.logger.error("Failed to save template: \(String(describing: error), privacy: .public)")
            errorMessage = "Your changes weren't saved. Please try again."
        }
    }

    // MARK: - Rows

    private var rowInsets: EdgeInsets {
        EdgeInsets(
            top: DesignSystem.Spacing.xs,
            leading: DesignSystem.Spacing.lg,
            bottom: DesignSystem.Spacing.xs,
            trailing: DesignSystem.Spacing.lg
        )
    }

    private func exerciseRow(_ spec: Binding<TemplateExerciseSpec>) -> some View {
        let value = spec.wrappedValue
        let available = isAvailable(value)
        let isExpanded = expanded.contains(value.id)
        return VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isExpanded {
                        expanded.remove(value.id)
                    } else {
                        expanded.insert(value.id)
                    }
                }
            } label: {
                header(value, available: available, isExpanded: isExpanded)
            }
            .buttonStyle(.plain)
            .accessibilityHint(isExpanded ? "Hides targets" : "Shows targets")

            if isExpanded {
                targets(spec)
                    .transition(.opacity)
            }
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
    }

    private func header(_ spec: TemplateExerciseSpec, available: Bool, isExpanded: Bool) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            HStack(spacing: DesignSystem.Spacing.md) {
                Text(spec.displayName)
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(available
                                     ? DesignSystem.Colors.textPrimary
                                     : DesignSystem.Colors.textSecondary)
                Spacer()
                if !available {
                    HStack(spacing: DesignSystem.Spacing.xs) {
                        Image(systemName: "circle.slash")
                            .font(.caption2)
                            .accessibilityHidden(true)
                        Text("Unavailable")
                            .font(DesignSystem.Typography.caption)
                    }
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .padding(.horizontal, DesignSystem.Spacing.sm)
                    .padding(.vertical, DesignSystem.Spacing.xs)
                    .background(DesignSystem.Colors.textSecondary.opacity(0.12))
                    .clipShape(Capsule())
                    .accessibilityLabel("Not available at your active gym")
                }
                if let group = spec.exerciseId.flatMap({ ExerciseLibrary.definition(id: $0) })?.muscleGroup {
                    Text(group.displayName)
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.accent)
                        .padding(.horizontal, DesignSystem.Spacing.sm)
                        .padding(.vertical, DesignSystem.Spacing.xs)
                        .background(DesignSystem.Colors.accent.opacity(0.12))
                        .clipShape(Capsule())
                }
                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    .accessibilityHidden(true)
            }
            Text(Self.summary(spec))
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
        }
        .contentShape(Rectangle())
    }

    // MARK: - Supersets

    private func supersetPosition(of id: TemplateExerciseSpec.ID) -> ActiveSessionViewModel.SupersetPosition? {
        guard let index = specs.firstIndex(where: { $0.id == id }) else { return nil }
        return ActiveSessionViewModel.supersetPosition(in: specs.map(\.supersetGroup), at: index)
    }

    private func assignSupersetGroups(_ groups: [Int?]) {
        for index in specs.indices where specs[index].supersetGroup != groups[index] {
            specs[index].supersetGroup = groups[index]
        }
    }

    @ViewBuilder
    private func supersetButtons(for id: TemplateExerciseSpec.ID) -> some View {
        if let index = specs.firstIndex(where: { $0.id == id }) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                if index + 1 < specs.count,
                   specs[index].supersetGroup == nil || specs[index].supersetGroup != specs[index + 1].supersetGroup {
                    supersetButton("Superset with Next", icon: "link") {
                        assignSupersetGroups(SetCounting.linkingWithNext(specs.map(\.supersetGroup), at: index))
                    }
                }
                if specs[index].supersetGroup != nil {
                    supersetButton("Remove from Superset", icon: "personalhotspot.slash") {
                        assignSupersetGroups(SetCounting.unlinking(specs.map(\.supersetGroup), at: index))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, DesignSystem.Spacing.xs)
        }
    }

    private func supersetButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DesignSystem.Spacing.xs) {
                Image(systemName: icon)
                    .accessibilityHidden(true)
                Text(title)
            }
            .font(DesignSystem.Typography.caption)
            .foregroundStyle(DesignSystem.Colors.accent)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func targets(_ spec: Binding<TemplateExerciseSpec>) -> some View {
        let limits = TemplateExerciseSpec.Limits.self
        return VStack(spacing: DesignSystem.Spacing.xs) {
            Divider()
            supersetButtons(for: spec.wrappedValue.id)
            stepperRow("Sets", value: "\(spec.wrappedValue.targetSets)") {
                Stepper("Sets", value: spec.targetSets, in: limits.sets)
            }
            stepperRow("Min reps", value: "\(spec.wrappedValue.repRangeMin)") {
                Stepper("Min reps", value: minReps(spec), in: limits.reps)
            }
            stepperRow("Max reps", value: "\(spec.wrappedValue.repRangeMax)") {
                Stepper("Max reps", value: maxReps(spec), in: limits.reps)
            }
            stepperRow("Target RIR", value: spec.wrappedValue.targetRIR.map(String.init) ?? "Off") {
                Stepper("Target RIR", value: rir(spec), in: (limits.rir.lowerBound - 1)...limits.rir.upperBound)
            }
            stepperRow("Rest", value: Self.restText(spec.wrappedValue.restSeconds)) {
                Stepper(
                    "Rest",
                    value: spec.restSeconds,
                    in: limits.restSeconds,
                    step: limits.restStepSeconds
                )
            }
        }
    }

    private func stepperRow(
        _ title: String,
        value: String,
        @ViewBuilder stepper: () -> some View
    ) -> some View {
        HStack {
            Text(title)
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
            Spacer()
            Text(value)
                .font(DesignSystem.Typography.headline)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .monospacedDigit()
            stepper()
                .labelsHidden()
                .accessibilityValue(value)
        }
    }

    // MARK: - Bindings

    /// Raising the minimum past the maximum carries the maximum along.
    private func minReps(_ spec: Binding<TemplateExerciseSpec>) -> Binding<Int> {
        Binding(
            get: { spec.wrappedValue.repRangeMin },
            set: { newValue in
                spec.wrappedValue.repRangeMin = newValue
                spec.wrappedValue.repRangeMax = max(spec.wrappedValue.repRangeMax, newValue)
            }
        )
    }

    /// Lowering the maximum below the minimum carries the minimum along.
    private func maxReps(_ spec: Binding<TemplateExerciseSpec>) -> Binding<Int> {
        Binding(
            get: { spec.wrappedValue.repRangeMax },
            set: { newValue in
                spec.wrappedValue.repRangeMax = newValue
                spec.wrappedValue.repRangeMin = min(spec.wrappedValue.repRangeMin, newValue)
            }
        )
    }

    /// One step below the RIR range means "Off" (no target).
    private func rir(_ spec: Binding<TemplateExerciseSpec>) -> Binding<Int> {
        let off = TemplateExerciseSpec.Limits.rir.lowerBound - 1
        return Binding(
            get: { spec.wrappedValue.targetRIR ?? off },
            set: { spec.wrappedValue.targetRIR = $0 == off ? nil : $0 }
        )
    }

    // MARK: - Formatting

    static func restText(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    /// "3 × 8–12 · RIR 2 · 2:00 rest"
    static func summary(_ spec: TemplateExerciseSpec) -> String {
        var parts = ["\(spec.targetSets) × \(ExerciseSessionCard.repRangeText(spec.repRange))"]
        if let rir = spec.targetRIR {
            parts.append("RIR \(rir)")
        }
        parts.append("\(restText(spec.restSeconds)) rest")
        return parts.joined(separator: " · ")
    }
}

#Preview {
    TemplateEditorView(split: .ppl, dayIndex: 0, dayTitle: "Push")
        .modelContainer(for: [GymProfile.self, WorkoutTemplate.self], inMemory: true)
}
