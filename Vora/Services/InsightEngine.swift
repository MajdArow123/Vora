//
//  InsightEngine.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import Foundation

enum InsightRule: String, CaseIterable, Codable {
    case streakMilestone
    case weightTrendPositive
    case proteinGap
    case missedWorkout
    case calorieSurplus
    case supplementGap
    case supplementStreakMilestone
}

struct Insight: Equatable, Codable {
    /// nil for the generic fallback shown when no rule matches.
    let rule: InsightRule?
    let title: String
    let message: String
    let iconName: String
}

/// Everything the rule engine needs to know about the current day,
/// captured as plain values so rules stay pure and unit-testable.
struct InsightInput {
    var date: Date
    /// Hour of day 0–23 (injected rather than read from the clock).
    var hour: Int
    var proteinConsumedG: Double
    var proteinTargetG: Int
    var caloriesConsumed: Double
    var calorieTarget: Int
    var isScheduledWorkoutDay: Bool
    var hasTrainedToday: Bool
    var streakDays: Int
    /// Most recent daily weigh-ins on consecutive calendar days ending
    /// with the latest entry, newest last. Empty when the user has no
    /// unbroken run of daily entries.
    var consecutiveDailyWeightsKg: [Double]
    var daysTracked: Int
    /// Untaken morning / pre-workout supplement names, in user order.
    var untakenEarlySupplementNames: [String] = []
    var supplementStreakDays: Int = 0
}

/// Picks one insight per day from a fixed-priority rule list. The rule
/// that produced yesterday's insight is excluded so the same rule never
/// fires two days in a row; the generic fallback is exempt.
enum InsightEngine {
    static let streakMilestones: Set<Int> = [7, 14, 30]

    static func generate(from input: InsightInput, excluding lastRule: InsightRule? = nil) -> Insight {
        let candidates: [InsightRule] = [
            .streakMilestone,
            .supplementStreakMilestone,
            .weightTrendPositive,
            .proteinGap,
            .supplementGap,
            .missedWorkout,
            .calorieSurplus,
        ]
        for rule in candidates where rule != lastRule {
            if let insight = evaluate(rule, input: input) {
                return insight
            }
        }
        return fallback(for: input)
    }

    private static func evaluate(_ rule: InsightRule, input: InsightInput) -> Insight? {
        switch rule {
        case .streakMilestone:
            guard streakMilestones.contains(input.streakDays) else { return nil }
            return Insight(
                rule: rule,
                title: "\(input.streakDays)-day streak",
                message: "You have kept your training streak alive for \(input.streakDays) days straight. Consistency like this is what moves the needle.",
                iconName: "flame.fill"
            )

        case .weightTrendPositive:
            let weights = Array(input.consecutiveDailyWeightsKg.suffix(3))
            guard weights.count == 3,
                  zip(weights.dropFirst(), weights).allSatisfy({ $0 < $1 })
            else { return nil }
            let dropKg = weights.first! - weights.last!
            return Insight(
                rule: rule,
                title: "Weight trending down",
                message: String(format: "Your weight has dropped 3 days in a row — down %.1f kg over the run. Keep doing what you are doing.", dropKg),
                iconName: "chart.line.downtrend.xyaxis"
            )

        case .proteinGap:
            guard input.hour >= 14,
                  input.proteinTargetG > 0,
                  input.proteinConsumedG < Double(input.proteinTargetG) * 0.5
            else { return nil }
            let remaining = Int((Double(input.proteinTargetG) - input.proteinConsumedG).rounded())
            return Insight(
                rule: rule,
                title: "Protein is behind",
                message: "It is past 2pm and you are under half your protein target — \(remaining) g still to go. Front-load your next meal with a protein source.",
                iconName: "fork.knife"
            )

        case .missedWorkout:
            guard input.isScheduledWorkoutDay, !input.hasTrainedToday else { return nil }
            return Insight(
                rule: rule,
                title: "Training day",
                message: "Today is a scheduled training day and no session is logged yet. Even a short session keeps the habit alive.",
                iconName: "dumbbell.fill"
            )

        case .calorieSurplus:
            guard input.calorieTarget > 0,
                  input.caloriesConsumed > Double(input.calorieTarget) + 200
            else { return nil }
            let over = Int((input.caloriesConsumed - Double(input.calorieTarget)).rounded())
            return Insight(
                rule: rule,
                title: "Over calorie target",
                message: "You are \(over) kcal over today's target. One day will not undo your progress — aim to land on target tomorrow.",
                iconName: "gauge.with.needle"
            )

        case .supplementGap:
            guard input.hour >= 14,
                  let name = input.untakenEarlySupplementNames.first
            else { return nil }
            return Insight(
                rule: rule,
                title: "Supplement missed",
                message: "You haven't taken your \(name) today.",
                iconName: "pills.fill"
            )

        case .supplementStreakMilestone:
            guard streakMilestones.contains(input.supplementStreakDays) else { return nil }
            return Insight(
                rule: rule,
                title: "\(input.supplementStreakDays)-day supplement streak",
                message: "Every supplement taken, \(input.supplementStreakDays) days running. Small habits done daily are the ones that stick.",
                iconName: "pills.fill"
            )
        }
    }

    private static func fallback(for input: InsightInput) -> Insight {
        Insight(
            rule: nil,
            title: "On track",
            message: input.daysTracked > 1
                ? "You have tracked \(input.daysTracked) days with Vora. Showing up daily is the quiet work that gets results."
                : "Log your meals, water, and training today — insights get sharper as Vora learns your patterns.",
            iconName: "checkmark.seal.fill"
        )
    }
}
