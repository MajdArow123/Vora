//
//  TemplateExerciseSpec.swift
//  Vora
//
//  Created by Majd Arow on 2026-11-01.
//

import Foundation

/// Plain-value copy of a TemplateExercise, used by the template editor and
/// to start a session, so neither needs SwiftData objects. `id` matches
/// the TemplateExercise it was read from, which lets a save update that
/// row in place.
struct TemplateExerciseSpec: Identifiable, Equatable {
    nonisolated enum Limits {
        static let sets = 1...10
        static let reps = 1...50
        static let rir = 0...5
        static let restSeconds = 30...600
        static let restStepSeconds = 15
    }

    static let defaultTargetSets = 3
    static let defaultRepRange = 8...12
    static let defaultTargetRIR = 2

    var id: UUID
    /// Library ID; nil for custom exercises.
    var exerciseId: String?
    /// Set only for custom exercises.
    var customName: String?
    var targetSets: Int
    var repRangeMin: Int
    var repRangeMax: Int
    var targetRIR: Int?
    var restSeconds: Int

    init(
        id: UUID = UUID(),
        exerciseId: String?,
        customName: String? = nil,
        targetSets: Int = Self.defaultTargetSets,
        repRangeMin: Int = Self.defaultRepRange.lowerBound,
        repRangeMax: Int = Self.defaultRepRange.upperBound,
        targetRIR: Int? = Self.defaultTargetRIR,
        restSeconds: Int? = nil
    ) {
        self.id = id
        self.exerciseId = exerciseId
        self.customName = exerciseId == nil ? customName : nil
        self.targetSets = targetSets
        self.repRangeMin = repRangeMin
        self.repRangeMax = repRangeMax
        self.targetRIR = targetRIR
        self.restSeconds = restSeconds ?? ExerciseLibrary.defaultRestSeconds(exerciseId: exerciseId)
    }

    init(_ exercise: TemplateExercise) {
        self.init(
            id: exercise.id,
            exerciseId: exercise.exerciseId,
            customName: exercise.customName,
            targetSets: exercise.targetSets,
            repRangeMin: exercise.repRangeMin,
            repRangeMax: exercise.repRangeMax,
            targetRIR: exercise.targetRIR,
            restSeconds: exercise.restSeconds
        )
    }

    /// A spec with default targets for a name picked in the picker or
    /// typed by the user: library names become an ID, anything else a
    /// custom exercise.
    init(pickedName name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let exerciseId = ExerciseIdentity.libraryID(forName: trimmed)
        self.init(exerciseId: exerciseId, customName: exerciseId == nil ? trimmed : nil)
    }

    var displayName: String {
        Self.displayName(exerciseId: exerciseId, customName: customName)
    }

    var repRange: ClosedRange<Int> {
        repRangeMin...max(repRangeMin, repRangeMax)
    }

    /// Same identity key ExerciseLog uses, so duplicates are detected
    /// across library and custom exercises alike.
    var identityKey: String {
        ExerciseIdentity.key(exerciseId: exerciseId, name: customName ?? "")
    }

    /// Every target forced into `Limits`, with the rep range ordered and
    /// rest snapped to the step.
    func clamped() -> TemplateExerciseSpec {
        var copy = self
        copy.targetSets = Self.clamp(targetSets, to: Limits.sets)
        copy.repRangeMin = Self.clamp(repRangeMin, to: Limits.reps)
        copy.repRangeMax = Self.clamp(max(repRangeMax, copy.repRangeMin), to: Limits.reps)
        copy.targetRIR = targetRIR.map { Self.clamp($0, to: Limits.rir) }
        let step = Limits.restStepSeconds
        let snapped = Int((Double(restSeconds) / Double(step)).rounded()) * step
        copy.restSeconds = Self.clamp(snapped, to: Limits.restSeconds)
        return copy
    }

    static func displayName(exerciseId: String?, customName: String?) -> String {
        if let exerciseId, let definition = ExerciseLibrary.definition(id: exerciseId) {
            return definition.name
        }
        return customName ?? exerciseId ?? ""
    }

    private static func clamp(_ value: Int, to range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
