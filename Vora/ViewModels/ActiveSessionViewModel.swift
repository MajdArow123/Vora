//
//  ActiveSessionViewModel.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import Foundation
import Observation
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
        var weightText = ""
        var repsText = ""
        var isCompleted = false

        var weightKg: Double? { Double(weightText.replacingOccurrences(of: ",", with: ".")) }
        var reps: Int? { Int(repsText) }
    }

    struct PreviousSet {
        let weightKg: Double
        let reps: Int

        var text: String {
            let weight = weightKg.truncatingRemainder(dividingBy: 1) == 0
                ? String(Int(weightKg))
                : String(format: "%.1f", weightKg)
            return "\(weight)×\(reps)"
        }
    }

    struct DraftExercise: Identifiable {
        let id = UUID()
        let name: String
        let muscleGroups: [String]
        var sets: [DraftSet]
        let previousSets: [PreviousSet]
    }

    let sessionName: String
    let startDate = Date.now
    var exercises: [DraftExercise] = []
    var restEndDate: Date?
    var summary: SessionSummary?

    init(sessionName: String) {
        self.sessionName = sessionName
    }

    // MARK: - Live stats

    var elapsedSeconds: Int {
        max(Int(Date.now.timeIntervalSince(startDate)), 0)
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
    /// per name with 4 empty sets. Weights are pre-filled from the most
    /// recent session containing the exercise; reps are left empty so the
    /// user consciously enters them. No-op once exercises exist.
    func prefill(with names: [String], context: ModelContext) {
        guard exercises.isEmpty, !names.isEmpty else { return }

        exercises = names.map { name in
            let previous = Self.previousSets(for: name, context: context)
            let sets = (0..<4).map { index in
                var set = DraftSet()
                if let reference = index < previous.count ? previous[index] : previous.last {
                    set.weightText = Self.weightString(reference.weightKg)
                }
                return set
            }
            return DraftExercise(
                name: name,
                muscleGroups: ExerciseLibrary.definition(named: name)
                    .map { [$0.muscleGroup.rawValue] } ?? [],
                sets: sets,
                previousSets: previous
            )
        }
    }

    // MARK: - Exercise management

    func addExercise(name: String, muscleGroups: [String], context: ModelContext) {
        let previous = Self.previousSets(for: name, context: context)
        var firstSet = DraftSet()
        if let first = previous.first {
            firstSet.weightText = Self.weightString(first.weightKg)
            firstSet.repsText = String(first.reps)
        }
        exercises.append(DraftExercise(
            name: name,
            muscleGroups: muscleGroups,
            sets: [firstSet],
            previousSets: previous
        ))
    }

    func removeExercise(_ id: DraftExercise.ID) {
        exercises.removeAll { $0.id == id }
    }

    /// Swaps an exercise for another in place, keeping its slot in the
    /// session order. Entered sets on the old exercise are discarded; the
    /// replacement starts like a freshly added exercise.
    func replaceExercise(
        _ id: DraftExercise.ID,
        withName name: String,
        muscleGroups: [String],
        context: ModelContext
    ) {
        guard let index = exercises.firstIndex(where: { $0.id == id }) else { return }
        let previous = Self.previousSets(for: name, context: context)
        var firstSet = DraftSet()
        if let first = previous.first {
            firstSet.weightText = Self.weightString(first.weightKg)
            firstSet.repsText = String(first.reps)
        }
        exercises[index] = DraftExercise(
            name: name,
            muscleGroups: muscleGroups,
            sets: [firstSet],
            previousSets: previous
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
        var newSet = DraftSet()
        if let last = exercises[index].sets.last {
            newSet.weightText = last.weightText
            newSet.repsText = last.repsText
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

    // MARK: - Rest timer

    func startRest(duration: TimeInterval) {
        restEndDate = Date.now.addingTimeInterval(duration)
    }

    func cancelRest() {
        restEndDate = nil
    }

    // MARK: - Finish

    /// Persists completed work, detects new PRs against prior history,
    /// and produces the summary. Exercises with no completed sets are
    /// dropped; incomplete sets are not saved.
    func finish(context: ModelContext) {
        let priorRecords = Dictionary(
            uniqueKeysWithValues: WorkoutHomeViewModel.computePersonalRecords(from: context)
                .map { ($0.exerciseName.lowercased(), $0.weightKg) }
        )

        let session = WorkoutSession(
            date: startDate,
            sessionName: sessionName,
            durationSeconds: elapsedSeconds,
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
                    isCompleted: true
                ))
                savedSetCount += 1
                if weight > bestWeight {
                    bestWeight = weight
                    bestReps = reps
                }
            }

            let prior = priorRecords[draft.name.lowercased()] ?? 0
            if bestWeight > prior, bestWeight > 0 {
                newPRs.append(PersonalRecord(
                    exerciseName: draft.name,
                    weightKg: bestWeight,
                    reps: bestReps,
                    date: startDate
                ))
            }
        }

        do {
            try context.save()
        } catch {
            assertionFailure("Failed to save workout session: \(error)")
        }

        summary = SessionSummary(
            durationSeconds: elapsedSeconds,
            totalVolumeKg: totalVolumeKg,
            exerciseCount: savedExerciseCount,
            setCount: savedSetCount,
            newPRs: newPRs
        )
    }

    // MARK: - Previous session reference

    private static func previousSets(for exerciseName: String, context: ModelContext) -> [PreviousSet] {
        let descriptor = FetchDescriptor<WorkoutSession>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let sessions = (try? context.fetch(descriptor)) ?? []
        let key = exerciseName.lowercased()

        for session in sessions {
            if let match = session.exercises.first(where: { $0.exerciseName.lowercased() == key }) {
                let sets = match.sets
                    .filter(\.isCompleted)
                    .sorted { $0.setNumber < $1.setNumber }
                    .map { PreviousSet(weightKg: $0.weightKg, reps: $0.reps) }
                if !sets.isEmpty { return sets }
            }
        }
        return []
    }

    static func weightString(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(value))
            : String(format: "%.1f", value)
    }
}
