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

        /// The recommendation, unless the weight was changed away from it.
        /// A typed weight always wins.
        var activeRecommendation: Recommendation? {
            guard let recommendation, let weightKg,
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
            sets.first { !$0.isCompleted }?.activeRecommendation.flatMap { $0.warnings.isEmpty ? nil : $0 }
        }
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

    let sessionName: String
    let units: UnitSystem
    private(set) var startDate: Date
    /// Interruption time left out of the duration (see `restore`).
    private(set) var excludedSeconds: TimeInterval = 0
    var exercises: [DraftExercise] = [] {
        didSet { scheduleDraftSave() }
    }
    var restEndDate: Date? {
        didSet { scheduleDraftSave() }
    }
    var summary: SessionSummary?
    /// A fix couldn't be saved to the template; it still applies to this session.
    var templateSaveFailed = false
    /// Start and active-duration end of the saved workout, for HealthKit.
    private(set) var workoutInterval: DateInterval?
    /// The saved session's ID. nil until `finish` has saved successfully.
    private(set) var savedSessionID: UUID?

    @ObservationIgnored private let health: any HealthWorkoutWriting
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
        now: @escaping () -> Date = Date.init
    ) {
        self.sessionName = sessionName
        self.units = units
        self.templateSlot = templateSlot
        self.health = health
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
                guard set.isCompleted, let w = set.weightKg, let r = set.reps else { return setTotal }
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
            return DraftExercise(
                name: name,
                exerciseId: exerciseId,
                muscleGroups: exerciseId.flatMap { ExerciseLibrary.definition(id: $0) }
                    .map { [$0.muscleGroup.rawValue] } ?? [],
                sets: sets,
                previousSets: previous,
                restSeconds: spec.restSeconds,
                targets: targets,
                predictedE1RMKg: recommendations.isEmpty ? nil : input.flatMap(ProgressionEngine.predictedE1RM),
                daysSinceLastSession: recommendations.isEmpty ? nil : days,
                loggedLoadsKg: loggedLoads
            )
        }
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
        return recentHistory(exerciseId: exerciseId, name: name, limit: .max, context: context)
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
              let first = exercises[e].sets.first
        else { return }

        var updates: [Recommendation]?
        if first.isCompleted, let weightKg = first.weightKg, let reps = first.reps {
            let plan = exercises[e].sets.compactMap(\.plannedRecommendation)
            updates = ProgressionEngine.retarget(
                plan: plan,
                firstSet: ProgressionSet(weightKg: weightKg, reps: reps, rir: first.rir),
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

        for s in exercises[e].sets.indices.dropFirst() {
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
        saveTemplate: ([TemplateExerciseSpec], TrainingSplit, Int, ModelContext) throws -> Void = {
            try WorkoutTemplateService.save($0, for: $1, dayIndex: $2, context: $3)
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
        for s in exercises[e].sets.indices {
            guard s < recommendations.count, exercises[e].sets[s].recommendation != nil else { continue }
            if exercises[e].sets[s].isCompleted || exercises[e].sets[s].activeRecommendation == nil {
                exercises[e].sets[s].recommendation = recommendations[s]
                exercises[e].sets[s].plannedRecommendation = recommendations[s]
            } else {
                exercises[e].sets[s].apply(recommendations[s], asPlan: true)
            }
        }
    }

    private func saveWidenedRange(
        exerciseIndex e: Int,
        minReps: Int,
        maxReps: Int,
        context: ModelContext,
        saveTemplate: ([TemplateExerciseSpec], TrainingSplit, Int, ModelContext) throws -> Void
    ) {
        guard let slot = templateSlot, let split = TrainingSplit(rawValue: slot.splitRawValue) else { return }
        let key = ExerciseIdentity.key(exerciseId: exercises[e].exerciseId, name: exercises[e].name)
        do {
            var specs = try WorkoutTemplateService.plan(for: split, dayIndex: slot.dayIndex, context: context)
            guard specs.contains(where: { $0.identityKey == key }) else { return }
            for index in specs.indices where specs[index].identityKey == key {
                specs[index].repRangeMin = minReps
                specs[index].repRangeMax = maxReps
            }
            try saveTemplate(specs, split, slot.dayIndex, context)
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
            sets: [firstSet],
            previousSets: previous,
            restSeconds: ExerciseLibrary.defaultRestSeconds(exerciseId: exerciseId),
            targets: nil
        ))
    }

    func removeExercise(_ id: DraftExercise.ID) {
        exercises.removeAll { $0.id == id }
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
            sets: [firstSet],
            previousSets: previous,
            restSeconds: replaced.restSeconds,
            targets: replaced.targets
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
    }

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
        restEndDate = now().addingTimeInterval(duration)
    }

    func cancelRest() {
        restEndDate = nil
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
            savedExerciseCount += 1

            for (setIndex, set) in completed.enumerated() {
                log.sets.append(SetEntry(
                    setNumber: setIndex + 1,
                    weightKg: set.weightKg ?? 0,
                    reps: set.reps ?? 0,
                    isCompleted: true,
                    rir: set.rir
                ))
                savedSetCount += 1
            }

            guard let priorSets else { continue }
            let key = ExerciseIdentity.key(exerciseId: draft.exerciseId, name: draft.name)
            let records = StrengthProgression.newRecords(
                prior: priorSets[key] ?? [],
                session: completed.map { RecordSet(weightKg: $0.weightKg ?? 0, reps: $0.reps ?? 0) }
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

        do {
            try save(context)
            savedSessionID = session.id
            // Only a saved workout may drop the draft; on failure it stays
            // on disk so the work can still be resumed.
            discardDraft()
        } catch {
            Self.logger.error("Failed to save workout session: \(String(describing: error), privacy: .public)")
        }

        workoutInterval = DateInterval(start: startDate, duration: TimeInterval(durationSeconds))
        summary = SessionSummary(
            durationSeconds: durationSeconds,
            totalVolumeKg: totalVolumeKg,
            exerciseCount: savedExerciseCount,
            setCount: savedSetCount,
            newPRs: newPRs
        )
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
    /// completed set, newest first. Fetches candidate sessions newest first,
    /// one page at a time, and confirms each match by identity key so
    /// renamed and legacy rows resolve the same way.
    static func recentHistory(exerciseId: String?, name: String, limit: Int, context: ModelContext) -> [ExerciseHistoryEntry] {
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
                        .filter(\.isCompleted)
                        .sorted { $0.setNumber < $1.setNumber }
                        .map { ProgressionSet(weightKg: $0.weightKg, reps: $0.reps, rir: $0.rir) }
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

    /// Every completed set so far, by exercise identity key. nil when the
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
                let completed = exercise.sets.filter(\.isCompleted).map { RecordSet(weightKg: $0.weightKg, reps: $0.reps) }
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
                            plannedRecommendation: $0.plannedRecommendation
                        )
                    },
                    predictedE1RMKg: exercise.predictedE1RMKg,
                    daysSinceLastSession: exercise.daysSinceLastSession
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
                loggedLoadsKg: progression == nil ? [] : Self.loggedStepLoads(exerciseId: saved.exerciseId, name: name, context: context)
            )
        }
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
