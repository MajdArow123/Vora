//
//  ActiveSessionViewModel.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import Foundation
import Observation
import OSLog
import SwiftData

struct SessionSummary: Identifiable {
    let id = UUID()
    let durationSeconds: Int
    let totalVolumeKg: Double
    let exerciseCount: Int
    let setCount: Int
    let newPRs: [SessionPR]
}

/// A record broken in this session.
struct SessionPR: Identifiable {
    let exerciseName: String
    /// Library ID; nil for custom exercises.
    let exerciseId: String?
    let kind: PersonalRecordKind
    let weightKg: Double
    let reps: Int

    /// Identity key shared by every log of this exercise (see ExerciseIdentity).
    var exerciseKey: String { ExerciseIdentity.key(exerciseId: exerciseId, name: exerciseName) }
    var id: String { "\(exerciseKey)|\(kind.rawValue)" }
    var estimatedOneRepMax: Double { StrengthProgression.epley(weightKg: weightKg, repsToFailure: reps) }
}

/// What the engine needs from the session's setup: nil means "Previous
/// values", where a session starts as it always did.
struct ProgressionContext {
    let mode: ProgressionMode
    let inventory: LoadingInventory?
}

@Observable
final class ActiveSessionViewModel {
    struct DraftSet: Identifiable {
        let id = UUID()
        /// Typed weight in `units`.
        var weightText = ""
        var repsText = ""
        var isCompleted = false
        /// Logged reps in reserve. nil until the user picks one; a template
        /// target is only ever shown as a placeholder.
        var rir: Int?
        var setType = SetType.normal
        var side: SetSide?
        /// What the engine suggests for this set now; retargeting changes it.
        var recommendation: Recommendation?
        /// What it suggested before set 1, to go back to if set 1 is undone.
        var plannedRecommendation: Recommendation?
        let units: UnitSystem
        /// Exact kilograms behind a prefilled `weightText`. Used while the
        /// text is untouched, so display rounding never drifts the value.
        private var source: (text: String, kg: Double)?

        init(units: UnitSystem = .metric) {
            self.units = units
        }

        var weightKg: Double? {
            if let source, source.text == weightText { return source.kg }
            return UnitConversion.parseWeight(weightText, units: units)
        }

        var reps: Int? { Int(repsText) }

        /// Logged RIR, else what the set type implies.
        var effectiveRIR: Int? { setType.effectiveRIR(logged: rir) }

        /// A fresh, incomplete set with this set's weight and reps. RIR is
        /// not copied: effort belongs to the set that was performed.
        func copyingValues() -> DraftSet {
            var copy = DraftSet(units: units)
            copy.weightText = weightText
            copy.repsText = repsText
            copy.source = source
            return copy
        }

        mutating func setWeight(kg: Double) {
            weightText = UnitConversion.weightNumberText(kg: kg, units: units)
            source = (weightText, kg)
        }

        /// The recommendation, unless the weight was changed away from it or
        /// this isn't a working set. A typed weight always wins.
        var activeRecommendation: Recommendation? {
            guard setType.isWorkingSet, let recommendation, let weightKg,
                  abs(weightKg - recommendation.weightKg) < 0.005
            else { return nil }
            return recommendation
        }

        mutating func apply(_ recommendation: Recommendation, asPlan: Bool) {
            self.recommendation = recommendation
            if asPlan { plannedRecommendation = recommendation }
            setWeight(kg: recommendation.weightKg)
        }
    }

    struct PreviousSet {
        let weightKg: Double
        let reps: Int

        func text(units: UnitSystem) -> String {
            "\(UnitConversion.weightNumberText(kg: weightKg, units: units))×\(reps)"
        }
    }

    struct DraftExercise: Identifiable {
        let id = UUID()
        let name: String
        /// Library ID; nil for custom exercises.
        let exerciseId: String?
        let muscleGroups: [String]
        var sets: [DraftSet]
        let previousSets: [PreviousSet]
        /// Rest started after completing one of this exercise's sets.
        let restSeconds: Int
        /// Template targets; nil for exercises added mid-session.
        var targets: TemplateTargets?
        /// The e1RM this session should open near, for retargeting; nil
        /// without a recommendation.
        var predictedE1RMKg: Double?
        var daysSinceLastSession: Int?
        /// Weights ever logged for this exercise on step equipment, which
        /// count as loadable. Read from history, so not kept in the draft.
        var loggedLoadsKg: [Double] = []
        /// Consecutive exercises sharing a number are a superset.
        var supersetGroup: Int?

        var repRange: ClosedRange<Int>? { targets?.repRange }

        /// What the plate calculator loads for this exercise, if it applies.
        /// Custom exercises have no library entry, so no known equipment.
        var plateLoadedEquipment: EquipmentType? {
            exerciseId
                .flatMap { ExerciseLibrary.definition(id: $0) }
                .flatMap { LoadingInventory.plateLoadedEquipment(in: $0.equipment) }
        }

        /// Warnings and fixes the next set to do still carries.
        var activeWarningRecommendation: Recommendation? {
            sets.first { $0.setType.isWorkingSet && !$0.isCompleted }?
                .activeRecommendation.flatMap { $0.warnings.isEmpty ? nil : $0 }
        }

        /// How many working sets come before the set at `index`. History and
        /// recommendations are in working sets, so they line up by this.
        func workingSetOrdinal(at index: Int) -> Int {
            sets[..<index].count { $0.setType.isWorkingSet }
        }

        /// What this set did last time. Only working sets have a counterpart.
        func previousSet(at index: Int) -> PreviousSet? {
            guard sets[index].setType.isWorkingSet else { return nil }
            let ordinal = workingSetOrdinal(at: index)
            return ordinal < previousSets.count ? previousSets[ordinal] : nil
        }

        /// A plate caption shows on the next set to do, whatever its type,
        /// and on the one set whose weight was tapped.
        func showsPlateCaption(for setID: DraftSet.ID, revealed: DraftSet.ID?) -> Bool {
            setID == revealed || setID == nextSetID
        }

        /// The first set not yet completed.
        var nextSetID: DraftSet.ID? {
            sets.first { !$0.isCompleted }?.id
        }

        /// The weight warm-ups ramp up to.
        var firstWorkingWeightKg: Double? {
            sets.first { $0.setType.isWorkingSet }?.weightKg
        }
    }

    /// Where an exercise sits in its superset, for the bracket.
    enum SupersetPosition: Equatable {
        case first, middle, last
    }

    /// Names a set for the plate calculator. It holds no weight on purpose:
    /// a tap can land after the text changed but before the row re-rendered,
    /// so a value captured by the row's button would be out of date. The
    /// sheet reads `plateCalculatorWeightKg(for:)` instead.
    struct PlateCalculatorRequest: Identifiable {
        let setID: DraftSet.ID
        let exerciseID: DraftExercise.ID

        var id: DraftSet.ID { setID }
    }

    private static let logger = Logger(subsystem: "com.majdarow.Vora", category: "Workout")

    /// Sessions fetched per page when looking for an exercise's history.
    static let historyPageSize = 5

    /// An app kill longer than this is left out of the session duration;
    /// shorter ones count as continuous training.
    static let interruptionThreshold: TimeInterval = 5 * 60

    /// What each +/- button on the rest bar changes.
    static let restAdjustmentStep: TimeInterval = 15

    let sessionName: String
    let units: UnitSystem
    private(set) var startDate: Date
    /// Interruption time left out of the duration (see `restore`).
    private(set) var excludedSeconds: TimeInterval = 0
    var exercises: [DraftExercise] = [] {
        didSet {
            scheduleDraftSave()
            syncRestPresentation()
        }
    }
    /// The one source of truth for rest. The bar, Live Activity and rest-over
    /// alert all follow it (see `syncRestPresentation`).
    var restEndDate: Date? {
        didSet {
            scheduleDraftSave()
            syncRestPresentation()
        }
    }
    var summary: SessionSummary?
    /// A fix couldn't be saved to the template; it still applies to this session.
    var templateSaveFailed = false
    /// Start and active-duration end of the saved workout, for HealthKit.
    private(set) var workoutInterval: DateInterval?
    /// The saved session's ID. nil until `finish` has saved successfully.
    private(set) var savedSessionID: UUID?
    /// The gym's loads to build warm-ups from. nil when smart warm-ups are off
    /// or the gym has no inventory yet, and then none are generated.
    var warmUpInventory: LoadingInventory?

    @ObservationIgnored private let health: any HealthWorkoutWriting
    @ObservationIgnored private let restActivity: any RestActivityControlling
    @ObservationIgnored private let restAlert: any RestAlertScheduling
    /// When the current rest began; only the activity's progress reads it, so
    /// it isn't in the draft and a resumed rest counts from the resume.
    @ObservationIgnored private var restStartDate: Date?
    /// The exercise whose set started the current rest, for what's up next.
    @ObservationIgnored private var restExerciseID: DraftExercise.ID?
    /// What the activity and alert were last told; nil when nothing is showing.
    @ObservationIgnored private var presentedRest: RestActivityAttributes.ContentState?
    @ObservationIgnored private var draftStore: SessionDraftStore?
    @ObservationIgnored private let draftDebounce: Duration
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var progression: ProgressionContext?
    @ObservationIgnored private var templateSlot: TemplateSlot?
    /// Readable so tests can await the save instead of guessing how long it takes.
    @ObservationIgnored private(set) var pendingDraftSave: Task<Void, Never>?

    init(
        sessionName: String,
        units: UnitSystem = .metric,
        templateSlot: TemplateSlot? = nil,
        draftStore: SessionDraftStore? = nil,
        draftDebounce: Duration = .milliseconds(500),
        health: any HealthWorkoutWriting = HealthKitService(),
        restActivity: any RestActivityControlling = NoRestActivity(),
        restAlert: any RestAlertScheduling = NoRestAlert(),
        now: @escaping () -> Date = Date.init
    ) {
        self.sessionName = sessionName
        self.units = units
        self.templateSlot = templateSlot
        self.health = health
        self.restActivity = restActivity
        self.restAlert = restAlert
        self.draftStore = draftStore
        self.draftDebounce = draftDebounce
        self.now = now
        self.startDate = now()
    }

    // MARK: - Live stats

    /// Active training time: wall time since start minus excluded
    /// interruptions.
    var elapsedSeconds: Int {
        max(Int(now().timeIntervalSince(startDate) - excludedSeconds), 0)
    }

    var totalVolumeKg: Double {
        exercises.reduce(0) { total, exercise in
            total + exercise.sets.reduce(0) { setTotal, set in
                guard set.isCompleted, set.setType.countsTowardVolume,
                      let w = set.weightKg, let r = set.reps
                else { return setTotal }
                return setTotal + w * Double(r)
            }
        }
    }

    var completedSetCount: Int {
        exercises.reduce(0) { $0 + $1.sets.filter(\.isCompleted).count }
    }

    var canFinish: Bool {
        completedSetCount > 0
    }

    // MARK: - Template pre-population

    /// Loads the split day's template into a fresh session: one exercise
    /// per entry with its target number of empty sets, rest and rep range.
    /// With a progression context and history, each set takes the engine's
    /// weight. Otherwise weights are pre-filled from the most recent session
    /// containing the exercise. Reps are always left empty so the user
    /// consciously enters them, which keeps logged numbers real.
    /// No-op once exercises exist.
    func prefill(with plan: [TemplateExerciseSpec], context: ModelContext, progression: ProgressionContext? = nil) {
        guard exercises.isEmpty, !plan.isEmpty else { return }
        self.progression = progression

        exercises = plan.map { spec in
            let name = spec.displayName
            let exerciseId = spec.exerciseId
            let history = Self.recentHistory(
                exerciseId: exerciseId,
                name: name,
                limit: progression == nil ? 1 : ProgressionEngine.historyLimit,
                context: context
            )
            let previous = (history.first?.sets ?? []).map { PreviousSet(weightKg: $0.weightKg, reps: $0.reps) }
            let targetSets = TemplateExerciseSpec.Limits.sets.contains(spec.targetSets)
                ? spec.targetSets
                : TemplateExerciseSpec.defaultTargetSets
            let targets = TemplateTargets(
                targetSets: targetSets,
                repRangeMin: spec.repRangeMin,
                repRangeMax: spec.repRangeMax,
                targetRIR: spec.targetRIR
            )
            let days = daysSince(history.first?.date)
            let loggedLoads = progression == nil ? [] : Self.loggedStepLoads(exerciseId: exerciseId, name: name, context: context)
            let input = progression.map {
                engineInput(exerciseId: exerciseId, targets: targets, history: history, days: days, loggedLoads: loggedLoads, $0)
            }
            let recommendations = input.map(ProgressionEngine.recommend) ?? []

            let sets = (0..<targetSets).map { index in
                var set = DraftSet(units: units)
                if index < recommendations.count {
                    set.apply(recommendations[index], asPlan: true)
                } else if let reference = index < previous.count ? previous[index] : previous.last {
                    set.setWeight(kg: reference.weightKg)
                }
                return set
            }
            let warmUps = warmUpSets(exerciseId: exerciseId, workingKg: sets.first?.weightKg, loggedLoads: loggedLoads)
            return DraftExercise(
                name: name,
                exerciseId: exerciseId,
                muscleGroups: exerciseId.flatMap { ExerciseLibrary.definition(id: $0) }
                    .map { [$0.muscleGroup.rawValue] } ?? [],
                sets: warmUps + sets,
                previousSets: previous,
                restSeconds: spec.restSeconds,
                targets: targets,
                predictedE1RMKg: recommendations.isEmpty ? nil : input.flatMap(ProgressionEngine.predictedE1RM),
                daysSinceLastSession: recommendations.isEmpty ? nil : days,
                loggedLoadsKg: loggedLoads,
                supersetGroup: spec.supersetGroup
            )
        }
        normalizeSupersets()
    }

    // MARK: - Progression

    private func engineInput(
        exerciseId: String?,
        targets: TemplateTargets,
        history: [ExerciseHistoryEntry],
        days: Int,
        loggedLoads: [Double],
        _ progression: ProgressionContext
    ) -> ProgressionInput {
        ProgressionInput(
            exerciseId: exerciseId,
            targets: targets,
            history: history.map { ProgressionSession(sets: $0.sets, targets: $0.targets) },
            daysSinceLastSession: days,
            equipment: Self.loadEquipment(exerciseId: exerciseId),
            inventory: progression.inventory,
            mode: progression.mode,
            loggedLoadsKg: loggedLoads
        )
    }

    private static func loadEquipment(exerciseId: String?) -> EquipmentType? {
        exerciseId
            .flatMap { ExerciseLibrary.definition(id: $0) }
            .flatMap { LoadingInventory.loadEquipment(in: $0.equipment) }
    }

    /// Every weight logged for the exercise, for step equipment only: plates
    /// stay exact, and an unknown stack has no grid to add them to.
    private static func loggedStepLoads(exerciseId: String?, name: String, context: ModelContext) -> [Double] {
        guard let equipment = loadEquipment(exerciseId: exerciseId), LoadCalculator.usesStepLoads(equipment) else { return [] }
        return recentHistory(exerciseId: exerciseId, name: name, limit: .max, includingAllSetTypes: true, context: context)
            .flatMap { $0.sets.map(\.weightKg) }
    }

    /// Whole calendar days from a date to now; 0 without a date.
    private func daysSince(_ date: Date?) -> Int {
        guard let date else { return 0 }
        let calendar = Calendar.current
        return calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: date),
            to: calendar.startOfDay(for: now())
        ).day ?? 0
    }

    /// Set 1 decides the rest: moves untouched, incomplete sets when it
    /// strayed from the prediction, and back to the plan when it didn't or
    /// was undone. Sets with a typed weight are left alone.
    private func retargetRemainingSets(exerciseIndex e: Int) {
        guard let progression,
              let targets = exercises[e].targets,
              let predicted = exercises[e].predictedE1RMKg,
              let firstIndex = exercises[e].sets.firstIndex(where: { $0.setType.isWorkingSet })
        else { return }
        let first = exercises[e].sets[firstIndex]

        var updates: [Recommendation]?
        if first.isCompleted, let weightKg = first.weightKg, let reps = first.reps {
            let plan = exercises[e].sets.filter(\.setType.isWorkingSet).compactMap(\.plannedRecommendation)
            updates = ProgressionEngine.retarget(
                plan: plan,
                firstSet: ProgressionSet(weightKg: weightKg, reps: reps, rir: first.effectiveRIR),
                predictedE1RMKg: predicted,
                input: engineInput(
                    exerciseId: exercises[e].exerciseId,
                    targets: targets,
                    history: [],
                    days: exercises[e].daysSinceLastSession ?? 0,
                    loggedLoads: exercises[e].loggedLoadsKg,
                    progression
                )
            )
        }

        for s in exercises[e].sets.indices where s > firstIndex && exercises[e].sets[s].setType.isWorkingSet {
            guard !exercises[e].sets[s].isCompleted,
                  exercises[e].sets[s].activeRecommendation != nil,
                  let planned = exercises[e].sets[s].plannedRecommendation
            else { continue }
            let next = updates?.first ?? planned
            guard next != exercises[e].sets[s].recommendation else { continue }
            exercises[e].sets[s].apply(next, asPlan: false)
        }
    }

    /// Applies a one-tap fix. Extending reps lasts this session; widening the
    /// range also saves to the template, and if that fails the session still
    /// gets it. Swapping is the view's: it opens the exercise picker.
    func applyFix(
        _ fix: ProgressionFix,
        exerciseID: DraftExercise.ID,
        context: ModelContext,
        saveTemplate: ([TemplateExerciseSpec], TemplateSlot, ModelContext) throws -> Void = {
            try WorkoutTemplateService.save($0, for: $1, context: $2)
        }
    ) {
        guard let e = exercises.firstIndex(where: { $0.id == exerciseID }) else { return }
        switch fix {
        case .extendReps(let reps):
            for s in exercises[e].sets.indices {
                guard let current = exercises[e].sets[s].recommendation else { continue }
                let extended = ProgressionEngine.extendingReps(current, toReps: reps)
                exercises[e].sets[s].recommendation = extended
                exercises[e].sets[s].plannedRecommendation = extended
            }
        case .widenRange(let minReps, let maxReps):
            widenRange(exerciseIndex: e, minReps: minReps, maxReps: maxReps, context: context)
            saveWidenedRange(exerciseIndex: e, minReps: minReps, maxReps: maxReps, context: context, saveTemplate: saveTemplate)
        case .swapExercise:
            break
        }
    }

    private func widenRange(exerciseIndex e: Int, minReps: Int, maxReps: Int, context: ModelContext) {
        guard var targets = exercises[e].targets else { return }
        targets.repRangeMin = minReps
        targets.repRangeMax = maxReps
        exercises[e].targets = targets
        guard let progression else { return }

        // The last session counts as done under the widened range: this is
        // the same plan with more room, not a new one to re-baseline to.
        var history = Self.recentHistory(
            exerciseId: exercises[e].exerciseId,
            name: exercises[e].name,
            limit: ProgressionEngine.historyLimit,
            context: context
        )
        if !history.isEmpty { history[0].targets = targets }
        let recommendations = ProgressionEngine.recommend(engineInput(
            exerciseId: exercises[e].exerciseId,
            targets: targets,
            history: history,
            days: exercises[e].daysSinceLastSession ?? 0,
            loggedLoads: exercises[e].loggedLoadsKg,
            progression
        ))
        for s in exercises[e].sets.indices where exercises[e].sets[s].setType.isWorkingSet {
            let ordinal = exercises[e].workingSetOrdinal(at: s)
            guard ordinal < recommendations.count, exercises[e].sets[s].recommendation != nil else { continue }
            let recommendation = recommendations[ordinal]
            if exercises[e].sets[s].isCompleted || exercises[e].sets[s].activeRecommendation == nil {
                exercises[e].sets[s].recommendation = recommendation
                exercises[e].sets[s].plannedRecommendation = recommendation
            } else {
                exercises[e].sets[s].apply(recommendation, asPlan: true)
            }
        }
    }

    private func saveWidenedRange(
        exerciseIndex e: Int,
        minReps: Int,
        maxReps: Int,
        context: ModelContext,
        saveTemplate: ([TemplateExerciseSpec], TemplateSlot, ModelContext) throws -> Void
    ) {
        guard let slot = templateSlot else { return }
        let key = ExerciseIdentity.key(exerciseId: exercises[e].exerciseId, name: exercises[e].name)
        do {
            var specs = try WorkoutTemplateService.plan(for: slot, context: context)
            guard specs.contains(where: { $0.identityKey == key }) else { return }
            for index in specs.indices where specs[index].identityKey == key {
                specs[index].repRangeMin = minReps
                specs[index].repRangeMax = maxReps
            }
            try saveTemplate(specs, slot, context)
        } catch {
            Self.logger.error("Failed to save the widened range: \(String(describing: error), privacy: .public)")
            templateSaveFailed = true
        }
    }

    // MARK: - Exercise management

    func addExercise(name: String, muscleGroups: [String], context: ModelContext) {
        let exerciseId = ExerciseIdentity.libraryID(forName: name)
        let previous = Self.previousSets(exerciseId: exerciseId, name: name, context: context)
        var firstSet = DraftSet(units: units)
        if let first = previous.first {
            firstSet.setWeight(kg: first.weightKg)
            firstSet.repsText = String(first.reps)
        }
        exercises.append(DraftExercise(
            name: name,
            exerciseId: exerciseId,
            muscleGroups: muscleGroups,
            sets: warmUpSets(exerciseId: exerciseId, workingKg: firstSet.weightKg, loggedLoads: []) + [firstSet],
            previousSets: previous,
            restSeconds: ExerciseLibrary.defaultRestSeconds(exerciseId: exerciseId),
            targets: nil
        ))
    }

    func removeExercise(_ id: DraftExercise.ID) {
        exercises.removeAll { $0.id == id }
        normalizeSupersets()
    }

    /// Swaps an exercise for another in place, keeping its slot in the
    /// session order. Entered sets on the old exercise are discarded; the
    /// replacement starts with one set like a freshly added exercise but
    /// keeps the slot's rest and rep range.
    func replaceExercise(
        _ id: DraftExercise.ID,
        withName name: String,
        muscleGroups: [String],
        context: ModelContext
    ) {
        guard let index = exercises.firstIndex(where: { $0.id == id }) else { return }
        let exerciseId = ExerciseIdentity.libraryID(forName: name)
        let previous = Self.previousSets(exerciseId: exerciseId, name: name, context: context)
        var firstSet = DraftSet(units: units)
        if let first = previous.first {
            firstSet.setWeight(kg: first.weightKg)
            firstSet.repsText = String(first.reps)
        }
        let replaced = exercises[index]
        exercises[index] = DraftExercise(
            name: name,
            exerciseId: exerciseId,
            muscleGroups: muscleGroups,
            sets: warmUpSets(exerciseId: exerciseId, workingKg: firstSet.weightKg, loggedLoads: []) + [firstSet],
            previousSets: previous,
            restSeconds: replaced.restSeconds,
            targets: replaced.targets,
            supersetGroup: replaced.supersetGroup
        )
    }

    /// Matches SwiftUI's move(fromOffsets:toOffset:) semantics, where the
    /// destination is an index into the pre-removal array. Implemented by
    /// hand so this view model stays SwiftUI-free.
    func moveExercise(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        let moving = offsets.sorted(by: >).compactMap { index in
            exercises.indices.contains(index) ? exercises.remove(at: index) : nil
        }.reversed()
        let insertAt = destination - offsets.count(where: { $0 < destination })
        exercises.insert(contentsOf: moving, at: insertAt)
        normalizeSupersets()
    }

    // MARK: - Supersets

    /// Links an exercise with the one after it. If either is already in a
    /// superset, the other joins it, and two supersets merge.
    func linkWithNext(_ id: DraftExercise.ID) {
        guard let e = exercises.firstIndex(where: { $0.id == id }), e + 1 < exercises.count else { return }
        assignSupersetGroups(SetCounting.linkingWithNext(exercises.map(\.supersetGroup), at: e))
    }

    /// Takes one exercise out of its superset. Leaving from the middle splits
    /// it, and any exercise left alone loses its link.
    func unlinkFromSuperset(_ id: DraftExercise.ID) {
        guard let e = exercises.firstIndex(where: { $0.id == id }) else { return }
        assignSupersetGroups(SetCounting.unlinking(exercises.map(\.supersetGroup), at: e))
    }

    func supersetPosition(of id: DraftExercise.ID) -> SupersetPosition? {
        guard let e = exercises.firstIndex(where: { $0.id == id }) else { return nil }
        return Self.supersetPosition(in: exercises.map(\.supersetGroup), at: e)
    }

    /// Where an exercise sits in its superset, for the bracket in the session
    /// and the template editor.
    static func supersetPosition(in groups: [Int?], at e: Int) -> SupersetPosition? {
        guard let group = groups[e] else { return nil }
        let linkedBefore = e > 0 && groups[e - 1] == group
        let linkedAfter = e + 1 < groups.count && groups[e + 1] == group
        switch (linkedBefore, linkedAfter) {
        case (false, true): return .first
        case (true, true): return .middle
        case (true, false): return .last
        case (false, false): return nil
        }
    }

    private func normalizeSupersets() {
        assignSupersetGroups(SetCounting.normalizedSupersetGroups(exercises.map(\.supersetGroup)))
    }

    private func assignSupersetGroups(_ groups: [Int?]) {
        for index in exercises.indices where exercises[index].supersetGroup != groups[index] {
            exercises[index].supersetGroup = groups[index]
        }
    }

    // MARK: - Warm-ups

    private func warmUpSets(exerciseId: String?, workingKg: Double?, loggedLoads: [Double]) -> [DraftSet] {
        // Custom exercises have no known mechanics or equipment, so get none.
        guard let warmUpInventory, let workingKg,
              let definition = exerciseId.flatMap({ ExerciseLibrary.definition(id: $0) }),
              let equipment = LoadingInventory.loadEquipment(in: definition.equipment)
        else { return [] }
        return WarmUpGenerator.sets(
            workingKg: workingKg,
            mechanics: definition.mechanics,
            equipment: equipment,
            inventory: warmUpInventory,
            loggedKg: loggedLoads
        ).map { warmUp in
            var set = DraftSet(units: units)
            set.setType = .warmUp
            set.setWeight(kg: warmUp.weightKg)
            // Filled in, unlike working sets: a warm-up counts toward nothing,
            // so one tap should be enough.
            set.repsText = String(warmUp.reps)
            return set
        }
    }

    private func suggestedWarmUps(for exercise: DraftExercise) -> [DraftSet] {
        guard !exercise.sets.contains(where: { $0.setType == .warmUp }) else { return [] }
        return warmUpSets(
            exerciseId: exercise.exerciseId,
            workingKg: exercise.firstWorkingWeightKg,
            loggedLoads: exercise.loggedLoadsKg
        )
    }

    /// Whether warm-ups can be added now: an exercise with no weight when the
    /// session opened has none until one is typed, and a deleted ramp can be
    /// rebuilt from the current weight.
    func canAddWarmUps(to exerciseID: DraftExercise.ID) -> Bool {
        guard let exercise = exercises.first(where: { $0.id == exerciseID }) else { return false }
        return !suggestedWarmUps(for: exercise).isEmpty
    }

    func addWarmUps(to exerciseID: DraftExercise.ID) {
        guard let e = exercises.firstIndex(where: { $0.id == exerciseID }) else { return }
        exercises[e].sets.insert(contentsOf: suggestedWarmUps(for: exercises[e]), at: 0)
    }

    // MARK: - Set types

    func addSet(to exerciseID: DraftExercise.ID) {
        guard let index = exercises.firstIndex(where: { $0.id == exerciseID }) else { return }
        var newSet = DraftSet(units: units)
        if let last = exercises[index].sets.last {
            // Copies the exact kg too, so an untouched prefill stays exact.
            newSet = last.copyingValues()
        }
        exercises[index].sets.append(newSet)
    }

    func removeSet(_ setID: DraftSet.ID, from exerciseID: DraftExercise.ID) {
        guard let index = exercises.firstIndex(where: { $0.id == exerciseID }) else { return }
        exercises[index].sets.removeAll { $0.id == setID }
    }

    /// Changes a set's type. Warm-ups always sit above working sets, so a set
    /// entering or leaving the warm-ups moves to the boundary between them.
    func setType(_ type: SetType, setID: DraftSet.ID, in exerciseID: DraftExercise.ID) {
        guard let e = exercises.firstIndex(where: { $0.id == exerciseID }),
              let s = exercises[e].sets.firstIndex(where: { $0.id == setID })
        else { return }
        let old = exercises[e].sets[s].setType
        guard old != type else { return }
        exercises[e].sets[s].setType = type
        if (old == .warmUp) != (type == .warmUp) {
            let moved = exercises[e].sets.remove(at: s)
            let boundary = exercises[e].sets.firstIndex { $0.setType != .warmUp } ?? exercises[e].sets.count
            exercises[e].sets.insert(moved, at: boundary)
        }
        retargetRemainingSets(exerciseIndex: e)
    }

    func setSide(_ side: SetSide?, setID: DraftSet.ID, in exerciseID: DraftExercise.ID) {
        guard let e = exercises.firstIndex(where: { $0.id == exerciseID }),
              let s = exercises[e].sets.firstIndex(where: { $0.id == setID })
        else { return }
        exercises[e].sets[s].side = side
    }

    /// Toggles completion. Completing requires parseable reps ≥ 1
    /// (weight 0 is valid for bodyweight work). Returns true when the
    /// set transitioned to completed, so the view can start the rest timer.
    func toggleCompletion(setID: DraftSet.ID, in exerciseID: DraftExercise.ID) -> Bool {
        guard let e = exercises.firstIndex(where: { $0.id == exerciseID }),
              let s = exercises[e].sets.firstIndex(where: { $0.id == setID })
        else { return false }

        if exercises[e].sets[s].isCompleted {
            exercises[e].sets[s].isCompleted = false
            retargetRemainingSets(exerciseIndex: e)
            return false
        }
        guard let reps = exercises[e].sets[s].reps, reps >= 1,
              exercises[e].sets[s].weightKg != nil
        else { return false }
        exercises[e].sets[s].isCompleted = true
        retargetRemainingSets(exerciseIndex: e)
        return true
    }

    /// Logs reps in reserve, or clears it with nil. Independent of
    /// completion, so it can be set before or after finishing the set.
    /// Values off the scale are ignored.
    func setRIR(_ rir: Int?, setID: DraftSet.ID, in exerciseID: DraftExercise.ID) {
        guard rir == nil || RIRScale.validated(rir) != nil,
              let e = exercises.firstIndex(where: { $0.id == exerciseID }),
              let s = exercises[e].sets.firstIndex(where: { $0.id == setID })
        else { return }
        exercises[e].sets[s].rir = rir
        retargetRemainingSets(exerciseIndex: e)
    }

    // MARK: - Rest timer

    /// The set's current weight, or nil if it has none or no longer exists.
    func plateCalculatorWeightKg(for request: PlateCalculatorRequest) -> Double? {
        exercises.first { $0.id == request.exerciseID }?
            .sets.first { $0.id == request.setID }?
            .weightKg
    }

    func startRest(duration: TimeInterval) {
        let start = now()
        restStartDate = start
        restEndDate = start.addingTimeInterval(duration)
    }

    /// Starts the exercise's rest after a set, unless the next thing to do
    /// follows without one: warm-ups run straight on, drop and myo-rep sets
    /// follow immediately, and a superset rests only once a round is done.
    func startRestIfDue(afterCompleting setID: DraftSet.ID, in exerciseID: DraftExercise.ID) {
        guard let e = exercises.firstIndex(where: { $0.id == exerciseID }),
              let s = exercises[e].sets.firstIndex(where: { $0.id == setID }),
              exercises[e].sets[s].setType != .warmUp
        else { return }
        if s + 1 < exercises[e].sets.count {
            let next = exercises[e].sets[s + 1].setType
            if next == .drop || next == .myoRep { return }
        }
        if let group = exercises[e].supersetGroup {
            let laterInSuperset = exercises[(e + 1)...].prefix { $0.supersetGroup == group }
            if laterInSuperset.contains(where: { $0.sets.contains { !$0.isCompleted } }) { return }
        }
        restExerciseID = exerciseID
        startRest(duration: TimeInterval(exercises[e].restSeconds))
    }

    func cancelRest() {
        restEndDate = nil
    }

    /// Adds or takes off time. Taking off all that's left ends the rest.
    func adjustRest(by seconds: TimeInterval) {
        guard let end = restEndDate else { return }
        let adjusted = end.addingTimeInterval(seconds)
        restEndDate = adjusted > now() ? adjusted : nil
    }

    /// Ends a rest that ran out while the app was suspended and couldn't.
    func reconcileRest() {
        if let end = restEndDate, end <= now() {
            restEndDate = nil
        }
    }

    /// Keeps the draft, rest included, so "Resume workout" can pick the rest
    /// up. The alert stays pending for the same reason; only the activity,
    /// which nothing would be left to end, goes.
    func prepareForTermination() {
        flushDraft()
        restActivity.endAllBeforeTermination()
    }

    /// Brings the activity and alert in line with the rest state. Called on
    /// every change to it or to the sets, and does nothing unless what they
    /// show changed, so typing in another set sends nothing.
    private func syncRestPresentation() {
        guard let end = restEndDate else {
            guard presentedRest != nil else { return }
            presentedRest = nil
            restStartDate = nil
            restExerciseID = nil
            restActivity.end()
            restAlert.cancel()
            return
        }
        let upNext = RestUpNext.resolve(
            exercises: exercises,
            restedAfter: restExerciseID,
            units: units,
            fallbackName: sessionName
        )
        let state = RestActivityAttributes.ContentState(
            exerciseName: upNext.exerciseName,
            nextSetText: upNext.setText,
            startDate: restStartDate ?? now(),
            endDate: end
        )
        guard state != presentedRest else { return }
        presentedRest = state
        restActivity.show(state)
        restAlert.schedule(at: end, body: upNext.notificationBody)
    }

    // MARK: - Finish

    /// Persists completed work, detects new PRs against prior history,
    /// and produces the summary. Exercises with no completed sets are
    /// dropped; incomplete sets are not saved. `save` is injectable so
    /// tests can simulate a failed save.
    func finish(
        context: ModelContext,
        save: (ModelContext) throws -> Void = { try $0.save() }
    ) {
        let durationSeconds = elapsedSeconds
        let priorSets = Self.priorRecordSets(context: context)

        let session = WorkoutSession(
            date: startDate,
            sessionName: sessionName,
            durationSeconds: durationSeconds,
            totalVolumeKg: totalVolumeKg
        )
        context.insert(session)

        var newPRs: [SessionPR] = []
        var savedExerciseCount = 0
        var savedSetCount = 0
        var savedLogs: [(log: ExerciseLog, group: Int?)] = []

        for (order, draft) in exercises.enumerated() {
            let completed = draft.sets.filter { $0.isCompleted && $0.weightKg != nil && ($0.reps ?? 0) >= 1 }
            guard !completed.isEmpty else { continue }

            let log = ExerciseLog(
                exerciseName: draft.name,
                exerciseId: draft.exerciseId,
                muscleGroups: draft.muscleGroups,
                orderIndex: order,
                targets: draft.targets
            )
            session.exercises.append(log)
            savedLogs.append((log, draft.supersetGroup))
            savedExerciseCount += 1

            for (setIndex, set) in completed.enumerated() {
                log.sets.append(SetEntry(
                    setNumber: setIndex + 1,
                    weightKg: set.weightKg ?? 0,
                    reps: set.reps ?? 0,
                    isCompleted: true,
                    rir: set.rir,
                    setType: set.setType,
                    side: set.side
                ))
                if set.setType.countsAsTrainingSet { savedSetCount += 1 }
            }

            guard let priorSets else { continue }
            let key = ExerciseIdentity.key(exerciseId: draft.exerciseId, name: draft.name)
            let records = StrengthProgression.newRecords(
                prior: priorSets[key] ?? [],
                session: completed.filter(\.setType.countsTowardRecords).map {
                    RecordSet(weightKg: $0.weightKg ?? 0, reps: $0.reps ?? 0)
                }
            )
            newPRs += records.map {
                SessionPR(
                    exerciseName: draft.name,
                    exerciseId: draft.exerciseId,
                    kind: $0.kind,
                    weightKg: $0.weightKg,
                    reps: $0.reps
                )
            }
        }

        // Exercises with nothing completed aren't saved, which can leave a
        // superset with one exercise.
        let groups = SetCounting.normalizedSupersetGroups(savedLogs.map(\.group))
        for (saved, group) in zip(savedLogs, groups) {
            saved.log.supersetGroup = group
        }

        let cycleAdvance = savedSetCount > 0 ? recordCycleFinish(context: context) : nil

        do {
            try save(context)
            savedSessionID = session.id
            // Only a saved workout may drop the draft; on failure it stays
            // on disk so the work can still be resumed.
            discardDraft()
        } catch {
            Self.logger.error("Failed to save workout session: \(String(describing: error), privacy: .public)")
            cycleAdvance?.undo()
        }
        // The session screen goes away with the summary, saved or not.
        restEndDate = nil

        workoutInterval = DateInterval(start: startDate, duration: TimeInterval(durationSeconds))
        summary = SessionSummary(
            durationSeconds: durationSeconds,
            totalVolumeKg: totalVolumeKg,
            exerciseCount: savedExerciseCount,
            setCount: savedSetCount,
            newPRs: newPRs
        )
    }

    /// Moves the cycle past this session's day, to be saved with the session.
    /// A failed read costs only the advance: the workout still saves.
    private func recordCycleFinish(context: ModelContext) -> CycleAdvance? {
        guard let dayID = templateSlot?.cycleDayID else { return nil }
        do {
            return try TrainingProgramService.recordFinish(dayID: dayID, context: context, now: now())
        } catch {
            Self.logger.error("Failed to advance the training cycle: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Writes the saved workout to HealthKit and stores its ID on the
    /// session, so deleting it later can target that exact workout. Does
    /// nothing if the local save failed: there is no row to link, and
    /// resuming the draft would write a second workout.
    func recordHealthWorkout(context: ModelContext) async {
        guard let sessionID = savedSessionID, let interval = workoutInterval,
              let workoutID = await health.saveStrengthWorkout(start: interval.start, end: interval.end)
        else { return }

        do {
            let descriptor = FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.id == sessionID })
            guard let session = try context.fetch(descriptor).first else {
                Self.logger.notice("Workout was deleted before its HealthKit ID could be stored")
                return
            }
            session.healthKitWorkoutID = workoutID
            try context.save()
        } catch {
            Self.logger.error("Failed to store HealthKit workout ID: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Previous session reference

    /// One past session of an exercise, in plain values.
    struct ExerciseHistoryEntry {
        let date: Date
        let sets: [ProgressionSet]
        var targets: TemplateTargets?
    }

    /// Completed sets from the most recent session that logged the
    /// exercise with at least one completed set.
    static func previousSets(exerciseId: String?, name: String, context: ModelContext) -> [PreviousSet] {
        (recentHistory(exerciseId: exerciseId, name: name, limit: 1, context: context).first?.sets ?? [])
            .map { PreviousSet(weightKg: $0.weightKg, reps: $0.reps) }
    }

    /// The most recent sessions that logged the exercise with at least one
    /// completed working set, newest first, in working sets only (failure sets
    /// carry their implied RIR). With `includingAllSetTypes`, every completed
    /// set counts, for what has been lifted rather than how. Fetches candidate sessions newest first,
    /// one page at a time, and confirms each match by identity key so
    /// renamed and legacy rows resolve the same way.
    static func recentHistory(
        exerciseId: String?,
        name: String,
        limit: Int,
        includingAllSetTypes: Bool = false,
        context: ModelContext
    ) -> [ExerciseHistoryEntry] {
        let key = ExerciseIdentity.key(exerciseId: exerciseId, name: name)
        var descriptor = ExerciseIdentity.candidateSessions(exerciseId: exerciseId ?? ExerciseIdentity.libraryID(forName: name))
        descriptor.fetchLimit = historyPageSize

        do {
            var found: [ExerciseHistoryEntry] = []
            var offset = 0
            while true {
                descriptor.fetchOffset = offset
                let page = try context.fetch(descriptor)
                for session in page {
                    guard let match = session.exercises.first(where: { $0.matchKey == key }) else { continue }
                    let sets = match.sets
                        .filter { $0.isCompleted && (includingAllSetTypes || $0.setType.isWorkingSet) }
                        .sorted { $0.setNumber < $1.setNumber }
                        .map { ProgressionSet(weightKg: $0.weightKg, reps: $0.reps, rir: $0.effectiveRIR) }
                    guard !sets.isEmpty else { continue }
                    found.append(ExerciseHistoryEntry(date: session.date, sets: sets, targets: match.targetSnapshot))
                    if found.count == limit { return found }
                }
                guard page.count == historyPageSize else { return found }
                offset += historyPageSize
            }
        } catch {
            logger.error("Failed to fetch exercise history: \(String(describing: error), privacy: .public)")
            return []
        }
    }

    /// Every set that can set a record so far, by exercise identity key. nil when the
    /// history can't be read: no comparison is better than calling everything
    /// a record.
    private static func priorRecordSets(context: ModelContext) -> [String: [RecordSet]]? {
        let sessions: [WorkoutSession]
        do {
            sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        } catch {
            logger.error("Failed to fetch history for records: \(String(describing: error), privacy: .public)")
            return nil
        }
        var sets: [String: [RecordSet]] = [:]
        for session in sessions {
            for exercise in session.exercises {
                let completed = exercise.sets
                    .filter { $0.isCompleted && $0.setType.countsTowardRecords }
                    .map { RecordSet(weightKg: $0.weightKg, reps: $0.reps) }
                sets[exercise.matchKey, default: []] += completed
            }
        }
        return sets
    }

    // MARK: - Draft persistence

    /// The session as a Codable snapshot, weights in kilograms.
    func snapshot() -> ActiveSessionDraft {
        ActiveSessionDraft(
            sessionName: sessionName,
            startDate: startDate,
            savedAt: now(),
            restEndDate: restEndDate,
            excludedSeconds: excludedSeconds,
            exercises: exercises.map { exercise in
                ActiveSessionDraft.Exercise(
                    exerciseId: exercise.exerciseId,
                    customName: exercise.exerciseId == nil ? exercise.name : nil,
                    muscleGroups: exercise.muscleGroups,
                    restSeconds: exercise.restSeconds,
                    targets: exercise.targets,
                    sets: exercise.sets.map {
                        ActiveSessionDraft.Set(
                            weightKg: $0.weightKg,
                            reps: $0.reps,
                            isCompleted: $0.isCompleted,
                            rir: $0.rir,
                            recommendation: $0.recommendation,
                            plannedRecommendation: $0.plannedRecommendation,
                            setType: $0.setType == .normal ? nil : $0.setType,
                            side: $0.side
                        )
                    },
                    predictedE1RMKg: exercise.predictedE1RMKg,
                    daysSinceLastSession: exercise.daysSinceLastSession,
                    supersetGroup: exercise.supersetGroup
                )
            },
            templateSlot: templateSlot
        )
    }

    /// Rebuilds a killed session from its draft. Weights show in the
    /// current units and previous sets come from history again. A rest
    /// that ended while the app was gone is dropped. A gap longer than
    /// `interruptionThreshold` between the last save and now is excluded
    /// from the duration; a shorter one counts as continuous.
    func restore(from draft: ActiveSessionDraft, context: ModelContext, progression: ProgressionContext? = nil) {
        let resumedAt = now()
        self.progression = progression
        templateSlot = draft.templateSlot
        startDate = draft.startDate
        let gap = resumedAt.timeIntervalSince(draft.savedAt)
        excludedSeconds = draft.excludedSeconds + (gap > Self.interruptionThreshold ? gap : 0)

        exercises = draft.exercises.map { saved in
            let name = TemplateExerciseSpec.displayName(exerciseId: saved.exerciseId, customName: saved.customName)
            let sets = saved.sets.map { savedSet in
                var set = DraftSet(units: units)
                if let weightKg = savedSet.weightKg {
                    set.setWeight(kg: weightKg)
                }
                set.repsText = savedSet.reps.map(String.init) ?? ""
                set.isCompleted = savedSet.isCompleted
                set.rir = RIRScale.validated(savedSet.rir)
                set.recommendation = savedSet.recommendation
                set.plannedRecommendation = savedSet.plannedRecommendation
                set.setType = savedSet.setType ?? .normal
                set.side = savedSet.side
                return set
            }
            return DraftExercise(
                name: name,
                exerciseId: saved.exerciseId,
                muscleGroups: saved.muscleGroups,
                sets: sets,
                previousSets: Self.previousSets(exerciseId: saved.exerciseId, name: name, context: context),
                restSeconds: saved.restSeconds,
                targets: saved.targets,
                predictedE1RMKg: saved.predictedE1RMKg,
                daysSinceLastSession: saved.daysSinceLastSession,
                loggedLoadsKg: progression == nil ? [] : Self.loggedStepLoads(exerciseId: saved.exerciseId, name: name, context: context),
                supersetGroup: saved.supersetGroup
            )
        }
        restStartDate = resumedAt
        restEndDate = draft.restEndDate.flatMap { $0 > resumedAt ? $0 : nil }
    }

    /// Writes the draft now, skipping the debounce (e.g. when the app
    /// moves to the background).
    func flushDraft() {
        pendingDraftSave?.cancel()
        pendingDraftSave = nil
        writeDraft()
    }

    /// Stops autosaving and deletes the draft (finished or discarded).
    func discardDraft() {
        pendingDraftSave?.cancel()
        pendingDraftSave = nil
        draftStore?.clear()
        draftStore = nil
        restEndDate = nil
    }

    private func scheduleDraftSave() {
        guard draftStore != nil else { return }
        pendingDraftSave?.cancel()
        let delay = draftDebounce
        pendingDraftSave = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return  // Cancelled by a newer change.
            }
            self?.pendingDraftSave = nil
            self?.writeDraft()
        }
    }

    private func writeDraft() {
        guard let draftStore else { return }
        do {
            try draftStore.save(snapshot())
        } catch {
            Self.logger.error("Failed to save session draft: \(String(describing: error), privacy: .public)")
        }
    }
}
