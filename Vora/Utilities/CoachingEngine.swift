//
//  CoachingEngine.swift
//  Vora
//
//  Created by Majd Arow on 2026-11-03.
//

import Foundation

/// Connects training and nutrition: how strength is going, what that means for
/// calories, and whether the user is in a deficit. Pure: days are plain offsets
/// and weights are kilograms. docs/COACHING.md explains every rule and number.
enum CoachingEngine {
    // MARK: - Strength trend constants

    /// Long enough to see past one bad session, short enough to reflect the
    /// current phase of a diet.
    static let strengthWindowDays = 28
    /// Epley gets unreliable above this, and moving to high-rep work would
    /// otherwise read as a change in strength.
    static let maximumTrendReps = 15
    /// How many lifts speak for overall strength.
    static let topLiftCount = 5
    /// A lift below these says too little to draw a line through, so it's
    /// ignored. Within the window, the span also means a lift's last session is
    /// at most 13 days old, so a dropped lift stops counting by itself.
    static let minimumLiftSessions = 3
    static let minimumLiftSpanDays = 14
    /// One lift alone could be a niggle or a technique change.
    static let minimumLifts = 2
    /// About one rep lost or gained at 8 reps over the window. Smaller moves
    /// are noise and read as flat.
    static let strengthTrendThresholdPercent = 0.5

    // MARK: - Rule constants

    /// Losing this many times the goal rate risks muscle.
    static let fastLossFactor = 1.5
    /// Gaining this many times the goal rate while strength is flat is mostly
    /// extra fat. Lower than the loss factor because the rate itself is smaller.
    static let fastGainFactor = 1.25
    /// Intake within this share of the target counts as eating to it. Beyond
    /// it, changing the target wouldn't change what's on the plate.
    static let adherenceTolerance = 0.10
    /// Falling strength alone is the softer signal.
    static let easeForStrengthKcal = 100
    /// Losing too fast is the stronger one, and the amount when both apply.
    static let easeForFastLossKcal = 150
    static let trimSurplusKcal = -100

    // MARK: - Deficit constants

    /// Below this, a dip in performance is unlikely to be about food.
    static let meaningfulDeficitFraction = 0.10
    /// Recent enough to describe this week's training.
    static let deficitWindowDays = 7
    static let deficitMinimumDays = 4
    /// An older expenditure estimate says too little about today.
    static let deficitEstimateMaxAgeDays = 28

    // MARK: - Strength trend

    struct StrengthSet: Equatable {
        let exerciseKey: String
        let dayOffset: Int
        let weightKg: Double
        let reps: Int
        let setType: SetType
    }

    enum StrengthTrend: Equatable {
        case rising(percentPerWeek: Double)
        case flat(percentPerWeek: Double)
        case falling(percentPerWeek: Double)
        case notEnoughData(usableLifts: Int)

        var isFalling: Bool {
            if case .falling = self { true } else { false }
        }
    }

    /// The median weekly e1RM change of the top lifts over the window ending
    /// on `asOfDay`. Reps only, like records: logged RIR would make someone
    /// who starts logging it look stronger.
    static func strengthTrend(sets: [StrengthSet], asOfDay: Int) -> StrengthTrend {
        let window = (asOfDay - strengthWindowDays + 1)...asOfDay
        let eligible = sets.filter {
            window.contains($0.dayOffset)
                && $0.setType.countsTowardRecords
                && $0.weightKg > 0
                && (1...maximumTrendReps).contains($0.reps)
        }

        let lifts = Dictionary(grouping: eligible, by: \.exerciseKey)
            .compactMap { key, sets in lift(key: key, sets: sets) }
            .sorted {
                if $0.sessions != $1.sessions { return $0.sessions > $1.sessions }
                if $0.volumeKg != $1.volumeKg { return $0.volumeKg > $1.volumeKg }
                return $0.key < $1.key
            }

        guard lifts.count >= minimumLifts else { return .notEnoughData(usableLifts: lifts.count) }

        let changes = lifts.prefix(topLiftCount).map(\.percentPerWeek).sorted()
        let middle = changes.count / 2
        let median = changes.count.isMultiple(of: 2) ? (changes[middle - 1] + changes[middle]) / 2 : changes[middle]

        if median <= -strengthTrendThresholdPercent { return .falling(percentPerWeek: median) }
        if median >= strengthTrendThresholdPercent { return .rising(percentPerWeek: median) }
        return .flat(percentPerWeek: median)
    }

    private struct Lift {
        let key: String
        let sessions: Int
        let volumeKg: Double
        let percentPerWeek: Double
    }

    /// nil when the lift has too little data to count.
    private static func lift(key: String, sets: [StrengthSet]) -> Lift? {
        let bestByDay = Dictionary(grouping: sets, by: \.dayOffset).mapValues { day in
            day.map { StrengthProgression.epley(weightKg: $0.weightKg, repsToFailure: $0.reps) }.max() ?? 0
        }
        guard bestByDay.count >= minimumLiftSessions,
              let first = bestByDay.keys.min(),
              let last = bestByDay.keys.max(),
              last - first >= minimumLiftSpanDays
        else { return nil }

        let readings = bestByDay.map { ExpenditureEstimator.WeightDay(dayOffset: $0.key, weightKg: $0.value) }
        let mean = bestByDay.values.reduce(0, +) / Double(bestByDay.count)
        guard mean > 0, let slope = ExpenditureEstimator.leastSquaresSlope(readings) else { return nil }

        return Lift(
            key: key,
            sessions: bestByDay.count,
            volumeKg: sets.reduce(0) { $0 + $1.weightKg * Double($1.reps) },
            percentPerWeek: slope * 7 / mean * 100
        )
    }

    // MARK: - Check-in advice

    enum Adherence: Equatable {
        case under
        case onTarget
        case over

        init(averageIntake: Double, targetCalories: Int) {
            let target = Double(targetCalories)
            // The small margin keeps a value exactly on the edge on target
            // whatever floating point makes of it.
            if averageIntake < target * (1 - adherenceTolerance) - 1e-6 {
                self = .under
            } else if averageIntake > target * (1 + adherenceTolerance) + 1e-6 {
                self = .over
            } else {
                self = .onTarget
            }
        }
    }

    /// Why a deficit should ease. Both can apply; they share one adjustment.
    enum EaseReason: Equatable {
        case strengthFalling(percentPerWeek: Double)
        case losingTooFast(kgPerWeek: Double, goalKgPerWeek: Double)
    }

    enum Rule: Equatable {
        case easeDeficit(reasons: [EaseReason])
        case trimSurplus(kgPerWeek: Double, goalKgPerWeek: Double)
        /// A signal fired, but intake is under the target: eat up to it first.
        case eatToTarget(reasons: [EaseReason])
        /// A signal fired, but intake is over the target, so the target isn't
        /// what's driving it.
        case overTargetDeficit(reasons: [EaseReason])
        case overTargetSurplus(kgPerWeek: Double, goalKgPerWeek: Double)
        /// Gaining fast, but intake is under the target, so trimming the target
        /// wouldn't touch it.
        case underTargetSurplus(kgPerWeek: Double, goalKgPerWeek: Double)
        case onTrack
        case notEnoughTrainingData
        case noChange
    }

    struct Adjustment: Equatable {
        let deltaKcal: Int
        let targets: ExpenditureTargets
    }

    struct Advice: Equatable {
        let strength: StrengthTrend
        let previousStrength: StrengthTrend
        let rule: Rule
        /// What the rule offers on top of the proposed targets; nil when it
        /// offers nothing or the limits leave nothing to change.
        let adjustment: Adjustment?
    }

    struct Input: Equatable {
        let goal: GoalType
        let expenditure: Double
        /// What's on the profile now, which is what the intake was eaten against.
        let currentCalories: Int
        let proposedTargets: ExpenditureTargets
        let averageIntake: Double
        let weightKgPerWeek: Double
        let strength: StrengthTrend
        /// The same trend a week ago.
        let previousStrength: StrengthTrend
        let weightKg: Double
        let bmr: Double
    }

    static func advise(_ input: Input) -> Advice {
        let rule = rule(for: input)
        return Advice(
            strength: input.strength,
            previousStrength: input.previousStrength,
            rule: rule,
            adjustment: adjustment(for: rule, input: input)
        )
    }

    private static func rule(for input: Input) -> Rule {
        let adherence = Adherence(averageIntake: input.averageIntake, targetCalories: input.currentCalories)
        let goalRate = CalorieCalculator.goalWeeklyRateKg(expenditure: input.expenditure, goal: input.goal)
        let rate = input.weightKgPerWeek
        let noStrengthData = if case .notEnoughData = input.strength { true } else { false }

        switch input.goal {
        case .fatLoss:
            var reasons: [EaseReason] = []
            if case .falling(let percent) = input.strength, input.previousStrength.isFalling {
                reasons.append(.strengthFalling(percentPerWeek: percent))
            }
            if goalRate < 0, rate < goalRate * fastLossFactor {
                reasons.append(.losingTooFast(kgPerWeek: rate, goalKgPerWeek: goalRate))
            }
            guard !reasons.isEmpty else { return noStrengthData ? .notEnoughTrainingData : .noChange }
            return switch adherence {
            case .onTarget: .easeDeficit(reasons: reasons)
            case .under: .eatToTarget(reasons: reasons)
            case .over: .overTargetDeficit(reasons: reasons)
            }

        case .muscleGain:
            switch input.strength {
            case .notEnoughData: return .notEnoughTrainingData
            case .rising: return .onTrack
            case .falling: return .noChange
            case .flat:
                guard rate > goalRate * fastGainFactor else { return .noChange }
                return switch adherence {
                case .onTarget: .trimSurplus(kgPerWeek: rate, goalKgPerWeek: goalRate)
                case .over: .overTargetSurplus(kgPerWeek: rate, goalKgPerWeek: goalRate)
                case .under: .underTargetSurplus(kgPerWeek: rate, goalKgPerWeek: goalRate)
                }
            }

        case .maintain:
            switch input.strength {
            case .notEnoughData: return .notEnoughTrainingData
            case .rising: return .onTrack
            case .flat, .falling: return .noChange
            }
        }
    }

    private static func adjustment(for rule: Rule, input: Input) -> Adjustment? {
        let delta: Int
        switch rule {
        case .easeDeficit(let reasons):
            let tooFast = reasons.contains { if case .losingTooFast = $0 { true } else { false } }
            delta = tooFast ? easeForFastLossKcal : easeForStrengthKcal
        case .trimSurplus:
            delta = trimSurplusKcal
        default:
            return nil
        }
        guard let targets = CalorieCalculator.adjusted(
            input.proposedTargets,
            byKcal: delta,
            expenditure: input.expenditure,
            weightKg: input.weightKg,
            goal: input.goal,
            bmr: input.bmr
        ) else { return nil }
        return Adjustment(deltaKcal: targets.calories - input.proposedTargets.calories, targets: targets)
    }

    // MARK: - Deficit

    /// Whole percent below expenditure when the deficit is meaningful, else
    /// nil. `loggedDays` holds the window's logged intakes. Days likely half
    /// logged are left out, as in the estimator, and too few days says nothing.
    static func deficitPercent(loggedDays: [Double], expenditure: Double) -> Int? {
        guard expenditure > 0 else { return nil }
        let used = loggedDays.filter { $0 >= expenditure * ExpenditureEstimator.incompleteDayFraction }
        guard used.count >= deficitMinimumDays else { return nil }
        let average = used.reduce(0, +) / Double(used.count)
        let fraction = 1 - average / expenditure
        guard fraction >= meaningfulDeficitFraction - 1e-9 else { return nil }
        return Int((fraction * 100).rounded())
    }
}
