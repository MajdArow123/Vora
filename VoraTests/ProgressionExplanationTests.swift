//
//  ProgressionExplanationTests.swift
//  VoraTests
//
//  Created by Majd Arow on 2026-11-02.
//

import Foundation
import Testing
@testable import Vora

struct ProgressionExplanationTests {
    private static func recommendation(_ reason: ProgressionReason) -> Recommendation {
        Recommendation(weightKg: 100, targetReps: 10, reason: reason)
    }

    @Test(arguments: [
        ProgressionReason.raiseLoad(fromKg: 100, toKg: 102.5, topReps: 12),
        .raiseLoadEarly(fromKg: 100, toKg: 102.5, predictedReps: 8),
        .addRep(lastReps: 9, targetReps: 10),
        .repeatTop(topReps: 12),
        .atTopOfRange(topReps: 12),
        .holdTooHard(struggling: 2, total: 3),
        .holdForDeficit(struggling: 2, total: 3),
        .dropLoad(fromKg: 100, toKg: 92.5),
        .finishSets(done: 2, target: 3),
        .welcomeBack(days: 30),
        .rangeChanged(oldMin: 3, oldMax: 5, newMin: 8, newMax: 12, fromKg: 100, toKg: 92.5),
        .retargeted(actualE1RMKg: 120, predictedE1RMKg: 140),
        .extendedReps(targetReps: 13),
    ])
    func everyReasonExplainsItselfInBothUnits(reason: ProgressionReason) {
        for units in [UnitSystem.metric, .imperial] {
            let recommendation = Self.recommendation(reason)
            #expect(!ProgressionExplanation.headline(recommendation, units: units).isEmpty)
            #expect(!ProgressionExplanation.why(recommendation, units: units).isEmpty)
        }
    }

    // MARK: - Deficit

    private static func inDeficit(_ reason: ProgressionReason, percent: Int? = 18) -> Recommendation {
        var recommendation = recommendation(reason)
        recommendation.deficitPercent = percent
        return recommendation
    }

    @Test(arguments: [
        ProgressionReason.addRep(lastReps: 9, targetReps: 10),
        .repeatTop(topReps: 12),
        .holdTooHard(struggling: 2, total: 3),
        .holdForDeficit(struggling: 2, total: 3),
        .finishSets(done: 2, target: 3),
    ])
    func holdsExplainThatHoldingIsNormalInADeficit(reason: ProgressionReason) {
        let text = ProgressionExplanation.why(Self.inDeficit(reason), units: .metric)
        #expect(text.contains("holding weight is normal"))
        #expect(text.contains("18%"))
    }

    @Test(arguments: [
        ProgressionReason.addRep(lastReps: 9, targetReps: 10),
        .repeatTop(topReps: 12),
        .holdTooHard(struggling: 2, total: 3),
        .finishSets(done: 2, target: 3),
    ])
    func outsideADeficitNothingMentionsIt(reason: ProgressionReason) {
        let text = ProgressionExplanation.why(Self.recommendation(reason), units: .metric)
        #expect(!text.contains("holding weight is normal"))
        #expect(!text.contains("below what you burn"))
    }

    @Test func aFirstHardSessionSaysWhenTheWeightComesDownEitherWay() {
        let plain = ProgressionExplanation.why(Self.recommendation(.holdTooHard(struggling: 2, total: 3)), units: .metric)
        #expect(plain.contains("If it happens again, the weight comes down."))
        let deficit = ProgressionExplanation.why(Self.inDeficit(.holdTooHard(struggling: 2, total: 3)), units: .metric)
        #expect(deficit.contains("next two sessions"))
        #expect(!deficit.contains("If it happens again"))
    }

    @Test func aSecondHardSessionInADeficitSaysItGetsOneMore() {
        let text = ProgressionExplanation.why(Self.inDeficit(.holdForDeficit(struggling: 2, total: 3)), units: .metric)
        #expect(text.contains("one more session"))
        #expect(text.contains("second session in a row"))
    }

    @Test func aDropSaysHowManySessionsItTook() {
        let drop = ProgressionReason.dropLoad(fromKg: 100, toKg: 92.5)
        #expect(ProgressionExplanation.why(Self.recommendation(drop), units: .metric).contains("last two sessions"))
        let deficit = ProgressionExplanation.why(Self.inDeficit(drop), units: .metric)
        #expect(deficit.contains("last three sessions"))
        #expect(!deficit.contains("holding weight is normal"))
    }

    @Test func aHoldForTheDeficitReadsAsTheSameWeight() {
        #expect(ProgressionExplanation.headline(Self.inDeficit(.holdForDeficit(struggling: 2, total: 3)), units: .metric) == "Same weight")
    }

    @Test func weightsFollowTheUsersUnits() {
        let raise = Self.recommendation(.raiseLoad(fromKg: 100, toKg: UnitConversion.kg(fromPounds: 225), topReps: 12))
        #expect(ProgressionExplanation.headline(raise, units: .imperial) == "Up to 225 lb")
        #expect(ProgressionExplanation.why(raise, units: .imperial).contains("225 lb"))
        let metric = Self.recommendation(.raiseLoad(fromKg: 100, toKg: 102.5, topReps: 12))
        #expect(ProgressionExplanation.headline(metric, units: .metric) == "Up to 102.5 kg")
    }

    @Test func welcomeBackNamesTheGap() {
        let text = ProgressionExplanation.why(Self.recommendation(.welcomeBack(days: 30)), units: .metric)
        #expect(text.contains("30 days"))
    }

    @Test func rangeChangedSaysWhetherTheLoadMoved() {
        let moved = ProgressionExplanation.why(
            Self.recommendation(.rangeChanged(oldMin: 3, oldMax: 5, newMin: 8, newMax: 12, fromKg: 100, toKg: 92.5)),
            units: .metric
        )
        #expect(moved.contains("3–5"))
        #expect(moved.contains("8–12"))
        #expect(moved.contains("92.5 kg"))
        let kept = ProgressionExplanation.why(
            Self.recommendation(.rangeChanged(oldMin: 3, oldMax: 5, newMin: 8, newMax: 12, fromKg: 30, toKg: 30)),
            units: .metric
        )
        #expect(kept.contains("Keep 30 kg"))
    }

    @Test func retargetHeadlineFollowsTheDirection() {
        let eased = Self.recommendation(.retargeted(actualE1RMKg: 120, predictedE1RMKg: 140))
        let raised = Self.recommendation(.retargeted(actualE1RMKg: 160, predictedE1RMKg: 140))
        #expect(ProgressionExplanation.headline(eased, units: .metric) == "Eased for today")
        #expect(ProgressionExplanation.headline(raised, units: .metric) == "Raised for today")
    }

    @Test(arguments: [
        ProgressionWarning.jumpTooLarge(nextKg: 12.5, predictedReps: 3),
        .noHeavierLoad(currentKg: 40),
        .loadNotModeled,
        .snappedLoad(fromKg: 101, toKg: 100),
        .lightestLoad(currentKg: 5),
    ])
    func everyWarningHasText(warning: ProgressionWarning) {
        #expect(!ProgressionExplanation.warning(warning, units: .metric).isEmpty)
        #expect(!ProgressionExplanation.warning(warning, units: .imperial).isEmpty)
    }

    @Test func fixTitlesAreSpecific() {
        #expect(ProgressionExplanation.fixTitle(.extendReps(toReps: 13)) == "Go for 13 reps")
        #expect(ProgressionExplanation.fixTitle(.widenRange(min: 8, max: 18)) == "Change range to 8–18")
        #expect(ProgressionExplanation.fixTitle(.swapExercise) == "Swap exercise")
    }
}
