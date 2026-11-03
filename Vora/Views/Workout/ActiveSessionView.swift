//
//  ActiveSessionView.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import SwiftUI
import SwiftData

struct ActiveSessionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel: ActiveSessionViewModel
    @State private var showingExercisePicker = false
    @State private var swappingExercise: ActiveSessionViewModel.DraftExercise?
    @State private var infoExercise: ActiveSessionViewModel.DraftExercise?
    @State private var showingDiscardConfirm = false
    @Query(filter: #Predicate<GymProfile> { $0.isActive })
    private var activeProfiles: [GymProfile]
    @State private var didPrefill = false
    @State private var editMode: EditMode = .inactive
    @AppStorage(SessionPrefillMode.storageKey) private var prefillMode: SessionPrefillMode = .smart
    @AppStorage(ProgressionMode.storageKey) private var progressionMode: ProgressionMode = .repsFirst
    @AppStorage(SmartWarmUpSettings.storageKey) private var smartWarmUps = SmartWarmUpSettings.defaultEnabled

    private let templatePlan: [TemplateExerciseSpec]
    private let restoredDraft: ActiveSessionDraft?

    init(
        sessionName: String,
        templatePlan: [TemplateExerciseSpec] = [],
        templateSlot: TemplateSlot? = nil,
        units: UnitSystem,
        draftStore: SessionDraftStore? = SessionDraftStore()
    ) {
        _viewModel = State(initialValue: ActiveSessionViewModel(
            sessionName: sessionName,
            units: units,
            templateSlot: templateSlot,
            draftStore: draftStore,
            restActivity: RestActivityController(),
            restAlert: RestAlertService()
        ))
        self.templatePlan = templatePlan
        self.restoredDraft = nil
    }

    /// Resumes a session saved before the app was killed.
    init(restoring draft: ActiveSessionDraft, units: UnitSystem, draftStore: SessionDraftStore = SessionDraftStore()) {
        _viewModel = State(initialValue: ActiveSessionViewModel(
            sessionName: draft.sessionName,
            units: units,
            draftStore: draftStore,
            restActivity: RestActivityController(),
            restAlert: RestAlertService()
        ))
        self.templatePlan = []
        self.restoredDraft = draft
    }

    var body: some View {
        ZStack {
            DesignSystem.Colors.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    .padding(.vertical, DesignSystem.Spacing.sm)

                if viewModel.exercises.count > 1 {
                    reorderToggle
                        .padding(.horizontal, DesignSystem.Spacing.lg)
                }

                List {
                    ForEach(viewModel.exercises) { exercise in
                        ExerciseSessionCard(
                            exercise: exercise,
                            viewModel: viewModel,
                            isUnavailable: isUnavailable(exercise.name),
                            inventory: activeProfiles.first?.loadingInventory,
                            onSwap: {
                                swappingExercise = exercise
                            },
                            onInfo: {
                                infoExercise = exercise
                            },
                            onFix: { fix in
                                if fix == .swapExercise {
                                    swappingExercise = exercise
                                } else {
                                    viewModel.applyFix(fix, exerciseID: exercise.id, context: modelContext)
                                }
                            }
                        )
                        .listRowBackground(SupersetBracket(position: viewModel.supersetPosition(of: exercise.id)))
                        .listRowSeparator(.hidden)
                        .listRowInsets(rowInsets)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                viewModel.removeExercise(exercise.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    .onMove { offsets, destination in
                        viewModel.moveExercise(fromOffsets: offsets, toOffset: destination)
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
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .contentMargins(.bottom, 120, for: .scrollContent)
                .environment(\.editMode, $editMode)
                .scrollDismissesKeyboard(.interactively)
            }

            VStack {
                Spacer()
                if viewModel.restEndDate != nil {
                    RestTimerBar(viewModel: viewModel)
                        .padding(.horizontal, DesignSystem.Spacing.lg)
                        .padding(.bottom, DesignSystem.Spacing.md)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.35), value: viewModel.restEndDate != nil)
        }
        .sheet(isPresented: $showingExercisePicker) {
            ExercisePickerView { name, muscleGroups in
                viewModel.addExercise(name: name, muscleGroups: muscleGroups, context: modelContext)
            }
        }
        .sheet(item: $swappingExercise) { exercise in
            ExercisePickerView { name, muscleGroups in
                viewModel.replaceExercise(
                    exercise.id,
                    withName: name,
                    muscleGroups: muscleGroups,
                    context: modelContext
                )
            }
        }
        .sheet(item: $infoExercise) { exercise in
            ExerciseDetailSheet(exerciseName: exercise.name)
        }
        .alert("Couldn't save the rep range", isPresented: $viewModel.templateSaveFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("It applies to this session, but your template keeps its old range.")
        }
        .sheet(item: $viewModel.summary, onDismiss: { dismiss() }) { summary in
            SessionSummaryView(summary: summary, units: viewModel.units)
        }
        .confirmationDialog(
            "Discard this session?",
            isPresented: $showingDiscardConfirm,
            titleVisibility: .visible
        ) {
            Button("Discard Session", role: .destructive) {
                viewModel.discardDraft()
                dismiss()
            }
            Button("Keep Training", role: .cancel) {}
        }
        .onAppear {
            guard !didPrefill else { return }
            didPrefill = true
            viewModel.warmUpInventory = smartWarmUps ? activeProfiles.first?.loadingInventory : nil
            if let restoredDraft {
                viewModel.restore(from: restoredDraft, context: modelContext, progression: progressionContext)
            } else {
                viewModel.prefill(with: templatePlan, context: modelContext, progression: progressionContext)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // A kill in the background must not lose the debounce window.
            if phase != .active {
                viewModel.flushDraft()
            } else {
                viewModel.reconcileRest()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)) { _ in
            viewModel.prepareForTermination()
        }
    }

    private var progressionContext: ProgressionContext? {
        guard prefillMode == .smart else { return nil }
        return ProgressionContext(
            mode: progressionMode,
            inventory: activeProfiles.first?.loadingInventory,
            deficitPercent: CoachingService.deficitPercentOrNil(context: modelContext)
        )
    }

    // MARK: - Equipment availability

    /// A template can carry exercises the active gym can't support; they
    /// stay in the session (never auto-removed) but get flagged so the
    /// user can skip or swap them.
    private func isUnavailable(_ name: String) -> Bool {
        guard let equipment = activeProfiles.first?.availableEquipment else { return false }
        return !ExerciseLibrary.isAvailable(name: name, with: equipment)
    }

    // MARK: - Reorder

    private var rowInsets: EdgeInsets {
        EdgeInsets(
            top: DesignSystem.Spacing.sm,
            leading: DesignSystem.Spacing.lg,
            bottom: DesignSystem.Spacing.sm,
            trailing: DesignSystem.Spacing.lg
        )
    }

    private var reorderToggle: some View {
        HStack {
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    editMode = editMode == .active ? .inactive : .active
                }
            } label: {
                HStack(spacing: DesignSystem.Spacing.xs) {
                    Image(systemName: editMode == .active
                          ? "checkmark"
                          : "line.3.horizontal")
                        .accessibilityHidden(true)
                    Text(editMode == .active ? "Done" : "Reorder")
                }
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.accent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(editMode == .active ? "Finish reordering" : "Reorder exercises")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button {
                if viewModel.completedSetCount > 0 {
                    showingDiscardConfirm = true
                } else {
                    viewModel.discardDraft()
                    dismiss()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .frame(width: 44, height: 44)
                    .background(DesignSystem.Colors.card)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close session")

            Spacer()

            TimelineView(.periodic(from: .now, by: 1)) { _ in
                VStack(spacing: 0) {
                    Text(Self.timeString(viewModel.elapsedSeconds))
                        .font(.system(.headline, design: .monospaced))
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                    Text("\(UnitConversion.volumeText(kg: viewModel.totalVolumeKg, units: viewModel.units)) volume")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
            }

            Spacer()

            Button {
                viewModel.finish(context: modelContext)
                let context = modelContext
                let finished = viewModel
                Task {
                    await finished.recordHealthWorkout(context: context)
                }
            } label: {
                Text("Finish")
                    .font(DesignSystem.Typography.headline)
                    .foregroundStyle(viewModel.canFinish ? .white : DesignSystem.Colors.textSecondary)
                    .padding(.horizontal, DesignSystem.Spacing.md)
                    .frame(height: 44)
                    .background(viewModel.canFinish
                                ? DesignSystem.Colors.accent
                                : DesignSystem.Colors.card)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canFinish)
        }
    }

    static func timeString(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

// MARK: - Exercise card

struct ExerciseSessionCard: View {
    let exercise: ActiveSessionViewModel.DraftExercise
    let viewModel: ActiveSessionViewModel
    var isUnavailable = false
    /// The active gym's inventory; nil if it hasn't been filled yet.
    var inventory: LoadingInventory?
    var onSwap: () -> Void = {}
    var onInfo: () -> Void = {}
    var onFix: (ProgressionFix) -> Void = { _ in }

    @State private var plateRequest: ActiveSessionViewModel.PlateCalculatorRequest?
    @State private var whySetID: ActiveSessionViewModel.DraftSet.ID?
    /// The set whose plate caption was asked for by tapping its weight.
    /// Clears once the next set to do changes.
    @State private var revealedPlatesSetID: ActiveSessionViewModel.DraftSet.ID?
    /// A fix chosen in the why sheet, applied once it has closed, since a
    /// swap opens a sheet of its own.
    @State private var pendingFix: ProgressionFix?
    /// Stays for this exercise while the session is open; not persisted.
    @State private var selectedBarName: String?

    /// "8–12", or "8" when the range is a single rep count.
    static func repRangeText(_ range: ClosedRange<Int>) -> String {
        range.lowerBound == range.upperBound
            ? "\(range.lowerBound)"
            : "\(range.lowerBound)–\(range.upperBound)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            HStack {
                Text(exercise.name)
                    .font(DesignSystem.Typography.headline)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                if isUnavailable {
                    HStack(spacing: DesignSystem.Spacing.xs) {
                        Image(systemName: "circle.slash")
                            .font(.caption2)
                            .accessibilityHidden(true)
                        Text("Unavailable")
                            .font(DesignSystem.Typography.caption)
                    }
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .padding(.horizontal, DesignSystem.Spacing.sm)
                    .padding(.vertical, 4)
                    .background(DesignSystem.Colors.textSecondary.opacity(0.12))
                    .clipShape(Capsule())
                    .accessibilityLabel("Not available at your active gym")
                }
                if exercise.supersetGroup != nil {
                    Image(systemName: "link")
                        .font(.caption)
                        .foregroundStyle(DesignSystem.Colors.accent)
                        .accessibilityLabel("In a superset")
                }
                Spacer()
                Button(action: onInfo) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle().inset(by: -4))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Exercise technique and muscles")
                Menu {
                    Button {
                        onSwap()
                    } label: {
                        Label("Swap Exercise", systemImage: "arrow.triangle.2.circlepath")
                    }
                    if viewModel.canAddWarmUps(to: exercise.id) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                viewModel.addWarmUps(to: exercise.id)
                            }
                        } label: {
                            Label("Add Warm-Ups", systemImage: "flame")
                        }
                    }
                    if canLinkWithNext {
                        Button {
                            viewModel.linkWithNext(exercise.id)
                        } label: {
                            Label("Superset with Next", systemImage: "link")
                        }
                    }
                    if exercise.supersetGroup != nil {
                        Button {
                            viewModel.unlinkFromSuperset(exercise.id)
                        } label: {
                            Label("Remove from Superset", systemImage: "personalhotspot.slash")
                        }
                    }
                    Button(role: .destructive) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.removeExercise(exercise.id)
                        }
                    } label: {
                        Label("Remove Exercise", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle().inset(by: -4))
                }
                .accessibilityLabel("Exercise options")
            }

            if let warned = exercise.activeWarningRecommendation {
                ProgressionWarningCard(recommendation: warned, units: viewModel.units, onFix: onFix)
            }

            HStack(spacing: SetRow.columnSpacing) {
                Text("SET")
                    .frame(width: SetRow.setNumberWidth, alignment: .leading)
                Text("PREVIOUS")
                    .frame(width: 76, alignment: .leading)
                Text(UnitConversion.weightUnitSymbol(viewModel.units).uppercased())
                    .frame(maxWidth: .infinity, alignment: .center)
                Text("REPS")
                    .frame(maxWidth: .infinity, alignment: .center)
                Text("RIR")
                    .frame(width: SetRow.rirWidth, alignment: .center)
                Color.clear.frame(width: 40, height: 1)
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(DesignSystem.Colors.textSecondary)

            let labels = SetCounting.labels(exercise.sets.map(\.setType))
            ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { index, set in
                SetRow(
                    label: labels[index],
                    set: set,
                    previousText: exercise.previousSet(at: index)?.text(units: viewModel.units) ?? "—",
                    repsPlaceholder: repsPlaceholder(for: set),
                    targetRIR: set.setType.isWorkingSet ? exercise.targets?.targetRIR : nil,
                    exerciseID: exercise.id,
                    viewModel: viewModel,
                    plateCaption: exercise.showsPlateCaption(for: set.id, revealed: revealedPlatesSetID)
                        ? plateCaption(for: set)
                        : nil,
                    onPlatesTapped: {
                        plateRequest = .init(setID: set.id, exerciseID: exercise.id)
                    },
                    onWeightTapped: {
                        revealedPlatesSetID = set.id
                    },
                    onWhyTapped: {
                        whySetID = set.id
                    }
                )
            }

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.addSet(to: exercise.id)
                }
            } label: {
                HStack {
                    Image(systemName: "plus")
                        .accessibilityHidden(true)
                    Text("Add Set")
                }
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DesignSystem.Spacing.sm)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
        .onChange(of: exercise.nextSetID) {
            revealedPlatesSetID = nil
        }
        .sheet(item: $plateRequest) { request in
            PlateCalculatorSheet(
                totalKg: viewModel.plateCalculatorWeightKg(for: request) ?? 0,
                equipment: exercise.plateLoadedEquipment ?? .barbell,
                inventory: inventory ?? .withoutBarbell(units: viewModel.units),
                units: viewModel.units,
                selectedBarName: $selectedBarName
            )
        }
        .sheet(item: whySheetBinding, onDismiss: {
            if let fix = pendingFix {
                pendingFix = nil
                onFix(fix)
            }
        }) { request in
            RecommendationSheet(
                exerciseName: exercise.name,
                setNumber: request.setNumber,
                recommendation: request.recommendation,
                lastSessionText: exercise.previousSets.isEmpty
                    ? nil
                    : exercise.previousSets.map { $0.text(units: viewModel.units) }.joined(separator: ", "),
                units: viewModel.units,
                onFix: { pendingFix = $0 }
            )
        }
    }

    /// Whether the next exercise is outside this one's superset.
    private var canLinkWithNext: Bool {
        guard let index = viewModel.exercises.firstIndex(where: { $0.id == exercise.id }),
              index + 1 < viewModel.exercises.count
        else { return false }
        return exercise.supersetGroup == nil
            || viewModel.exercises[index + 1].supersetGroup != exercise.supersetGroup
    }

    /// Targets are for working sets; other types have no rep range to hit.
    private func repsPlaceholder(for set: ActiveSessionViewModel.DraftSet) -> String {
        guard set.setType.isWorkingSet else { return "0" }
        return set.activeRecommendation.map { "\($0.targetReps)" }
            ?? exercise.repRange.map { Self.repRangeText($0) }
            ?? "0"
    }

    private struct WhyRequest: Identifiable {
        let id: ActiveSessionViewModel.DraftSet.ID
        let setNumber: Int
        let recommendation: Recommendation
    }

    /// Reads the set when the sheet opens, so it never shows stale numbers.
    private var whySheetBinding: Binding<WhyRequest?> {
        Binding(
            get: {
                guard let whySetID,
                      let index = exercise.sets.firstIndex(where: { $0.id == whySetID }),
                      let recommendation = exercise.sets[index].activeRecommendation
                else { return nil }
                return WhyRequest(id: whySetID, setNumber: exercise.workingSetOrdinal(at: index) + 1, recommendation: recommendation)
            },
            set: { whySetID = $0?.id }
        )
    }

    /// "Nearest: 57.5 or 60 kg", or just the side that exists.
    static func nearestLoadsText(below: Double?, above: Double?, units: UnitSystem) -> String {
        let symbol = UnitConversion.weightUnitSymbol(units)
        let number = { (kg: Double) in UnitConversion.weightNumberText(kg: kg, units: units) }
        switch (below, above) {
        case let (below?, above?): return "Nearest: \(number(below)) or \(number(above)) \(symbol)"
        case let (below?, nil): return "Nearest: \(number(below)) \(symbol)"
        case let (nil, above?): return "Nearest: \(number(above)) \(symbol)"
        case (nil, nil): return "No loadable weights on this bar"
        }
    }

    /// Nil unless this is a plate-loaded exercise with a weight entered.
    private func plateCaption(for set: ActiveSessionViewModel.DraftSet) -> SetRow.PlateCaption? {
        guard let equipment = exercise.plateLoadedEquipment,
              let totalKg = set.weightKg, totalKg > 0
        else { return nil }
        let bars = inventory?.bars(for: equipment) ?? []
        guard let inventory,
              let bar = bars.first(where: { $0.name == selectedBarName })
                ?? LoadCalculator.preferredBar(forKg: totalKg, equipment: equipment, profile: inventory)
        else {
            return SetRow.PlateCaption(text: "Plate calculator", isLoadable: true)
        }
        guard let stack = LoadCalculator.plateBreakdown(totalKg: totalKg, bar: bar, profile: inventory) else {
            let nearest = LoadCalculator.nearestLoads(aroundKg: totalKg, bar: bar, profile: inventory)
            return SetRow.PlateCaption(
                text: Self.nearestLoadsText(below: nearest.below, above: nearest.above, units: viewModel.units),
                isLoadable: false
            )
        }
        let summary = PlateStackText.summary(stack, units: viewModel.units)
        return SetRow.PlateCaption(text: stack.isEmpty ? summary : "Per side: \(summary)", isLoadable: true)
    }
}

// MARK: - Set row

fileprivate struct SetRow: View {
    // Sized so a weight like 102.25 stays readable beside the RIR column.
    static let columnSpacing: CGFloat = 6
    static let setNumberWidth: CGFloat = 22
    static let rirWidth: CGFloat = 32

    struct PlateCaption {
        let text: String
        let isLoadable: Bool
    }

    let label: String
    let set: ActiveSessionViewModel.DraftSet
    let previousText: String
    let repsPlaceholder: String
    let targetRIR: Int?
    let exerciseID: ActiveSessionViewModel.DraftExercise.ID
    let viewModel: ActiveSessionViewModel
    let plateCaption: PlateCaption?
    let onPlatesTapped: () -> Void
    let onWeightTapped: () -> Void
    let onWhyTapped: () -> Void

    @FocusState private var isWeightFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            controls
            captions
                .padding(.leading, Self.setNumberWidth + Self.columnSpacing)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, DesignSystem.Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                .fill(rowBackground)
        )
        .contextMenu {
            Button(role: .destructive) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.removeSet(set.id, from: exerciseID)
                }
            } label: {
                Label("Delete Set", systemImage: "trash")
            }
        }
    }

    private var rowBackground: Color {
        if set.isCompleted { return DesignSystem.Colors.accent.opacity(0.08) }
        return set.setType == .warmUp ? set.setType.tint.opacity(0.1) : .clear
    }

    /// Side by side when they fit, so a set doesn't take three lines.
    @ViewBuilder
    private var captions: some View {
        switch (set.activeRecommendation, plateCaption) {
        case let (recommendation?, caption?):
            ViewThatFits(in: .horizontal) {
                HStack(spacing: DesignSystem.Spacing.md) {
                    whyButton(recommendation)
                    plateButton(caption)
                    Spacer(minLength: 0)
                }
                VStack(alignment: .leading, spacing: 0) {
                    whyButton(recommendation)
                    plateButton(caption)
                }
            }
        case let (recommendation?, nil):
            HStack {
                whyButton(recommendation)
                Spacer(minLength: 0)
            }
        case let (nil, caption?):
            HStack {
                plateButton(caption)
                Spacer(minLength: 0)
            }
        case (nil, nil):
            EmptyView()
        }
    }

    private func whyButton(_ recommendation: Recommendation) -> some View {
        let headline = ProgressionExplanation.headline(recommendation, units: set.units)
        return Button(action: onWhyTapped) {
            HStack(spacing: DesignSystem.Spacing.xs) {
                Image(systemName: "wand.and.stars")
                    .accessibilityHidden(true)
                Text(headline)
                    .lineLimit(1)
            }
            .font(DesignSystem.Typography.caption)
            .foregroundStyle(recommendation.warnings.isEmpty ? DesignSystem.Colors.accent : DesignSystem.Colors.warning)
            .frame(minHeight: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(headline)
        .accessibilityHint("Explains this recommendation")
    }

    private func plateButton(_ caption: PlateCaption) -> some View {
        Button(action: onPlatesTapped) {
            HStack(spacing: DesignSystem.Spacing.xs) {
                Image(systemName: caption.isLoadable ? "circle.circle" : "exclamationmark.triangle")
                    .accessibilityHidden(true)
                Text(caption.text)
                    .lineLimit(1)
            }
            .font(DesignSystem.Typography.caption)
            .foregroundStyle(caption.isLoadable ? DesignSystem.Colors.accent : DesignSystem.Colors.warning)
            .frame(minHeight: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(caption.text)
        .accessibilityHint("Opens the plate calculator")
    }

    private var controls: some View {
        HStack(spacing: Self.columnSpacing) {
            setTypeMenu

            Text(previousText)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .frame(width: 76, alignment: .leading)
                .lineLimit(1)

            field(binding(\.weightText), placeholder: "0")
                .focused($isWeightFocused)
                .onChange(of: isWeightFocused) { _, isFocused in
                    if isFocused { onWeightTapped() }
                }
                // A completed set's field is disabled, so it can't take focus.
                .simultaneousGesture(
                    TapGesture().onEnded { onWeightTapped() },
                    including: set.isCompleted ? .all : .subviews
                )
                .accessibilityLabel("Weight in \(UnitConversion.spokenWeightUnit(set.units))")
            field(binding(\.repsText), placeholder: repsPlaceholder)
                .accessibilityLabel("Reps")

            rirPicker

            Button {
                let completed = withAnimation(.spring(duration: 0.3)) {
                    viewModel.toggleCompletion(setID: set.id, in: exerciseID)
                }
                if completed {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    viewModel.startRestIfDue(afterCompleting: set.id, in: exerciseID)
                }
            } label: {
                Image(systemName: set.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(set.isCompleted
                                     ? DesignSystem.Colors.accent
                                     : DesignSystem.Colors.textSecondary.opacity(0.3))
                    .frame(width: 40, height: 40)
                    .scaleEffect(set.isCompleted ? 1.08 : 1)
                    .contentShape(Rectangle().inset(by: -2))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(set.isCompleted ? "Mark set incomplete" : "Mark set complete")
        }
    }

    /// Tap the number to change the set's type or side. Stays enabled on
    /// completed sets, so a set can be corrected after doing it.
    private var setTypeMenu: some View {
        Menu {
            Picker("Set type", selection: typeBinding) {
                ForEach(SetType.allCases) { type in
                    Text(type.displayName).tag(type)
                }
            }
            Picker("Side", selection: sideBinding) {
                Text("Both sides").tag(SetSide?.none)
                ForEach(SetSide.allCases) { side in
                    Text(side.displayName).tag(SetSide?.some(side))
                }
            }
        } label: {
            SetLabel(text: label, type: set.setType, side: set.side)
                .frame(width: Self.setNumberWidth, height: 40, alignment: .leading)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(SetLabel.spokenText(label: label, type: set.setType, side: set.side))
        .accessibilityHint("Changes the set type or side")
    }

    private var typeBinding: Binding<SetType> {
        Binding(
            get: {
                viewModel.exercises.first { $0.id == exerciseID }?
                    .sets.first { $0.id == set.id }?.setType ?? .normal
            },
            set: { type in
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.setType(type, setID: set.id, in: exerciseID)
                }
            }
        )
    }

    private var sideBinding: Binding<SetSide?> {
        Binding(
            get: {
                viewModel.exercises.first { $0.id == exerciseID }?
                    .sets.first { $0.id == set.id }?.side
            },
            set: { viewModel.setSide($0, setID: set.id, in: exerciseID) }
        )
    }

    /// Stays enabled on completed sets, since effort is usually rated right
    /// after finishing. An untouched picker shows the target dimmed and logs
    /// nothing, and so does an implied value.
    private var rirPicker: some View {
        Menu {
            Picker("Reps in reserve", selection: rirBinding) {
                Text("Not logged").tag(Int?.none)
                ForEach(RIRScale.range, id: \.self) { value in
                    Text(value == RIRScale.range.lowerBound ? "\(value) (Failure)" : RIRScale.text(value))
                        .tag(Int?.some(value))
                }
            }
        } label: {
            Text((set.effectiveRIR ?? targetRIR).map { RIRScale.text($0) } ?? "–")
                .font(DesignSystem.Typography.headline)
                .foregroundStyle(set.rir == nil
                                 ? DesignSystem.Colors.textSecondary.opacity(0.6)
                                 : DesignSystem.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.vertical, 6)
                .frame(width: Self.rirWidth)
                .background(DesignSystem.Colors.background)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small))
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Reps in reserve")
        .accessibilityValue(rirSpokenValue)
        .accessibilityHint(targetRIR.map { "Target: \(RIRScale.spokenText($0))" } ?? "")
    }

    private var rirSpokenValue: String {
        if let rir = set.rir { return RIRScale.spokenText(rir) }
        return set.setType.impliedRIR.map { "\(RIRScale.spokenText($0)), implied by the set type" } ?? "Not logged"
    }

    private var rirBinding: Binding<Int?> {
        Binding(
            get: {
                viewModel.exercises.first { $0.id == exerciseID }?
                    .sets.first { $0.id == set.id }?.rir
            },
            set: { viewModel.setRIR($0, setID: set.id, in: exerciseID) }
        )
    }

    private func field(_ binding: Binding<String>, placeholder: String) -> some View {
        TextField(placeholder, text: binding)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.center)
            .font(DesignSystem.Typography.headline)
            .foregroundStyle(set.setType == .warmUp ? DesignSystem.Colors.textSecondary : DesignSystem.Colors.textPrimary)
            .minimumScaleFactor(0.7)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(DesignSystem.Colors.background)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small))
            .disabled(set.isCompleted)
    }

    private func binding(_ keyPath: WritableKeyPath<ActiveSessionViewModel.DraftSet, String>) -> Binding<String> {
        Binding(
            get: {
                guard let e = viewModel.exercises.first(where: { $0.id == exerciseID }),
                      let s = e.sets.first(where: { $0.id == set.id })
                else { return "" }
                return s[keyPath: keyPath]
            },
            set: { newValue in
                guard let e = viewModel.exercises.firstIndex(where: { $0.id == exerciseID }),
                      let s = viewModel.exercises[e].sets.firstIndex(where: { $0.id == set.id })
                else { return }
                viewModel.exercises[e].sets[s][keyPath: keyPath] = newValue
            }
        )
    }
}

// MARK: - Superset bracket

/// Joins a superset's cards in the left gutter. Lives in the row background,
/// which spans the row's insets, so its lines meet across rows.
struct SupersetBracket: View {
    let position: ActiveSessionViewModel.SupersetPosition?

    var body: some View {
        if let position {
            BracketShape(position: position)
                .stroke(DesignSystem.Colors.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .accessibilityHidden(true)
        } else {
            Color.clear
        }
    }

    private struct BracketShape: Shape {
        let position: ActiveSessionViewModel.SupersetPosition

        func path(in rect: CGRect) -> Path {
            let lineX = DesignSystem.Spacing.sm
            let tickEndX = DesignSystem.Spacing.lg
            let tickInset = DesignSystem.Spacing.lg + DesignSystem.Spacing.sm
            var path = Path()
            switch position {
            case .first:
                path.move(to: CGPoint(x: tickEndX, y: rect.minY + tickInset))
                path.addLine(to: CGPoint(x: lineX, y: rect.minY + tickInset))
                path.addLine(to: CGPoint(x: lineX, y: rect.maxY))
            case .middle:
                path.move(to: CGPoint(x: lineX, y: rect.minY))
                path.addLine(to: CGPoint(x: lineX, y: rect.maxY))
            case .last:
                path.move(to: CGPoint(x: lineX, y: rect.minY))
                path.addLine(to: CGPoint(x: lineX, y: rect.maxY - tickInset))
                path.addLine(to: CGPoint(x: tickEndX, y: rect.maxY - tickInset))
            }
            return path
        }
    }
}

#Preview {
    ActiveSessionView(sessionName: "Push", units: .metric, draftStore: nil)
        .modelContainer(for: [WorkoutSession.self, GymProfile.self], inMemory: true)
}
