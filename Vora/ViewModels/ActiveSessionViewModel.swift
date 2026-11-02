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
    let newPRs: [PersonalRecord]
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
        let targets: TemplateTargets?

        var repRange: ClosedRange<Int>? { targets?.repRange }

        /// What the plate calculator loads for this exercise, if it applies.
        /// Custom exercises have no library entry, so no known equipment.
        var plateLoadedEquipment: EquipmentType? {
            exerciseId
                .flatMap { ExerciseLibrary.definition(id: $0) }
                .flatMap { LoadingInventory.plateLoadedEquipment(in: $0.equipment) }
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
    /// Start and active-duration end of the saved workout, for HealthKit.
    private(set) var workoutInterval: DateInterval?
    /// The saved session's ID. nil until `finish` has saved successfully.
    private(set) var savedSessionID: UUID?

    @ObservationIgnored private let health: any HealthWorkoutWriting
    @ObservationIgnored private var draftStore: SessionDraftStore?
    @ObservationIgnored private let draftDebounce: Duration
    @ObservationIgnored private let now: () -> Date
    /// Readable so tests can await the save instead of guessing how long it takes.
    @ObservationIgnored private(set) var pendingDraftSave: Task<Void, Never>?

    init(
        sessionName: String,
        units: UnitSystem = .metric,
        draftStore: SessionDraftStore? = nil,
        draftDebounce: Duration = .milliseconds(500),
        health: any HealthWorkoutWriting = HealthKitService(),
        now: @escaping () -> Date = Date.init
    ) {
        self.sessionName = sessionName
        self.units = units
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
    /// Weights are pre-filled from the most recent session containing the
    /// exercise; reps are left empty so the user consciously enters them.
    /// No-op once exercises exist.
    func prefill(with plan: [TemplateExerciseSpec], context: ModelContext) {
        guard exercises.isEmpty, !plan.isEmpty else { return }

        exercises = plan.map { spec in
            let name = spec.displayName
            let exerciseId = spec.exerciseId
            let previous = Self.previousSets(exerciseId: exerciseId, name: name, context: context)
            let targetSets = TemplateExerciseSpec.Limits.sets.contains(spec.targetSets)
                ? spec.targetSets
                : TemplateExerciseSpec.defaultTargetSets
            let sets = (0..<targetSets).map { index in
                var set = DraftSet(units: units)
                if let reference = index < previous.count ? previous[index] : previous.last {
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
                targets: TemplateTargets(
                    targetSets: targetSets,
                    repRangeMin: spec.repRangeMin,
                    repRangeMax: spec.repRangeMax,
                    targetRIR: spec.targetRIR
                )
            )
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
            return false
        }
        guard let reps = exercises[e].sets[s].reps, reps >= 1,
              exercises[e].sets[s].weightKg != nil
        else { return false }
        exercises[e].sets[s].isCompleted = true
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
        let priorRecords = Dictionary(
            uniqueKeysWithValues: WorkoutHomeViewModel.computePersonalRecords(from: context)
                .map { ($0.id, $0.weightKg) }
        )

        let session = WorkoutSession(
            date: startDate,
            sessionName: sessionName,
            durationSeconds: durationSeconds,
            totalVolumeKg: totalVolumeKg
        )
        context.insert(session)

        var newPRs: [PersonalRecord] = []
        var savedExerciseCount = 0
        var savedSetCount = 0

        for (order, draft) in exercises.enumerated() {
            let completed = draft.sets.filter { $0.isCompleted && $0.weightKg != nil && ($0.reps ?? 0) >= 1 }
            guard !completed.isEmpty else { continue }

            let log = ExerciseLog(
                exerciseName: draft.name,
                exerciseId: draft.exerciseId,
                muscleGroups: draft.muscleGroups,
                orderIndex: order
            )
            session.exercises.append(log)
            savedExerciseCount += 1

            var bestWeight = 0.0
            var bestReps = 0
            for (setIndex, set) in completed.enumerated() {
                let weight = set.weightKg ?? 0
                let reps = set.reps ?? 0
                log.sets.append(SetEntry(
                    setNumber: setIndex + 1,
                    weightKg: weight,
                    reps: reps,
                    isCompleted: true,
                    rir: set.rir
                ))
                savedSetCount += 1
                if weight > bestWeight {
                    bestWeight = weight
                    bestReps = reps
                }
            }

            let key = ExerciseIdentity.key(exerciseId: draft.exerciseId, name: draft.name)
            let prior = priorRecords[key] ?? 0
            if bestWeight > prior, bestWeight > 0 {
                newPRs.append(PersonalRecord(
                    exerciseName: draft.name,
                    weightKg: bestWeight,
                    reps: bestReps,
                    date: startDate,
                    exerciseId: draft.exerciseId
                ))
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

    /// Completed sets from the most recent session that logged the
    /// exercise with at least one completed set. Fetches candidate
    /// sessions newest first, one page at a time, and confirms each match
    /// by identity key so renamed and legacy rows resolve the same way.
    static func previousSets(exerciseId: String?, name: String, context: ModelContext) -> [PreviousSet] {
        let key = ExerciseIdentity.key(exerciseId: exerciseId, name: name)
        var descriptor = ExerciseIdentity.candidateSessions(exerciseId: exerciseId ?? ExerciseIdentity.libraryID(forName: name))
        descriptor.fetchLimit = historyPageSize

        do {
            var offset = 0
            while true {
                descriptor.fetchOffset = offset
                let page = try context.fetch(descriptor)
                for session in page {
                    guard let match = session.exercises.first(where: { $0.matchKey == key }) else { continue }
                    let sets = match.sets
                        .filter(\.isCompleted)
                        .sorted { $0.setNumber < $1.setNumber }
                        .map { PreviousSet(weightKg: $0.weightKg, reps: $0.reps) }
                    if !sets.isEmpty { return sets }
                }
                guard page.count == historyPageSize else { return [] }
                offset += historyPageSize
            }
        } catch {
            logger.error("Failed to fetch exercise history: \(String(describing: error), privacy: .public)")
            return []
        }
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
                        ActiveSessionDraft.Set(weightKg: $0.weightKg, reps: $0.reps, isCompleted: $0.isCompleted, rir: $0.rir)
                    }
                )
            }
        )
    }

    /// Rebuilds a killed session from its draft. Weights show in the
    /// current units and previous sets come from history again. A rest
    /// that ended while the app was gone is dropped. A gap longer than
    /// `interruptionThreshold` between the last save and now is excluded
    /// from the duration; a shorter one counts as continuous.
    func restore(from draft: ActiveSessionDraft, context: ModelContext) {
        let resumedAt = now()
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
                return set
            }
            return DraftExercise(
                name: name,
                exerciseId: saved.exerciseId,
                muscleGroups: saved.muscleGroups,
                sets: sets,
                previousSets: Self.previousSets(exerciseId: saved.exerciseId, name: name, context: context),
                restSeconds: saved.restSeconds,
                targets: saved.targets
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
