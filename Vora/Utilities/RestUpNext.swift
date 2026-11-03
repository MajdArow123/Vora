//
//  RestUpNext.swift
//  Vora
//
//  Created by Majd Arow on 2026-11-03.
//

import Foundation

/// What comes after the current rest, for the Live Activity and the rest-over
/// notification. Pure: plain session values in, text in the user's units out.
struct RestUpNext: Equatable {
    static let lastSetText = "Last set done"

    let exerciseName: String
    let setText: String

    var notificationBody: String {
        "\(exerciseName): \(setText)"
    }

    /// `restedAfter` is the exercise whose set started the rest. It isn't in
    /// the draft, so a resumed rest passes nil and the last exercise with a
    /// completed set stands in. With nothing left to do, the exercise rested
    /// after is named, or `fallbackName` when there isn't one.
    static func resolve(
        exercises: [ActiveSessionViewModel.DraftExercise],
        restedAfter: ActiveSessionViewModel.DraftExercise.ID?,
        units: UnitSystem,
        fallbackName: String
    ) -> RestUpNext {
        let anchor = exercises.firstIndex { $0.id == restedAfter }
            ?? exercises.lastIndex { $0.sets.contains(where: \.isCompleted) }

        for index in searchOrder(exercises: exercises, anchor: anchor) {
            if let set = exercises[index].sets.first(where: { !$0.isCompleted }) {
                return RestUpNext(
                    exerciseName: exercises[index].name,
                    setText: setText(set, repRange: exercises[index].repRange, units: units)
                )
            }
        }
        return RestUpNext(
            exerciseName: anchor.map { exercises[$0].name } ?? fallbackName,
            setText: lastSetText
        )
    }

    /// The exercise rested after, or its whole superset from the top because
    /// a round starts again there. Then later exercises, then earlier ones.
    private static func searchOrder(
        exercises: [ActiveSessionViewModel.DraftExercise],
        anchor: Int?
    ) -> [Int] {
        guard let anchor else { return Array(exercises.indices) }
        var first = anchor
        var last = anchor
        if let group = exercises[anchor].supersetGroup {
            while first > 0, exercises[first - 1].supersetGroup == group { first -= 1 }
            while last + 1 < exercises.count, exercises[last + 1].supersetGroup == group { last += 1 }
        }
        return Array(first...last) + Array((last + 1)..<exercises.count) + Array(0..<first)
    }

    /// "80 kg × 8", "180 lb × 8–12", "Warm-up · 40 kg × 5", or as much of
    /// that as is known. Typed reps win over the recommendation, which wins
    /// over the template's range. A weight of 0 is bodyweight work.
    static func setText(
        _ set: ActiveSessionViewModel.DraftSet,
        repRange: ClosedRange<Int>?,
        units: UnitSystem
    ) -> String {
        let weight = set.weightKg.flatMap { $0 > 0 ? UnitConversion.liftWeightText(kg: $0, units: units) : nil }
        let reps = repsText(set, repRange: repRange)

        let load: String?
        switch (weight, reps) {
        case let (weight?, reps?): load = "\(weight) × \(reps)"
        case let (weight?, nil): load = weight
        case let (nil, reps?): load = "\(reps) reps"
        case (nil, nil): load = nil
        }

        if set.setType == .normal {
            return load ?? "Next set"
        }
        return load.map { "\(set.setType.displayName) · \($0)" } ?? set.setType.displayName
    }

    private static func repsText(_ set: ActiveSessionViewModel.DraftSet, repRange: ClosedRange<Int>?) -> String? {
        if let reps = set.reps { return String(reps) }
        if let target = set.activeRecommendation?.targetReps { return String(target) }
        guard set.setType.isWorkingSet, let repRange else { return nil }
        return repRange.count == 1 ? String(repRange.lowerBound) : "\(repRange.lowerBound)–\(repRange.upperBound)"
    }
}
