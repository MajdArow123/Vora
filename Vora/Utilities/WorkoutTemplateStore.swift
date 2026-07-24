//
//  WorkoutTemplateStore.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-24.
//

import Foundation

/// Default exercise lists per split day, with user overrides persisted in
/// UserDefaults. Keyed by "\(split.rawValue).\(dayIndex)" rather than the
/// day's title because titles are user-editable and repeat within a week
/// (both Upper days are titled "Upper").
enum WorkoutTemplateStore {
    static let storageKey = "vora.workoutTemplates"

    private static let upperA = [
        "Barbell Bench Press", "Overhead Press", "Incline Dumbbell Press",
        "Triceps Pushdown", "Lateral Raise", "Dip",
    ]
    private static let upperB = [
        "Pull-Up", "Barbell Row", "Seated Cable Row",
        "Face Pull", "Barbell Curl", "Hammer Curl",
    ]
    private static let lowerA = [
        "Back Squat", "Leg Press", "Bulgarian Split Squat",
        "Leg Extension", "Standing Calf Raise",
    ]
    private static let lowerB = [
        "Romanian Deadlift", "Hip Thrust", "Lying Leg Curl",
        "Hip Abduction", "Cable Kickback",
    ]
    private static let push = [
        "Barbell Bench Press", "Overhead Press", "Incline Dumbbell Press",
        "Lateral Raise", "Triceps Pushdown", "Skull Crusher",
    ]
    private static let pull = [
        "Pull-Up", "Barbell Row", "Seated Cable Row",
        "Face Pull", "Barbell Curl", "Hammer Curl",
    ]
    private static let legs = [
        "Back Squat", "Romanian Deadlift", "Leg Press",
        "Lying Leg Curl", "Hip Thrust", "Standing Calf Raise",
    ]
    private static let fullBodyA = [
        "Back Squat", "Barbell Bench Press", "Barbell Row",
        "Overhead Press", "Romanian Deadlift",
    ]
    private static let fullBodyB = [
        "Deadlift", "Incline Dumbbell Press", "Pull-Up",
        "Hip Thrust", "Lateral Raise",
    ]

    static func key(for split: TrainingSplit, dayIndex: Int) -> String {
        "\(split.rawValue).\(dayIndex)"
    }

    /// Built-in default for a split's weekday slot (0 = Monday). Rest days
    /// and the custom split have no defaults.
    static func defaultTemplate(for split: TrainingSplit, dayIndex: Int) -> [String] {
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

    /// The user's saved template for the slot, falling back to the default.
    static func template(
        for split: TrainingSplit,
        dayIndex: Int,
        defaults: UserDefaults = .standard
    ) -> [String] {
        stored(in: defaults)[key(for: split, dayIndex: dayIndex)]
            ?? defaultTemplate(for: split, dayIndex: dayIndex)
    }

    static func saveTemplate(
        _ exercises: [String],
        for split: TrainingSplit,
        dayIndex: Int,
        defaults: UserDefaults = .standard
    ) {
        var all = stored(in: defaults)
        all[key(for: split, dayIndex: dayIndex)] = exercises
        defaults.set(all, forKey: storageKey)
    }

    static func resetTemplate(
        for split: TrainingSplit,
        dayIndex: Int,
        defaults: UserDefaults = .standard
    ) {
        var all = stored(in: defaults)
        all.removeValue(forKey: key(for: split, dayIndex: dayIndex))
        defaults.set(all, forKey: storageKey)
    }

    static func isCustomized(
        for split: TrainingSplit,
        dayIndex: Int,
        defaults: UserDefaults = .standard
    ) -> Bool {
        stored(in: defaults)[key(for: split, dayIndex: dayIndex)] != nil
    }

    private static func stored(in defaults: UserDefaults) -> [String: [String]] {
        defaults.dictionary(forKey: storageKey) as? [String: [String]] ?? [:]
    }
}
