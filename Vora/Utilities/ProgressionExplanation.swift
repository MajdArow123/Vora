//
//  ProgressionExplanation.swift
//  Vora
//
//  Created by Majd Arow on 2026-11-02.
//

import Foundation

/// Plain-English text for the engine's output, in the user's units. Pure.
enum ProgressionExplanation {
    private static func weight(_ kg: Double, _ units: UnitSystem) -> String {
        UnitConversion.liftWeightText(kg: kg, units: units)
    }

    private static func reps(_ count: Int) -> String {
        count == 1 ? "1 rep" : "\(count) reps"
    }

    /// The short line under a set.
    static func headline(_ recommendation: Recommendation, units: UnitSystem) -> String {
        switch recommendation.reason {
        case .raiseLoad(_, let toKg, _), .raiseLoadEarly(_, let toKg, _):
            "Up to \(weight(toKg, units))"
        case .addRep:
            "Add a rep"
        case .repeatTop, .atTopOfRange, .holdTooHard, .holdForDeficit, .finishSets:
            "Same weight"
        case .dropLoad(_, let toKg):
            "Down to \(weight(toKg, units))"
        case .welcomeBack:
            "Welcome back"
        case .rangeChanged:
            "New rep range"
        case .retargeted(let actual, let predicted):
            actual < predicted ? "Eased for today" : "Raised for today"
        case .extendedReps(let target):
            "Go for \(reps(target))"
        }
    }

    /// Why the set has these numbers.
    static func why(_ recommendation: Recommendation, units: UnitSystem) -> String {
        let base = baseWhy(recommendation, units: units)
        guard let percent = recommendation.deficitPercent else { return base }
        switch recommendation.reason {
        case .addRep, .repeatTop, .holdTooHard, .finishSets:
            return "\(base) You're eating about \(percent)% below what you burn, so holding weight is normal right now, and keeping the load is what protects your muscle."
        default:
            return base
        }
    }

    private static func baseWhy(_ recommendation: Recommendation, units: UnitSystem) -> String {
        let inDeficit = recommendation.deficitPercent != nil
        return switch recommendation.reason {
        case .raiseLoad(_, let toKg, let topReps):
            "You hit \(reps(topReps)), the top of your range, on every set at your target effort. So the weight goes up to \(weight(toKg, units)), and reps start again from the bottom of the range."
        case .raiseLoadEarly(_, let toKg, let predicted):
            "You're in weight-first mode, and your last session suggests you can do about \(reps(predicted)) at \(weight(toKg, units)) at your target effort. That stays in your range, so the weight goes up now."
        case .addRep(let last, let target):
            "You did \(reps(last)) on this set last time, inside your range. Keep the weight and aim for \(reps(target))."
        case .repeatTop(let topReps):
            "You reached \(reps(topReps)), the top of your range, but it was harder than your target effort. Repeat it at this weight until it matches your target before adding load."
        case .atTopOfRange(let topReps):
            "You've reached \(reps(topReps)), the top of your range, and there's no good next step in weight. Stay at this weight for now."
        case .holdTooHard(let struggling, let total):
            "\(struggling) of your \(total) sets last time fell below your range or were harder than your target effort. Stay at this weight and try to settle in. "
                + (inDeficit ? "If it happens in your next two sessions too, the weight comes down." : "If it happens again, the weight comes down.")
        case .holdForDeficit(let struggling, let total):
            "\(struggling) of your \(total) sets last time fell below your range or were harder than your target effort, for the second session in a row. Normally the weight would come down now, but you're eating about \(recommendation.deficitPercent ?? 0)% below what you burn, so holding weight is normal and it gets one more session. If the next one is too hard as well, the weight comes down."
        case .dropLoad(let fromKg, let toKg):
            inDeficit
                ? "Your last three sessions at this range were too hard, even allowing for your deficit. Dropping from \(weight(fromKg, units)) to \(weight(toKg, units)) gives you room to build back up with good reps."
                : "Your last two sessions at this range were too hard. Dropping from \(weight(fromKg, units)) to \(weight(toKg, units)) gives you room to build back up with good reps."
        case .finishSets(let done, let target):
            "You did \(done) of \(target) sets at this weight last time. Stay here and complete them all before moving on."
        case .welcomeBack(let days):
            "It's been \(days) days since you last did this exercise. Same weight today, so you can see how it feels before pushing on."
        case .rangeChanged(let oldMin, let oldMax, let newMin, let newMax, let fromKg, let toKg):
            "Your rep range changed from \(rangeText(oldMin, oldMax)) to \(rangeText(newMin, newMax)), so last session's reps don't apply directly. "
                + (abs(fromKg - toKg) < 0.005
                    ? "Keep \(weight(toKg, units)) and aim for your new range."
                    : "Based on your estimated strength, \(weight(toKg, units)) should land at the bottom of the new range.")
        case .retargeted(let actual, let predicted):
            "Your first set points to an estimated 1RM of \(weight(actual, units)), compared with about \(weight(predicted, units)) expected. The remaining sets are adjusted to match how today is going."
        case .extendedReps(let target):
            "The next weight up is too big a jump for now. Build up to \(reps(target)) at this weight first, past your usual range."
        }
    }

    static func warning(_ warning: ProgressionWarning, units: UnitSystem) -> String {
        switch warning {
        case .jumpTooLarge(let nextKg, let predicted):
            "The next load, \(weight(nextKg, units)), is a big jump. You'd likely manage only \(reps(predicted)), which is below your range."
        case .noHeavierLoad(let currentKg):
            "This gym can't load more than \(weight(currentKg, units)) for this exercise."
        case .loadNotModeled:
            "Vora doesn't know what weights this equipment has. When you add load, use the smallest jump you have."
        case .snappedLoad(let fromKg, let toKg):
            "This gym can't load \(weight(fromKg, units)), so this uses the nearest weight, \(weight(toKg, units))."
        case .lightestLoad(let currentKg):
            "\(weight(currentKg, units)) is already the lightest load here, so it can't drop further."
        }
    }

    static func fixTitle(_ fix: ProgressionFix) -> String {
        switch fix {
        case .extendReps(let target): "Go for \(reps(target))"
        case .widenRange(let minReps, let maxReps): "Change range to \(rangeText(minReps, maxReps))"
        case .swapExercise: "Swap exercise"
        }
    }

    private static func rangeText(_ minReps: Int, _ maxReps: Int) -> String {
        minReps == maxReps ? "\(minReps)" : "\(minReps)–\(maxReps)"
    }
}
