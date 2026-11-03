//
//  CoachingExplanation.swift
//  Vora
//
//  Created by Majd Arow on 2026-11-03.
//

import Foundation

/// Plain-English text for the check-in's Training section, in the user's
/// units. Pure.
enum CoachingExplanation {
    /// One line on how strength is going.
    static func strengthSummary(_ trend: CoachingEngine.StrengthTrend) -> String {
        switch trend {
        case .rising(let percent):
            "Your top lifts are going up about \(percentText(percent)) a week."
        case .flat:
            "Your top lifts are holding steady."
        case .falling(let percent):
            "Your top lifts are going down about \(percentText(percent)) a week."
        case .notEnoughData(let usable):
            "Not enough training data to judge strength yet. Vora needs at least \(CoachingEngine.minimumLifts) lifts, each done \(CoachingEngine.minimumLiftSessions) or more times over at least \(CoachingEngine.minimumLiftSpanDays) of the last \(CoachingEngine.strengthWindowDays) days. So far it has \(usable)."
        }
    }

    /// What the rule means, and why.
    static func detail(_ advice: CoachingEngine.Advice, units: UnitSystem) -> String {
        switch advice.rule {
        case .easeDeficit(let reasons):
            let lead = reasons.map { reasonText($0, units: units) }.joined(separator: " ")
            guard advice.adjustment != nil else {
                return "\(lead) Your calories are already as high as your plan allows, so there's nothing to add this week."
            }
            return "\(lead) Easing the deficit a little should help you keep your muscle."
        case .trimSurplus(let rate, let goal):
            let lead = gainText(rate: rate, goal: goal, units: units)
            guard advice.adjustment != nil else {
                return "\(lead) Your calories are already at the lowest your plan allows, so there's nothing to trim this week."
            }
            return "\(lead) With strength flat, the extra is likely going to fat, so a smaller surplus should serve you better."
        case .eatToTarget(let reasons):
            let lead = reasons.map { reasonText($0, units: units) }.joined(separator: " ")
            return "\(lead) You're also eating below your target, so raising it wouldn't change anything. Try eating up to your target first."
        case .overTargetDeficit(let reasons):
            let lead = reasons.map { reasonText($0, units: units) }.joined(separator: " ")
            return "\(lead) You're eating above your target already, so the target isn't what's behind this. No calorie change this week."
        case .overTargetSurplus(let rate, let goal):
            return "\(gainText(rate: rate, goal: goal, units: units)) You're eating above your target, so lowering it wouldn't change much. Try eating closer to your target first."
        case .underTargetSurplus(let rate, let goal):
            return "\(gainText(rate: rate, goal: goal, units: units)) You're eating below your target, so lowering it wouldn't touch this. No calorie change this week."
        case .onTrack:
            return "Strength is going up on your current calories, so you're on track."
        case .notEnoughTrainingData:
            return "Vora won't guess, so there's no training-based suggestion this week."
        case .noChange:
            return "Nothing here calls for a calorie change this week."
        }
    }

    /// e.g. "+150 kcal" or "-100 kcal".
    static func adjustmentText(_ adjustment: CoachingEngine.Adjustment) -> String {
        adjustment.deltaKcal > 0 ? "+\(adjustment.deltaKcal) kcal" : "\(adjustment.deltaKcal) kcal"
    }

    /// The line under a day's target with calorie cycling on; nil with it off.
    static func dayNote(_ day: DayTargets) -> String? {
        switch day.kind {
        case .training:
            return "Training day"
        case .rest:
            guard let trained = day.ifTrainedCalories else { return "Rest day" }
            return "Rest day. Train today and this becomes \(trained.formatted()) kcal."
        case nil:
            return nil
        }
    }

    private static func reasonText(_ reason: CoachingEngine.EaseReason, units: UnitSystem) -> String {
        switch reason {
        case .strengthFalling:
            "Your strength has been falling for two check-ins in a row, which can mean the deficit is too deep."
        case .losingTooFast(let rate, let goal):
            "You're losing \(weeklyText(rate, units)) against a goal of about \(weeklyText(goal, units)), which risks losing muscle along with fat."
        }
    }

    private static func gainText(rate: Double, goal: Double, units: UnitSystem) -> String {
        "You're gaining \(weeklyText(rate, units)) against a goal of about \(weeklyText(goal, units))."
    }

    /// The size of a weekly change, e.g. "0.9 kg/week".
    private static func weeklyText(_ kgPerWeek: Double, _ units: UnitSystem) -> String {
        "\(UnitConversion.bodyWeightText(kg: abs(kgPerWeek), units: units))/week"
    }

    private static func percentText(_ percent: Double) -> String {
        "\(abs(percent).formatted(.number.precision(.fractionLength(1))))%"
    }
}
