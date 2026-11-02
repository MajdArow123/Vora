//
//  WorkoutTemplateService.swift
//  Vora
//
//  Created by Majd Arow on 2026-11-01.
//

import Foundation
import OSLog
import SwiftData

/// Reads and writes split-day templates. Slots are identified by split and
/// weekday index rather than the day's title, because titles are
/// user-editable and repeat within a week (both Upper days are "Upper").
/// A slot with no saved WorkoutTemplate uses the built-in default.
enum WorkoutTemplateService {
    private static let logger = Logger(subsystem: "com.majdarow.Vora", category: "Workout")

    private static let upperA = [
        "barbell-bench-press", "overhead-press", "incline-dumbbell-press",
        "triceps-pushdown", "lateral-raise", "dip",
    ]
    private static let upperB = [
        "pull-up", "barbell-row", "seated-cable-row",
        "face-pull", "barbell-curl", "hammer-curl",
    ]
    private static let lowerA = [
        "back-squat", "leg-press", "bulgarian-split-squat",
        "leg-extension", "standing-calf-raise",
    ]
    private static let lowerB = [
        "romanian-deadlift", "hip-thrust", "lying-leg-curl",
        "hip-abduction", "cable-kickback",
    ]
    private static let push = [
        "barbell-bench-press", "overhead-press", "incline-dumbbell-press",
        "lateral-raise", "triceps-pushdown", "skull-crusher",
    ]
    private static let pull = [
        "pull-up", "barbell-row", "seated-cable-row",
        "face-pull", "barbell-curl", "hammer-curl",
    ]
    private static let legs = [
        "back-squat", "romanian-deadlift", "leg-press",
        "lying-leg-curl", "hip-thrust", "standing-calf-raise",
    ]
    private static let fullBodyA = [
        "back-squat", "barbell-bench-press", "barbell-row",
        "overhead-press", "romanian-deadlift",
    ]
    private static let fullBodyB = [
        "deadlift", "incline-dumbbell-press", "pull-up",
        "hip-thrust", "lateral-raise",
    ]

    /// Weekday slots, Monday first.
    static let dayIndices = 0...6

    /// Built-in default library IDs for a split's weekday slot. Rest days
    /// and the custom split have no defaults.
    static func defaultExerciseIDs(for split: TrainingSplit, dayIndex: Int) -> [String] {
        switch (split, dayIndex) {
        case (.upperLower, 0): upperA
        case (.upperLower, 1): lowerA
        case (.upperLower, 3): upperB
        case (.upperLower, 4): lowerB
        case (.ppl, 0), (.ppl, 3): push
        case (.ppl, 1), (.ppl, 4): pull
        case (.ppl, 2), (.ppl, 5): legs
        case (.fullBody, 0), (.fullBody, 4): fullBodyA
        case (.fullBody, 2): fullBodyB
        default: []
        }
    }

    static func defaultPlan(for split: TrainingSplit, dayIndex: Int) -> [TemplateExerciseSpec] {
        defaultExerciseIDs(for: split, dayIndex: dayIndex).map { TemplateExerciseSpec(exerciseId: $0) }
    }

    /// Name for a new template row: the split's title for that day, or a
    /// numbered fallback for rest and custom slots.
    static func defaultName(for split: TrainingSplit, dayIndex: Int) -> String {
        let week = split.weeklyTemplate
        if week.indices.contains(dayIndex), !week[dayIndex].isRest {
            return week[dayIndex].title
        }
        return "Day \(dayIndex + 1)"
    }

    static func template(
        for split: TrainingSplit,
        dayIndex: Int,
        context: ModelContext
    ) throws -> WorkoutTemplate? {
        let raw = split.rawValue
        var descriptor = FetchDescriptor<WorkoutTemplate>(
            predicate: #Predicate { $0.splitRawValue == raw && $0.dayIndex == dayIndex }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// The saved template's exercises in order, or the default.
    static func plan(
        for split: TrainingSplit,
        dayIndex: Int,
        context: ModelContext
    ) throws -> [TemplateExerciseSpec] {
        guard let saved = try template(for: split, dayIndex: dayIndex, context: context) else {
            return defaultPlan(for: split, dayIndex: dayIndex)
        }
        return saved.orderedExercises.map { TemplateExerciseSpec($0) }
    }

    /// The plan for a new session in this slot; empty on rest days. Falls
    /// back to the built-in default when the saved template can't be read,
    /// so a session can always start.
    static func sessionPlan(
        isRestDay: Bool,
        split: TrainingSplit,
        dayIndex: Int,
        context: ModelContext
    ) -> [TemplateExerciseSpec] {
        guard !isRestDay else { return [] }
        do {
            return try plan(for: split, dayIndex: dayIndex, context: context)
        } catch {
            logger.error("Failed to load today's template: \(String(describing: error), privacy: .public)")
            return defaultPlan(for: split, dayIndex: dayIndex)
        }
    }

    /// The slot's day title: the saved template's name, or the default.
    /// Falls back to the default when the template can't be read, matching
    /// `sessionPlan`.
    static func dayTitle(split: TrainingSplit, dayIndex: Int, context: ModelContext) -> String {
        do {
            return try template(for: split, dayIndex: dayIndex, context: context)?.name
                ?? defaultName(for: split, dayIndex: dayIndex)
        } catch {
            logger.error("Failed to load today's template title: \(String(describing: error), privacy: .public)")
            return defaultName(for: split, dayIndex: dayIndex)
        }
    }

    static func isCustomized(
        for split: TrainingSplit,
        dayIndex: Int,
        context: ModelContext
    ) throws -> Bool {
        try template(for: split, dayIndex: dayIndex, context: context) != nil
    }

    /// Saves `specs` as the slot's template, creating the row if needed.
    /// Existing exercises are matched by ID and updated in place so their
    /// IDs stay stable across edits; new ones are inserted and missing
    /// ones deleted. Targets are clamped to `TemplateExerciseSpec.Limits`.
    static func save(
        _ specs: [TemplateExerciseSpec],
        for split: TrainingSplit,
        dayIndex: Int,
        context: ModelContext
    ) throws {
        let template: WorkoutTemplate
        if let existing = try self.template(for: split, dayIndex: dayIndex, context: context) {
            template = existing
        } else {
            template = WorkoutTemplate(
                split: split,
                dayIndex: dayIndex,
                name: defaultName(for: split, dayIndex: dayIndex)
            )
            context.insert(template)
        }

        let keptIDs = Set(specs.map(\.id))
        for exercise in template.exercises where !keptIDs.contains(exercise.id) {
            context.delete(exercise)
        }
        template.exercises.removeAll { !keptIDs.contains($0.id) }

        let existingByID = Dictionary(
            template.exercises.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for (index, spec) in specs.enumerated() {
            let values = spec.clamped()
            let exercise: TemplateExercise
            if let match = existingByID[spec.id] {
                exercise = match
            } else {
                exercise = TemplateExercise(id: spec.id, exerciseId: values.exerciseId, orderIndex: index)
                template.exercises.append(exercise)
            }
            exercise.exerciseId = values.exerciseId
            exercise.customName = values.customName
            exercise.orderIndex = index
            exercise.targetSets = values.targetSets
            exercise.repRangeMin = values.repRangeMin
            exercise.repRangeMax = values.repRangeMax
            exercise.targetRIR = values.targetRIR
            exercise.restSeconds = values.restSeconds
        }

        try context.save()
    }

    /// Deletes the slot's saved template so the default applies again.
    static func reset(for split: TrainingSplit, dayIndex: Int, context: ModelContext) throws {
        guard let saved = try template(for: split, dayIndex: dayIndex, context: context) else { return }
        context.delete(saved)
        try context.save()
    }
}
