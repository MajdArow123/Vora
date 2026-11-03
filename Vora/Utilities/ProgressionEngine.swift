//
//  ProgressionEngine.swift
//  Vora
//
//  Created by Majd Arow on 2026-11-02.
//

import Foundation

/// Which way double progression moves first. Raw values are persisted and
/// never change.
nonisolated enum ProgressionMode: String, Codable, CaseIterable, Identifiable {
    /// Fill the rep range on every set, then add load.
    case repsFirst
    /// Add load as soon as the next load is predicted to stay in the range.
    case weightFirst

    var id: String { rawValue }
}

/// One completed set, as the engine sees it. Weights are kilograms.
nonisolated struct ProgressionSet: Equatable {
    var weightKg: Double
    var reps: Int
    var rir: Int?
}

/// One past session of the exercise. `targets` is what it was done under;
/// nil for logs without a snapshot, which are judged by the current targets.
nonisolated struct ProgressionSession: Equatable {
    var sets: [ProgressionSet]
    var targets: TemplateTargets?
}

nonisolated struct ProgressionInput: Equatable {
    var exerciseId: String?
    var targets: TemplateTargets
    /// Newest first, at most `ProgressionEngine.historyLimit` sessions.
    var history: [ProgressionSession]
    /// Whole calendar days since the newest session in `history`.
    var daysSinceLastSession: Int
    /// nil when the equipment isn't known (custom exercises).
    var equipment: EquipmentType?
    /// nil when the gym's inventory hasn't been filled yet.
    var inventory: LoadingInventory?
    var mode: ProgressionMode
    /// Every weight ever logged for the exercise, beyond `history`. On step
    /// equipment these count as loadable, so a lifted weight is never snapped.
    var loggedLoadsKg: [Double] = []
}

/// Why a set got its numbers. Holds values rather than text, so the wording
/// follows the user's units when it's shown (see ProgressionExplanation).
/// Persisted in the session draft; case and field names never change.
nonisolated enum ProgressionReason: Codable, Equatable {
    case raiseLoad(fromKg: Double, toKg: Double, topReps: Int)
    case raiseLoadEarly(fromKg: Double, toKg: Double, predictedReps: Int)
    case addRep(lastReps: Int, targetReps: Int)
    case repeatTop(topReps: Int)
    case atTopOfRange(topReps: Int)
    case holdTooHard(struggling: Int, total: Int)
    case dropLoad(fromKg: Double, toKg: Double)
    case finishSets(done: Int, target: Int)
    case welcomeBack(days: Int)
    case rangeChanged(oldMin: Int, oldMax: Int, newMin: Int, newMax: Int, fromKg: Double, toKg: Double)
    case retargeted(actualE1RMKg: Double, predictedE1RMKg: Double)
    case extendedReps(targetReps: Int)
}

/// Persisted in the session draft; case and field names never change.
nonisolated enum ProgressionWarning: Codable, Equatable {
    /// The next load is predicted to fall below the rep range.
    case jumpTooLarge(nextKg: Double, predictedReps: Int)
    case noHeavierLoad(currentKg: Double)
    /// The app doesn't know what this equipment can load.
    case loadNotModeled
    /// The last load can't be made at this gym.
    case snappedLoad(fromKg: Double, toKg: Double)
    case lightestLoad(currentKg: Double)
}

/// Persisted in the session draft; case and field names never change.
nonisolated enum ProgressionFix: Codable, Equatable {
    /// This session only.
    case extendReps(toReps: Int)
    /// Saved to the template.
    case widenRange(min: Int, max: Int)
    case swapExercise
}

/// Persisted in the session draft; field names never change.
nonisolated struct Recommendation: Codable, Equatable {
    var weightKg: Double
    var targetReps: Int
    var reason: ProgressionReason
    var warnings: [ProgressionWarning] = []
    var fixes: [ProgressionFix] = []
}

/// Rule-based double progression with RIR. Pure and deterministic: plain
/// values in and out, with no storage, clock or units.
nonisolated enum ProgressionEngine {
    static let historyLimit = 3
    /// Older than this and the load is held, whatever the last session said.
    static let longGapDays = 21
    /// How far set 1's e1RM may stray from the prediction before the
    /// remaining sets are retargeted; about 3 reps.
    static let retargetThreshold = 0.075
    /// A next load this many reps below the range still counts as fitting,
    /// so a single-rep range isn't flagged on every small jump.
    static let jumpSlackReps = 1
    static let dropTargetFraction = 0.925
    static let dropWindow = 0.90...0.95
    /// Reps a widen fix adds when no particular jump calls for more.
    static let defaultWidenReps = 2

    /// Loads closer than this are the same load; matches LoadCalculator.
    private static let toleranceKg = 0.005

    // MARK: - Recommend

    /// One recommendation per target set, or [] with no usable history.
    static func recommend(_ input: ProgressionInput) -> [Recommendation] {
        let sessions = usableSessions(input.history)
        guard let latest = sessions.first else { return [] }

        let targets = input.targets
        let judge = latest.targets ?? targets
        let working = workingSets(of: latest, limit: judge.targetSets)
        guard let heaviest = working.first?.weightKg else { return [] }

        let loads = heaviest > 0 ? modeledLoads(input, referenceKg: heaviest) : []
        let held = loads.isEmpty
            ? heaviest
            : LoadCalculator.nearest(toKg: heaviest, in: loads, rounding: .nearest)
        let snapped: [ProgressionWarning] = abs(held - heaviest) > toleranceKg
            ? [.snappedLoad(fromKg: heaviest, toKg: held)]
            : []

        let setCount = max(targets.targetSets, 1)
        func uniform(
            weightKg: Double,
            reps: Int,
            reason: ProgressionReason,
            warnings: [ProgressionWarning] = [],
            fixes: [ProgressionFix] = []
        ) -> [Recommendation] {
            Array(repeating: Recommendation(
                weightKg: weightKg,
                targetReps: reps,
                reason: reason,
                warnings: snapped + warnings,
                fixes: fixes
            ), count: setCount)
        }
        /// Each set's last reps, kept inside the current range.
        func holding(reason: ProgressionReason, warnings: [ProgressionWarning] = []) -> [Recommendation] {
            (0..<setCount).map { index in
                Recommendation(
                    weightKg: held,
                    targetReps: clampedToRange(lastReps(working, index: index), targets),
                    reason: reason,
                    warnings: snapped + warnings
                )
            }
        }

        // Long gap: hold the load, no raise and no drop.
        if input.daysSinceLastSession > longGapDays {
            return holding(reason: .welcomeBack(days: input.daysSinceLastSession))
        }

        // The range changed since: last session's reps say nothing about it.
        if let previousRange = latest.targets, !sameRange(previousRange, targets) {
            let reason = { (toKg: Double) in
                ProgressionReason.rangeChanged(
                    oldMin: previousRange.repRangeMin,
                    oldMax: previousRange.repRangeMax,
                    newMin: targets.repRange.lowerBound,
                    newMax: targets.repRange.upperBound,
                    fromKg: heaviest,
                    toKg: toKg
                )
            }
            guard !loads.isEmpty else { return holding(reason: reason(heaviest)) }
            let best = working.map { e1RM($0, assumedRIR: judge.targetRIR) }.max() ?? 0
            let rebased = loads.last {
                predictedReps(e1RMKg: best, atKg: $0, targetRIR: targets.targetRIR) >= targets.repRange.lowerBound
            } ?? loads[0]
            return uniform(weightKg: rebased, reps: targets.repRange.lowerBound, reason: reason(rebased))
        }

        // Too hard: hold once, drop when it happens twice under this range.
        let strugglingCount = working.filter { isStruggling($0, judge) }.count
        if strugglingCount * 2 > working.count {
            if isStruggling(sessions.dropFirst().first, current: targets) {
                if let lighter = dropLoad(from: held, in: loads) {
                    return uniform(
                        weightKg: lighter,
                        reps: targets.repRange.lowerBound,
                        reason: .dropLoad(fromKg: held, toKg: lighter)
                    )
                }
                if !loads.isEmpty {
                    return holding(
                        reason: .holdTooHard(struggling: strugglingCount, total: working.count),
                        warnings: [.lightestLoad(currentKg: held)]
                    )
                }
            }
            return holding(reason: .holdTooHard(struggling: strugglingCount, total: working.count))
        }

        if working.count < judge.targetSets {
            return holding(reason: .finishSets(done: working.count, target: judge.targetSets))
        }

        let topReps = targets.repRange.upperBound
        let minReps = targets.repRange.lowerBound
        let weakest = working.map { e1RM($0, assumedRIR: judge.targetRIR) }.min() ?? 0
        let next = LoadCalculator.nextAchievable(aboveKg: held, in: loads)
        let predictedAtNext = next.map {
            predictedReps(e1RMKg: weakest, atKg: $0, targetRIR: targets.targetRIR)
        }
        let effortMet = working.allSatisfy { metTargetEffort($0, judge) }

        // Top of the range on every set at the target effort.
        if effortMet, working.allSatisfy({ $0.reps >= judge.repRange.upperBound }) {
            let extend = ProgressionFix.extendReps(toReps: min(topReps + 1, TemplateExerciseSpec.Limits.reps.upperBound))
            guard !loads.isEmpty else {
                let widenedMax = topReps + defaultWidenReps
                let fixes: [ProgressionFix] = TemplateExerciseSpec.Limits.reps.contains(widenedMax)
                    ? [extend, .widenRange(min: minReps, max: widenedMax)]
                    : [extend]
                return uniform(
                    weightKg: held,
                    reps: topReps,
                    reason: .atTopOfRange(topReps: topReps),
                    warnings: [.loadNotModeled],
                    fixes: fixes
                )
            }
            guard let next, let predictedAtNext else {
                return uniform(
                    weightKg: held,
                    reps: topReps,
                    reason: .atTopOfRange(topReps: topReps),
                    warnings: [.noHeavierLoad(currentKg: held)],
                    fixes: [extend, .swapExercise]
                )
            }
            if predictedAtNext < minReps - jumpSlackReps {
                let needed = repsNeeded(atKg: held, toReachKg: next, targets: targets)
                var fixes = [extend]
                if TemplateExerciseSpec.Limits.reps.contains(needed) {
                    fixes.append(.widenRange(min: minReps, max: max(needed, topReps + 1)))
                }
                fixes.append(.swapExercise)
                return uniform(
                    weightKg: held,
                    reps: topReps,
                    reason: .atTopOfRange(topReps: topReps),
                    warnings: [.jumpTooLarge(nextKg: next, predictedReps: predictedAtNext)],
                    fixes: fixes
                )
            }
            return uniform(
                weightKg: next,
                reps: minReps,
                reason: .raiseLoad(fromKg: held, toKg: next, topReps: topReps)
            )
        }

        // Weight-first raises as soon as the next load stays in the range.
        if input.mode == .weightFirst, effortMet, let next, let predictedAtNext, predictedAtNext >= minReps {
            return uniform(
                weightKg: next,
                reps: min(predictedAtNext, topReps),
                reason: .raiseLoadEarly(fromKg: held, toKg: next, predictedReps: predictedAtNext)
            )
        }

        // In the range: same load, one more rep on each set.
        return (0..<setCount).map { index in
            let last = lastReps(working, index: index)
            let target = clampedToRange(last + 1, targets)
            return Recommendation(
                weightKg: held,
                targetReps: target,
                reason: last >= topReps ? .repeatTop(topReps: topReps) : .addRep(lastReps: last, targetReps: target),
                warnings: snapped
            )
        }
    }

    /// The e1RM a new session should open near: the median of each recent
    /// session's best. nil with no usable history.
    static func predictedE1RM(_ input: ProgressionInput) -> Double? {
        let bests = usableSessions(input.history).compactMap { session -> Double? in
            let judge = session.targets ?? input.targets
            return workingSets(of: session, limit: judge.targetSets)
                .map { e1RM($0, assumedRIR: judge.targetRIR) }
                .max()
        }.sorted()
        guard !bests.isEmpty else { return nil }
        let middle = bests.count / 2
        return bests.count.isMultiple(of: 2) ? (bests[middle - 1] + bests[middle]) / 2 : bests[middle]
    }

    // MARK: - In-session retarget

    /// New numbers for the rest of the session when set 1 strayed strongly
    /// from the prediction, one per plan entry; nil when it didn't. After a
    /// long gap only a weak set 1 retargets, so nothing raises the load.
    static func retarget(
        plan: [Recommendation],
        firstSet: ProgressionSet,
        predictedE1RMKg: Double,
        input: ProgressionInput
    ) -> [Recommendation]? {
        guard predictedE1RMKg > 0, firstSet.weightKg > 0, firstSet.reps >= 1 else { return nil }
        let targets = input.targets
        let actual = e1RM(firstSet, assumedRIR: targets.targetRIR)
        let deviation = actual / predictedE1RMKg - 1
        guard abs(deviation) >= retargetThreshold else { return nil }
        if deviation > 0, input.daysSinceLastSession > longGapDays { return nil }

        let loads = modeledLoads(input, referenceKg: firstSet.weightKg)
        let range = targets.repRange
        let reps = { (load: Double) in predictedReps(e1RMKg: actual, atKg: load, targetRIR: targets.targetRIR) }

        var load = firstSet.weightKg
        if !loads.isEmpty {
            let here = reps(load)
            if here < range.lowerBound {
                load = loads.last { $0 <= load + toleranceKg && reps($0) >= range.lowerBound } ?? loads[0]
            } else if here > range.upperBound {
                // One step at most: a typo in set 1 must not load the bar
                // with what it seems to predict.
                if let next = LoadCalculator.nextAchievable(aboveKg: load, in: loads), reps(next) >= range.lowerBound {
                    load = next
                }
            }
        }
        let target = clampedToRange(reps(load), targets)
        return plan.map { _ in
            Recommendation(
                weightKg: load,
                targetReps: target,
                reason: .retargeted(actualE1RMKg: actual, predictedE1RMKg: predictedE1RMKg)
            )
        }
    }

    // MARK: - Fix results

    /// A recommendation after "extend reps": same load, past the range.
    static func extendingReps(_ recommendation: Recommendation, toReps reps: Int) -> Recommendation {
        Recommendation(
            weightKg: recommendation.weightKg,
            targetReps: reps,
            reason: .extendedReps(targetReps: reps)
        )
    }

    // MARK: - Shared math

    /// Epley estimate. One definition shared with the record calculations.
    static func e1RM(_ set: ProgressionSet, assumedRIR: Int?) -> Double {
        StrengthProgression.epley(
            weightKg: set.weightKg,
            repsToFailure: set.reps + (set.rir ?? assumedRIR ?? 0)
        )
    }

    /// Reps doable at a load while leaving the target RIR, rounded down.
    static func predictedReps(e1RMKg: Double, atKg load: Double, targetRIR: Int?) -> Int {
        guard load > 0 else { return 0 }
        let toFailure = 30 * (e1RMKg / load - 1)
        return max(Int((toFailure + 1e-9).rounded(.down)) - (targetRIR ?? 0), 0)
    }

    // MARK: - Rules' helpers

    private static func usableSessions(_ history: [ProgressionSession]) -> [ProgressionSession] {
        history.prefix(historyLimit).compactMap { session in
            let sets = session.sets.filter { $0.reps >= 1 && $0.weightKg >= 0 && $0.weightKg.isFinite }
            return sets.isEmpty ? nil : ProgressionSession(sets: sets, targets: session.targets)
        }
    }

    /// The first sets at the session's heaviest load. Lighter sets are
    /// warm-ups or back-offs.
    private static func workingSets(of session: ProgressionSession, limit: Int) -> [ProgressionSet] {
        guard let heaviest = session.sets.map(\.weightKg).max() else { return [] }
        return Array(session.sets.filter { heaviest - $0.weightKg <= toleranceKg }.prefix(max(limit, 1)))
    }

    private static func modeledLoads(_ input: ProgressionInput, referenceKg: Double) -> [Double] {
        guard let equipment = input.equipment, let inventory = input.inventory else { return [] }
        return LoadCalculator.workingLoads(
            equipment: equipment,
            profile: inventory,
            referenceKg: referenceKg,
            loggedKg: input.loggedLoadsKg + input.history.flatMap { $0.sets.map(\.weightKg) }
        )
    }

    private static func sameRange(_ lhs: TemplateTargets, _ rhs: TemplateTargets) -> Bool {
        lhs.repRange == rhs.repRange
    }

    private static func isStruggling(_ set: ProgressionSet, _ judge: TemplateTargets) -> Bool {
        if set.reps < judge.repRange.lowerBound { return true }
        guard let target = judge.targetRIR, let rir = set.rir else { return false }
        return rir < target - 1
    }

    /// Whether the session before the latest also struggled. One done under
    /// a different range is never evidence for a drop.
    private static func isStruggling(_ session: ProgressionSession?, current: TemplateTargets) -> Bool {
        guard let session else { return false }
        if let targets = session.targets, !sameRange(targets, current) { return false }
        let judge = session.targets ?? current
        let working = workingSets(of: session, limit: judge.targetSets)
        return working.filter { isStruggling($0, judge) }.count * 2 > working.count
    }

    private static func metTargetEffort(_ set: ProgressionSet, _ judge: TemplateTargets) -> Bool {
        guard let target = judge.targetRIR, let rir = set.rir else { return true }
        return rir >= target
    }

    private static func lastReps(_ working: [ProgressionSet], index: Int) -> Int {
        (index < working.count ? working[index] : working.last)?.reps ?? 0
    }

    private static func clampedToRange(_ reps: Int, _ targets: TemplateTargets) -> Int {
        min(max(reps, targets.repRange.lowerBound), targets.repRange.upperBound)
    }

    /// The load closest to the target fraction inside the window, else the
    /// next one down; nil when nothing lighter exists.
    private static func dropLoad(from held: Double, in loads: [Double]) -> Double? {
        let lower = loads.filter { $0 < held - toleranceKg }
        let target = held * dropTargetFraction
        var best: Double?
        for load in lower where dropWindow.contains(load / held) {
            if let current = best, abs(current - target) <= abs(load - target) { continue }
            best = load
        }
        return best ?? lower.last
    }

    /// Reps at `load` whose e1RM makes the next load doable at the range's
    /// minimum: what the top of a widened range needs to be.
    private static func repsNeeded(atKg load: Double, toReachKg next: Double, targets: TemplateTargets) -> Int {
        let rir = targets.targetRIR ?? 0
        let needed = next * (1 + Double(targets.repRange.lowerBound + rir) / 30)
        return Int((30 * (needed / load - 1) - 1e-9).rounded(.up)) - rir
    }
}
