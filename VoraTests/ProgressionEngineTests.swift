//
//  ProgressionEngineTests.swift
//  VoraTests
//
//  Created by Majd Arow on 2026-11-02.
//

import Foundation
import Testing
@testable import Vora

struct ProgressionEngineTests {
    private static let metric = LoadingInventory.standard(units: .metric)
    private static let targets = TemplateTargets(targetSets: 3, repRangeMin: 8, repRangeMax: 12, targetRIR: 2)

    private static func sets(_ weight: Double, _ reps: [Int], rir: [Int?]? = nil) -> [ProgressionSet] {
        reps.enumerated().map { index, count in
            ProgressionSet(weightKg: weight, reps: count, rir: rir.map { $0[index] } ?? 2)
        }
    }

    private static func session(
        _ weight: Double,
        _ reps: [Int],
        rir: [Int?]? = nil,
        targets: TemplateTargets? = nil
    ) -> ProgressionSession {
        ProgressionSession(sets: sets(weight, reps, rir: rir), targets: targets)
    }

    private static func input(
        _ history: [ProgressionSession],
        targets: TemplateTargets = targets,
        days: Int = 3,
        equipment: EquipmentType? = .barbell,
        inventory: LoadingInventory? = metric,
        mode: ProgressionMode = .repsFirst,
        loggedLoads: [Double] = []
    ) -> ProgressionInput {
        ProgressionInput(
            exerciseId: "barbell-bench-press",
            targets: targets,
            history: history,
            daysSinceLastSession: days,
            equipment: equipment,
            inventory: inventory,
            mode: mode,
            loggedLoadsKg: loggedLoads
        )
    }

    private static func isClose(_ lhs: Double?, _ rhs: Double) -> Bool {
        guard let lhs else { return false }
        return abs(lhs - rhs) < 0.001
    }

    // MARK: - No history

    @Test func noHistoryMeansNoRecommendation() {
        #expect(ProgressionEngine.recommend(Self.input([])).isEmpty)
        #expect(ProgressionEngine.predictedE1RM(Self.input([])) == nil)
    }

    @Test func emptyOrInvalidSessionsCountAsNoHistory() {
        let unusable = ProgressionSession(sets: [ProgressionSet(weightKg: 100, reps: 0, rir: nil)], targets: nil)
        #expect(ProgressionEngine.recommend(Self.input([unusable])).isEmpty)
        #expect(ProgressionEngine.recommend(Self.input([ProgressionSession(sets: [], targets: nil)])).isEmpty)
    }

    @Test func usesEmptySessionsSkippedToFindTheLatestReal() {
        let empty = ProgressionSession(sets: [], targets: nil)
        let result = ProgressionEngine.recommend(Self.input([empty, Self.session(100, [10, 10, 10])]))
        #expect(result.first?.weightKg == 100)
    }

    // MARK: - Deficit

    private static func deficitInput(_ history: [ProgressionSession], percent: Int? = 18) -> ProgressionInput {
        var input = input(history)
        input.deficitPercent = percent
        return input
    }

    private static let hard = session(100, [6, 6, 6])
    private static let fine = session(100, [9, 9, 9])

    @Test func withoutADeficitTwoStrugglingSessionsDrop() throws {
        let result = ProgressionEngine.recommend(Self.deficitInput([Self.hard, Self.hard], percent: nil))
        let first = try #require(result.first)
        guard case .dropLoad = first.reason else {
            Issue.record("Expected a drop, got \(first.reason)")
            return
        }
        #expect(first.deficitPercent == nil)
    }

    @Test func inADeficitTwoStrugglingSessionsHold() throws {
        let result = ProgressionEngine.recommend(Self.deficitInput([Self.hard, Self.hard]))
        let first = try #require(result.first)
        #expect(first.reason == .holdForDeficit(struggling: 3, total: 3))
        #expect(first.weightKg == 100)
        #expect(first.deficitPercent == 18)
    }

    @Test func inADeficitAThirdStrugglingSessionStillDrops() throws {
        let result = ProgressionEngine.recommend(Self.deficitInput([Self.hard, Self.hard, Self.hard]))
        let first = try #require(result.first)
        guard case .dropLoad(_, let toKg) = first.reason else {
            Issue.record("Expected a drop, got \(first.reason)")
            return
        }
        #expect(toKg < 100)
        #expect(first.weightKg == toKg)
        #expect(first.deficitPercent == 18)
    }

    @Test func aGoodSessionBetweenResetsTheCount() throws {
        let result = ProgressionEngine.recommend(Self.deficitInput([Self.hard, Self.hard, Self.fine]))
        #expect(result.first?.reason == .holdForDeficit(struggling: 3, total: 3))
    }

    @Test func oneStrugglingSessionHoldsEitherWay() {
        let plain = ProgressionEngine.recommend(Self.deficitInput([Self.hard, Self.fine], percent: nil))
        let deficit = ProgressionEngine.recommend(Self.deficitInput([Self.hard, Self.fine]))
        #expect(plain.first?.reason == .holdTooHard(struggling: 3, total: 3))
        #expect(deficit.first?.reason == .holdTooHard(struggling: 3, total: 3))
        #expect(plain.first?.deficitPercent == nil)
        #expect(deficit.first?.deficitPercent == 18)
    }

    @Test func aSessionUnderADifferentRangeIsNeverEvidenceInADeficit() {
        let other = TemplateTargets(targetSets: 3, repRangeMin: 3, repRangeMax: 5, targetRIR: 2)
        let earlier = Self.session(100, [1, 1, 1], targets: other)
        let result = ProgressionEngine.recommend(Self.deficitInput([Self.hard, Self.hard, earlier]))
        #expect(result.first?.reason == .holdForDeficit(struggling: 3, total: 3))
    }

    @Test func theLightestLoadStillWarnsOnTheThirdSession() throws {
        let bar = Self.session(20, [6, 6, 6])
        var input = Self.deficitInput([bar, bar, bar])
        input.loggedLoadsKg = []
        let first = try #require(ProgressionEngine.recommend(input).first)
        #expect(first.weightKg == 20)
        #expect(first.warnings == [.lightestLoad(currentKg: 20)])
    }

    @Test func aHoldInRangeCarriesTheDeficitButARaiseDoesnt() {
        let hold = ProgressionEngine.recommend(Self.deficitInput([Self.fine]))
        #expect(hold.first?.deficitPercent == 18)
        let raise = ProgressionEngine.recommend(Self.deficitInput([Self.session(100, [12, 12, 12])]))
        #expect(raise.first?.weightKg == 102.5)
        #expect(raise.first?.deficitPercent == nil)
    }

    @Test func aDeficitDoesntStopLoadRaises() {
        let without = ProgressionEngine.recommend(Self.deficitInput([Self.session(100, [12, 12, 12])], percent: nil))
        let with = ProgressionEngine.recommend(Self.deficitInput([Self.session(100, [12, 12, 12])]))
        #expect(without.first?.weightKg == with.first?.weightKg)
    }

    @Test func noDeficitLeavesEveryRecommendationUntagged() {
        for history in [[Self.hard], [Self.fine], [Self.session(100, [12, 12, 12])]] {
            #expect(ProgressionEngine.recommend(Self.input(history)).allSatisfy { $0.deficitPercent == nil })
        }
    }

    @Test func aDeficitRecommendationSurvivesCoding() throws {
        let original = Recommendation(
            weightKg: 100,
            targetReps: 8,
            reason: .holdForDeficit(struggling: 2, total: 3),
            deficitPercent: 18
        )
        let decoded = try JSONDecoder().decode(Recommendation.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
    }

    // MARK: - Raise

    @Test func allSetsAtTopRaisesToNextLoadAndResetsReps() {
        let result = ProgressionEngine.recommend(Self.input([Self.session(100, [12, 12, 12])]))
        #expect(result.count == 3)
        #expect(result.allSatisfy { $0.weightKg == 102.5 && $0.targetReps == 8 })
        #expect(result.first?.reason == .raiseLoad(fromKg: 100, toKg: 102.5, topReps: 12))
        #expect(result.first?.warnings == [])
    }

    @Test func oneSetBelowTopDoesNotRaise() {
        let result = ProgressionEngine.recommend(Self.input([Self.session(100, [12, 12, 11])]))
        #expect(result.allSatisfy { $0.weightKg == 100 })
        #expect(result.map(\.targetReps) == [12, 12, 12])
    }

    @Test func rirBelowTargetAtTopRepeatsInsteadOfRaising() {
        let result = ProgressionEngine.recommend(Self.input([Self.session(100, [12, 12, 12], rir: [2, 2, 1])]))
        #expect(result.allSatisfy { $0.weightKg == 100 && $0.targetReps == 12 })
        #expect(result.first?.reason == .repeatTop(topReps: 12))
    }

    @Test func nilRIRAssumesTheTargetAndCanRaise() {
        let result = ProgressionEngine.recommend(Self.input([Self.session(100, [12, 12, 12], rir: [nil, nil, nil])]))
        #expect(result.first?.weightKg == 102.5)
    }

    @Test func nilTargetRIRSkipsEffortChecks() {
        let targets = TemplateTargets(targetSets: 3, repRangeMin: 8, repRangeMax: 12, targetRIR: nil)
        let result = ProgressionEngine.recommend(Self.input(
            [Self.session(100, [12, 12, 12], rir: [0, 0, 0])],
            targets: targets
        ))
        #expect(result.first?.weightKg == 102.5)
    }

    // MARK: - Within range

    @Test func withinRangeAddsARepPerSetAndFloorsAtMin() {
        let result = ProgressionEngine.recommend(Self.input([Self.session(100, [10, 9, 8])]))
        #expect(result.allSatisfy { $0.weightKg == 100 })
        #expect(result.map(\.targetReps) == [11, 10, 9])
        #expect(result.first?.reason == .addRep(lastReps: 10, targetReps: 11))
    }

    @Test func extraTargetSetsUseTheLastSetsReps() {
        // Only the working sets of a 4-set target; the last session did 4.
        let targets = TemplateTargets(targetSets: 4, repRangeMin: 8, repRangeMax: 12, targetRIR: 2)
        let result = ProgressionEngine.recommend(Self.input([Self.session(100, [10, 9, 8, 8])], targets: targets))
        #expect(result.map(\.targetReps) == [11, 10, 9, 9])
    }

    @Test func moreSetsThanTargetOnlyJudgesTheFirstOnes() {
        // The extra fourth set, tired at 6 reps, doesn't block the raise.
        let result = ProgressionEngine.recommend(Self.input([Self.session(100, [12, 12, 12, 6])]))
        #expect(result.count == 3)
        #expect(result.first?.weightKg == 102.5)
    }

    @Test func lighterSetsAreNotWorkingSets() {
        let session = ProgressionSession(
            sets: Self.sets(60, [12]) + Self.sets(100, [12, 12, 12]),
            targets: nil
        )
        #expect(ProgressionEngine.recommend(Self.input([session])).first?.weightKg == 102.5)
    }

    // MARK: - Hold and drop

    @Test func belowMinOnMostSetsHoldsOnce() {
        let result = ProgressionEngine.recommend(Self.input([Self.session(100, [7, 7, 8])]))
        #expect(result.allSatisfy { $0.weightKg == 100 })
        #expect(result.first?.reason == .holdTooHard(struggling: 2, total: 3))
        #expect(result.map(\.targetReps) == [8, 8, 8])
    }

    @Test func exactlyMinIsNotStruggling() {
        let result = ProgressionEngine.recommend(Self.input([Self.session(100, [8, 8, 8])]))
        #expect(result.first?.reason == .addRep(lastReps: 8, targetReps: 9))
    }

    @Test func oneRepBelowTargetRIRIsNotStruggling() {
        // rir == target − 1 passes; only target − 2 and lower struggle.
        let fine = ProgressionEngine.recommend(Self.input([Self.session(100, [10, 10, 10], rir: [1, 1, 1])]))
        #expect(fine.first?.reason == .addRep(lastReps: 10, targetReps: 11))
        let hard = ProgressionEngine.recommend(Self.input([Self.session(100, [10, 10, 10], rir: [0, 0, 0])]))
        #expect(hard.first?.reason == .holdTooHard(struggling: 3, total: 3))
    }

    @Test func exactlyHalfStrugglingIsNotMost() {
        let targets = TemplateTargets(targetSets: 2, repRangeMin: 8, repRangeMax: 12, targetRIR: 2)
        let result = ProgressionEngine.recommend(Self.input([Self.session(100, [8, 7])], targets: targets))
        if case .holdTooHard = result.first?.reason {
            Issue.record("Half of the sets is not most of them")
        }
    }

    @Test func twoBadSessionsDropToAbout92Percent() {
        let bad = Self.session(100, [7, 7, 7])
        let result = ProgressionEngine.recommend(Self.input([bad, bad]))
        #expect(result.allSatisfy { $0.weightKg == 92.5 && $0.targetReps == 8 })
        #expect(result.first?.reason == .dropLoad(fromKg: 100, toKg: 92.5))
    }

    @Test func dropWithBigJumpsTakesTheNextLoadDown() {
        // 5 kg machine steps at 20 kg: 18.5 isn't loadable and 15 is outside
        // the window, so the next one down.
        let bad = Self.session(20, [7, 7, 7])
        let result = ProgressionEngine.recommend(Self.input([bad, bad], equipment: .machine))
        #expect(result.first?.weightKg == 15)
    }

    @Test func dropAtTheLightestLoadHoldsWithAWarning() {
        let bad = Self.session(5, [7, 7, 7])
        let result = ProgressionEngine.recommend(Self.input([bad, bad], equipment: .machine))
        #expect(result.first?.weightKg == 5)
        #expect(result.first?.warnings == [.lightestLoad(currentKg: 5)])
    }

    @Test func dropWithoutModeledLoadsOnlyHolds() {
        let bad = Self.session(30, [7, 7, 7])
        let result = ProgressionEngine.recommend(Self.input([bad, bad], equipment: .kettlebell))
        #expect(result.first?.weightKg == 30)
        #expect(result.first?.reason == .holdTooHard(struggling: 3, total: 3))
    }

    @Test func fewerSetsThanTargetHolds() {
        let result = ProgressionEngine.recommend(Self.input([Self.session(100, [12, 12])]))
        #expect(result.count == 3)
        #expect(result.allSatisfy { $0.weightKg == 100 })
        #expect(result.first?.reason == .finishSets(done: 2, target: 3))
    }

    // MARK: - Own snapshot

    @Test func pastSessionIsJudgedByItsOwnTargetRIR() {
        // Target now 0, but it was 3: rir 1 was too hard then, so a hold.
        let current = TemplateTargets(targetSets: 3, repRangeMin: 8, repRangeMax: 12, targetRIR: 0)
        let then = TemplateTargets(targetSets: 3, repRangeMin: 8, repRangeMax: 12, targetRIR: 3)
        let session = Self.session(100, [10, 10, 10], rir: [1, 1, 1], targets: then)
        let result = ProgressionEngine.recommend(Self.input([session], targets: current))
        #expect(result.first?.reason == .holdTooHard(struggling: 3, total: 3))
    }

    @Test func nilSnapshotFallsBackToCurrentTargets() {
        let result = ProgressionEngine.recommend(Self.input([Self.session(100, [12, 12, 12], targets: nil)]))
        #expect(result.first?.reason == .raiseLoad(fromKg: 100, toKg: 102.5, topReps: 12))
    }

    @Test func sameRangeSnapshotDoesNotRebaseline() {
        let result = ProgressionEngine.recommend(Self.input([Self.session(100, [10, 10, 10], targets: Self.targets)]))
        #expect(result.first?.reason == .addRep(lastReps: 10, targetReps: 11))
    }

    @Test func targetRIROnlyChangeDoesNotRebaseline() {
        let then = TemplateTargets(targetSets: 3, repRangeMin: 8, repRangeMax: 12, targetRIR: 1)
        let result = ProgressionEngine.recommend(Self.input([Self.session(100, [10, 10, 10], rir: [1, 1, 1], targets: then)]))
        #expect(result.first?.reason == .addRep(lastReps: 10, targetReps: 11))
    }

    @Test func pastSessionUsesItsOwnSetTarget() {
        // It was a 2-set day, done in full, so nothing to finish.
        let then = TemplateTargets(targetSets: 2, repRangeMin: 8, repRangeMax: 12, targetRIR: 2)
        let result = ProgressionEngine.recommend(Self.input([Self.session(100, [10, 10], targets: then)]))
        #expect(result.count == 3)
        #expect(result.first?.reason == .addRep(lastReps: 10, targetReps: 11))
    }

    // MARK: - Re-baseline

    @Test func higherRepRangeRebaselinesDown() throws {
        // 100×5 at 2 RIR: e1RM 123.33. At 8 + 2 reps to failure: 92.5 kg.
        let then = TemplateTargets(targetSets: 3, repRangeMin: 3, repRangeMax: 5, targetRIR: 2)
        let result = ProgressionEngine.recommend(Self.input([Self.session(100, [5, 5, 5], targets: then)]))
        let first = try #require(result.first)
        #expect(first.weightKg == 92.5)
        #expect(first.targetReps == 8)
        #expect(first.reason == .rangeChanged(oldMin: 3, oldMax: 5, newMin: 8, newMax: 12, fromKg: 100, toKg: 92.5))
    }

    @Test func lowerRepRangeRebaselinesUp() throws {
        let then = TemplateTargets(targetSets: 3, repRangeMin: 8, repRangeMax: 12, targetRIR: 2)
        let current = TemplateTargets(targetSets: 3, repRangeMin: 3, repRangeMax: 5, targetRIR: 2)
        let result = ProgressionEngine.recommend(Self.input([Self.session(100, [10, 10, 10], targets: then)], targets: current))
        let first = try #require(result.first)
        #expect(first.weightKg > 100)
        #expect(first.targetReps == 3)
        // The next load up would no longer reach the new minimum.
        let e1RM = StrengthProgression.epley(weightKg: 100, repsToFailure: 12)
        #expect(ProgressionEngine.predictedReps(e1RMKg: e1RM, atKg: first.weightKg, targetRIR: 2) >= 3)
        #expect(ProgressionEngine.predictedReps(e1RMKg: e1RM, atKg: first.weightKg + 2.5, targetRIR: 2) < 3)
    }

    @Test func rebaselineSnapsToWhatTheGymCanLoad() {
        let then = TemplateTargets(targetSets: 3, repRangeMin: 3, repRangeMax: 5, targetRIR: 2)
        let result = ProgressionEngine.recommend(Self.input(
            [Self.session(40, [5, 5, 5], targets: then)],
            equipment: .machine
        ))
        // e1RM 49.33; 37 would land at 8 reps, and 35 is the load below it.
        #expect(result.first?.weightKg == 35)
    }

    @Test func rebaselineUsesTheLightestLoadWhenNothingReachesTheMin() {
        let then = TemplateTargets(targetSets: 3, repRangeMin: 1, repRangeMax: 3, targetRIR: 0)
        let current = TemplateTargets(targetSets: 3, repRangeMin: 40, repRangeMax: 50, targetRIR: 0)
        let result = ProgressionEngine.recommend(Self.input(
            [Self.session(5, [3, 3, 3], rir: [0, 0, 0], targets: then)],
            targets: current,
            equipment: .machine
        ))
        #expect(result.first?.weightKg == 5)
        #expect(result.first?.targetReps == 40)
    }

    @Test func rebaselineWithoutModeledLoadsKeepsTheLoadAndClampsReps() {
        let then = TemplateTargets(targetSets: 3, repRangeMin: 3, repRangeMax: 5, targetRIR: 2)
        let result = ProgressionEngine.recommend(Self.input(
            [Self.session(30, [5, 5, 5], targets: then)],
            equipment: .kettlebell
        ))
        #expect(result.first?.weightKg == 30)
        #expect(result.first?.targetReps == 8)
        #expect(result.first?.reason == .rangeChanged(oldMin: 3, oldMax: 5, newMin: 8, newMax: 12, fromKg: 30, toKg: 30))
    }

    @Test func aBadSessionUnderAnotherRangeRebaselinesRatherThanDrops() {
        let then = TemplateTargets(targetSets: 3, repRangeMin: 3, repRangeMax: 5, targetRIR: 2)
        let bad = Self.session(100, [2, 2, 2], targets: then)
        let result = ProgressionEngine.recommend(Self.input([bad, bad]))
        guard case .rangeChanged = result.first?.reason else {
            Issue.record("Expected a re-baseline, got \(String(describing: result.first?.reason))")
            return
        }
    }

    @Test func noDropFromASessionDoneUnderADifferentRange() {
        // Latest was under the current range and struggled; the one before
        // was under another range, so it's no evidence for a drop.
        let other = TemplateTargets(targetSets: 3, repRangeMin: 3, repRangeMax: 5, targetRIR: 2)
        let latest = Self.session(100, [7, 7, 7], targets: Self.targets)
        let before = Self.session(120, [2, 2, 2], targets: other)
        let result = ProgressionEngine.recommend(Self.input([latest, before]))
        #expect(result.first?.weightKg == 100)
        #expect(result.first?.reason == .holdTooHard(struggling: 3, total: 3))
    }

    @Test func sameRangeSnapshotsStillDrop() {
        let bad = Self.session(100, [7, 7, 7], targets: Self.targets)
        #expect(ProgressionEngine.recommend(Self.input([bad, bad])).first?.weightKg == 92.5)
    }

    @Test func nilSnapshotBeforeCountsAsCurrentRangeForADrop() {
        let latest = Self.session(100, [7, 7, 7], targets: Self.targets)
        let before = Self.session(100, [7, 7, 7], targets: nil)
        #expect(ProgressionEngine.recommend(Self.input([latest, before])).first?.weightKg == 92.5)
    }

    // MARK: - Long gap

    @Test func exactly21DaysIsNotALongGap() {
        let result = ProgressionEngine.recommend(Self.input([Self.session(100, [12, 12, 12])], days: 21))
        #expect(result.first?.weightKg == 102.5)
    }

    @Test func over21DaysHoldsInsteadOfRaising() {
        let result = ProgressionEngine.recommend(Self.input([Self.session(100, [12, 12, 12])], days: 22))
        #expect(result.allSatisfy { $0.weightKg == 100 && $0.targetReps == 12 })
        #expect(result.first?.reason == .welcomeBack(days: 22))
    }

    @Test func longGapHoldsInsteadOfDropping() {
        let bad = Self.session(100, [7, 7, 7])
        let result = ProgressionEngine.recommend(Self.input([bad, bad], days: 30))
        #expect(result.first?.weightKg == 100)
        #expect(result.first?.targetReps == 8)
        #expect(result.first?.reason == .welcomeBack(days: 30))
    }

    @Test func longGapBeatsRebaselining() {
        let then = TemplateTargets(targetSets: 3, repRangeMin: 3, repRangeMax: 5, targetRIR: 2)
        let result = ProgressionEngine.recommend(Self.input([Self.session(100, [5, 5, 5], targets: then)], days: 30))
        #expect(result.first?.weightKg == 100)
        #expect(result.first?.targetReps == 8)
        #expect(result.first?.reason == .welcomeBack(days: 30))
    }

    @Test func longGapStillSnapsToWhatThisGymCanLoad() {
        let result = ProgressionEngine.recommend(Self.input([Self.session(101, [10, 10, 10])], days: 30))
        #expect(result.first?.weightKg == 100)
        #expect(result.first?.warnings == [.snappedLoad(fromKg: 101, toKg: 100)])
    }

    // MARK: - Modes

    @Test func weightFirstRaisesAsSoonAsTheNextLoadStaysInRange() throws {
        // 100×9 at 2 RIR: e1RM 136.67; 102.5 predicts 8 at 2 RIR.
        let result = ProgressionEngine.recommend(Self.input([Self.session(100, [9, 9, 9])], mode: .weightFirst))
        let first = try #require(result.first)
        #expect(first.weightKg == 102.5)
        #expect(first.targetReps == 8)
        #expect(first.reason == .raiseLoadEarly(fromKg: 100, toKg: 102.5, predictedReps: 8))
    }

    @Test func weightFirstAddsARepWhenTheNextLoadFallsShort() {
        // 100×8 at 2 RIR: 102.5 predicts only 7.
        let result = ProgressionEngine.recommend(Self.input([Self.session(100, [8, 8, 8])], mode: .weightFirst))
        #expect(result.first?.weightKg == 100)
        #expect(result.first?.reason == .addRep(lastReps: 8, targetReps: 9))
    }

    @Test func weightFirstRequiresTheTargetEffort() {
        let result = ProgressionEngine.recommend(Self.input(
            [Self.session(100, [11, 11, 11], rir: [1, 1, 1])],
            mode: .weightFirst
        ))
        #expect(result.first?.weightKg == 100)
    }

    @Test func repsFirstDoesNotRaiseEarly() {
        let result = ProgressionEngine.recommend(Self.input([Self.session(100, [11, 11, 11])], mode: .repsFirst))
        #expect(result.first?.weightKg == 100)
    }

    @Test func bothModesRaiseAtTheTop() {
        for mode in ProgressionMode.allCases {
            let result = ProgressionEngine.recommend(Self.input([Self.session(100, [12, 12, 12])], mode: mode))
            #expect(result.first?.reason == .raiseLoad(fromKg: 100, toKg: 102.5, topReps: 12))
        }
    }

    // MARK: - Load limits

    @Test func dumbbellJumpTooBigWarnsAndOffersFixes() throws {
        // 10 kg ×12 at 2 RIR: e1RM 14.67; 12.5 kg predicts only 3.
        let result = ProgressionEngine.recommend(Self.input([Self.session(10, [12, 12, 12])], equipment: .dumbbell))
        let first = try #require(result.first)
        #expect(first.weightKg == 10)
        #expect(first.targetReps == 12)
        #expect(first.reason == .atTopOfRange(topReps: 12))
        #expect(first.warnings == [.jumpTooLarge(nextKg: 12.5, predictedReps: 3)])
        #expect(first.fixes == [.extendReps(toReps: 13), .widenRange(min: 8, max: 18), .swapExercise])
    }

    @Test func widenFixIsDroppedWhenItWouldPassTheRepLimit() {
        // From a 20 kg bar, a single pair of 25s jumps to 70 kg.
        let result = ProgressionEngine.recommend(Self.input(
            [Self.session(20, [12, 12, 12])],
            inventory: LoadingInventory(
                bars: [GymBar(name: "Olympic", weightKg: 20)],
                plates: [PlateStock(weightKg: 25, pairCount: 1)],
                dumbbellIncrementKg: 2.5,
                machineIncrementKg: 5
            )
        ))
        #expect(result.first?.fixes == [.extendReps(toReps: 13), .swapExercise])
    }

    @Test func jumpOneRepBelowTheRangeStillRaises() {
        // A single-rep range: 102.5 predicts 7 against a min of 8, within the slack.
        let targets = TemplateTargets(targetSets: 3, repRangeMin: 8, repRangeMax: 8, targetRIR: 2)
        let result = ProgressionEngine.recommend(Self.input([Self.session(100, [8, 8, 8])], targets: targets))
        #expect(result.first?.weightKg == 102.5)
        #expect(result.first?.targetReps == 8)
    }

    @Test func noHeavierLoadWarnsWithLimitedPlates() {
        let inventory = LoadingInventory(
            bars: [GymBar(name: "Olympic", weightKg: 20)],
            plates: [PlateStock(weightKg: 10, pairCount: 1)],
            dumbbellIncrementKg: 2.5,
            machineIncrementKg: 5
        )
        let result = ProgressionEngine.recommend(Self.input([Self.session(40, [12, 12, 12])], inventory: inventory))
        #expect(result.first?.weightKg == 40)
        #expect(result.first?.warnings == [.noHeavierLoad(currentKg: 40)])
        #expect(result.first?.fixes == [.extendReps(toReps: 13), .swapExercise])
    }

    @Test func microplatesGiveTheSmallestStep() {
        let result = ProgressionEngine.recommend(Self.input([Self.session(100, [12, 12, 12])]))
        #expect(result.first?.weightKg == 102.5)
        var noMicro = Self.metric
        noMicro.plates.removeAll { $0.weightKg == 1.25 }
        let coarser = ProgressionEngine.recommend(Self.input([Self.session(100, [12, 12, 12])], inventory: noMicro))
        #expect(coarser.first?.weightKg == 105)
    }

    @Test func staysOnTheBarThatMadeTheLastLoad() {
        // No microplates: the Olympic bar steps by 5 here, and the 15 kg bar
        // can't make 100 at all, so the next load isn't a 2.5 from it.
        let inventory = LoadingInventory(
            bars: [GymBar(name: "Olympic", weightKg: 20), GymBar(name: "Women's", weightKg: 15)],
            plates: [PlateStock(weightKg: 20, pairCount: 2), PlateStock(weightKg: 5, pairCount: 2)],
            dumbbellIncrementKg: 2.5,
            machineIncrementKg: 5
        )
        let result = ProgressionEngine.recommend(Self.input([Self.session(100, [12, 12, 12])], inventory: inventory))
        #expect(result.first?.weightKg == 110)
    }

    @Test func smithMachineUsesItsOwnBar() {
        let inventory = Self.metric.addingSmithBar(ifIn: [.smithMachine], units: .metric)
        // 65 kg is the 15 kg Smith bar plus 25 a side.
        let result = ProgressionEngine.recommend(Self.input(
            [Self.session(65, [12, 12, 12])],
            equipment: .smithMachine,
            inventory: inventory
        ))
        #expect(result.first?.weightKg == 67.5)
        #expect(result.first?.warnings == [])
    }

    @Test func smithMachineWithoutABarIsNotModeled() {
        let result = ProgressionEngine.recommend(Self.input(
            [Self.session(65, [12, 12, 12])],
            equipment: .smithMachine
        ))
        #expect(result.first?.warnings == [.loadNotModeled])
    }

    @Test func lbGymStepsInPounds() throws {
        let benchLb = UnitConversion.kg(fromPounds: 185)
        let result = ProgressionEngine.recommend(Self.input(
            [Self.session(benchLb, [12, 12, 12])],
            inventory: .standard(units: .imperial)
        ))
        let first = try #require(result.first)
        #expect(Self.isClose(first.weightKg, UnitConversion.kg(fromPounds: 190)))
    }

    @Test func kgDisplayWithLbPlatesSnapsAndSaysSo() throws {
        let result = ProgressionEngine.recommend(Self.input(
            [Self.session(100, [10, 10, 10])],
            inventory: .standard(units: .imperial)
        ))
        let first = try #require(result.first)
        #expect(first.weightKg != 100)
        guard case .snappedLoad(let from, let to) = first.warnings.first else {
            Issue.record("Expected a snap warning")
            return
        }
        #expect(from == 100)
        #expect(to == first.weightKg)
        #expect(abs(first.weightKg - 100) < 1.2)
    }

    @Test func noInventoryAtTopWarnsAboutUnknownLoads() {
        let result = ProgressionEngine.recommend(Self.input([Self.session(100, [12, 12, 12])], inventory: nil))
        #expect(result.first?.weightKg == 100)
        #expect(result.first?.warnings == [.loadNotModeled])
        #expect(result.first?.fixes == [.extendReps(toReps: 13), .widenRange(min: 8, max: 14)])
    }

    @Test func customExerciseWithinRangeJustAddsReps() {
        let result = ProgressionEngine.recommend(Self.input([Self.session(55, [10, 10, 10])], equipment: nil))
        #expect(result.first?.weightKg == 55)
        #expect(result.first?.targetReps == 11)
        #expect(result.first?.warnings == [])
    }

    @Test func bodyweightProgressesRepsAtZeroLoad() {
        let result = ProgressionEngine.recommend(Self.input([Self.session(0, [12, 12, 12])], equipment: .bodyweight))
        #expect(result.first?.weightKg == 0)
        #expect(result.first?.targetReps == 12)
        #expect(result.first?.warnings == [.loadNotModeled])
    }

    @Test func kgGymWithChangedGymSnapsTheHeldLoad() {
        let result = ProgressionEngine.recommend(Self.input([Self.session(101, [10, 10, 10])]))
        #expect(result.first?.weightKg == 100)
        #expect(result.first?.warnings == [.snappedLoad(fromKg: 101, toKg: 100)])
    }

    @Test func extendRepsTopRepCappedAtTheRepLimit() {
        let targets = TemplateTargets(targetSets: 1, repRangeMin: 40, repRangeMax: 50, targetRIR: 0)
        let result = ProgressionEngine.recommend(Self.input(
            [Self.session(5, [50], rir: [0], targets: targets)],
            targets: targets,
            equipment: .kettlebell
        ))
        #expect(result.first?.fixes == [.extendReps(toReps: 50)])
    }

    // MARK: - Logged weights on step equipment

    @Test(arguments: [EquipmentType.machine, .cable])
    func aLoggedWeightOffTheGridIsKept(equipment: EquipmentType) {
        let result = ProgressionEngine.recommend(Self.input([Self.session(27.5, [10, 10, 10])], equipment: equipment))
        #expect(result.allSatisfy { $0.weightKg == 27.5 })
        #expect(result.first?.reason == .addRep(lastReps: 10, targetReps: 11))
        #expect(result.first?.warnings == [])
    }

    @Test func aLoggedDumbbellOffTheGridIsKept() {
        let result = ProgressionEngine.recommend(Self.input([Self.session(23, [10, 10, 10])], equipment: .dumbbell))
        #expect(result.first?.weightKg == 23)
        #expect(result.first?.warnings == [])
    }

    @Test func raiseFromAnOffGridWeightGoesToTheNextGridLoad() {
        let result = ProgressionEngine.recommend(Self.input([Self.session(27.5, [12, 12, 12])], equipment: .machine))
        #expect(result.first?.weightKg == 30)
        #expect(result.first?.reason == .raiseLoad(fromKg: 27.5, toKg: 30, topReps: 12))
        #expect(result.first?.warnings == [])
    }

    @Test func raiseGoesToALoggedLoadWhenItIsTheNextOneUp() {
        let result = ProgressionEngine.recommend(Self.input(
            [Self.session(27.5, [12, 12, 12])],
            equipment: .machine,
            loggedLoads: [28.75, 32.5]
        ))
        #expect(result.first?.weightKg == 28.75)
    }

    @Test func dumbbellRaiseUsesLoggedAndGridLoads() {
        let grid = ProgressionEngine.recommend(Self.input([Self.session(23, [12, 12, 12])], equipment: .dumbbell))
        #expect(grid.first?.weightKg == 25)
        let logged = ProgressionEngine.recommend(Self.input(
            [Self.session(23, [12, 12, 12])],
            equipment: .dumbbell,
            loggedLoads: [24]
        ))
        #expect(logged.first?.weightKg == 24)
    }

    @Test func aLoggedLoadBelowTheWeightDoesNotCountAsARaise() {
        let result = ProgressionEngine.recommend(Self.input(
            [Self.session(27.5, [12, 12, 12])],
            equipment: .machine,
            loggedLoads: [26, 27.5]
        ))
        #expect(result.first?.weightKg == 30)
    }

    @Test func aLoggedLoadAboveTheCeilingCanBeTheHeldLoad() {
        let result = ProgressionEngine.recommend(Self.input([Self.session(205, [10, 10, 10])], equipment: .machine))
        #expect(result.first?.weightKg == 205)
        #expect(result.first?.warnings == [])
    }

    @Test func dropCanLandOnALoggedLoad() {
        // 92.5% of 27.5 is 25.44: logged 25.5 is closer than the grid's 25.
        let bad = Self.session(27.5, [7, 7, 7])
        let grid = ProgressionEngine.recommend(Self.input([bad, bad], equipment: .machine))
        #expect(grid.first?.weightKg == 25)
        let logged = ProgressionEngine.recommend(Self.input([bad, bad], equipment: .machine, loggedLoads: [25.5]))
        #expect(logged.first?.weightKg == 25.5)
    }

    @Test func rebaselineCanLandOnALoggedLoad() {
        // e1RM 49.33: logged 37 still reaches 8 reps at 2 RIR; the grid stops at 35.
        let then = TemplateTargets(targetSets: 3, repRangeMin: 3, repRangeMax: 5, targetRIR: 2)
        let result = ProgressionEngine.recommend(Self.input(
            [Self.session(40, [5, 5, 5], targets: then)],
            equipment: .machine,
            loggedLoads: [37]
        ))
        #expect(result.first?.weightKg == 37)
    }

    @Test func retargetRaisesToALoggedLoad() {
        let result = ProgressionEngine.retarget(
            plan: Self.plan,
            firstSet: ProgressionSet(weightKg: 27.5, reps: 16, rir: 2),
            predictedE1RMKg: 30,
            input: Self.input([], equipment: .machine, loggedLoads: [28.75])
        )
        #expect(result?.first?.weightKg == 28.75)
    }

    @Test func barbellStaysPlateExactWhateverWasLogged() {
        let snapped = ProgressionEngine.recommend(Self.input([Self.session(101, [10, 10, 10])], loggedLoads: [101]))
        #expect(snapped.first?.weightKg == 100)
        #expect(snapped.first?.warnings == [.snappedLoad(fromKg: 101, toKg: 100)])
        let raised = ProgressionEngine.recommend(Self.input([Self.session(100, [12, 12, 12])], loggedLoads: [101]))
        #expect(raised.first?.weightKg == 102.5)
    }

    @Test func smithStaysPlateExactWhateverWasLogged() {
        let inventory = Self.metric.addingSmithBar(ifIn: [.smithMachine], units: .metric)
        let result = ProgressionEngine.recommend(Self.input(
            [Self.session(65, [12, 12, 12])],
            equipment: .smithMachine,
            inventory: inventory,
            loggedLoads: [66]
        ))
        #expect(result.first?.weightKg == 67.5)
    }

    @Test func kettlebellsStayUnmodeledWhateverWasLogged() {
        let result = ProgressionEngine.recommend(Self.input(
            [Self.session(24, [12, 12, 12])],
            equipment: .kettlebell,
            loggedLoads: [28]
        ))
        #expect(result.first?.weightKg == 24)
        #expect(result.first?.warnings == [.loadNotModeled])
    }

    // MARK: - Purity

    @Test func sameInputSameOutput() {
        let input = Self.input([Self.session(100, [11, 10, 9]), Self.session(97.5, [12, 12, 12])])
        let first = ProgressionEngine.recommend(input)
        for _ in 0..<20 {
            #expect(ProgressionEngine.recommend(input) == first)
        }
    }

    @Test func historyPastTheLimitIsIgnored() {
        let good = Self.session(100, [10, 10, 10])
        let old = Self.session(500, [1, 1, 1])
        let input = Self.input([good, good, good, old])
        #expect(Self.isClose(ProgressionEngine.predictedE1RM(input), StrengthProgression.epley(weightKg: 100, repsToFailure: 12)))
    }

    @Test func recommendationSurvivesCoding() throws {
        let result = ProgressionEngine.recommend(Self.input([Self.session(10, [12, 12, 12])], equipment: .dumbbell))
        let data = try JSONEncoder().encode(result)
        #expect(try JSONDecoder().decode([Recommendation].self, from: data) == result)
    }

    // MARK: - e1RM

    @Test func e1RMUsesRepsPlusRIRAsRepsToFailure() {
        let set = ProgressionSet(weightKg: 100, reps: 10, rir: 2)
        #expect(Self.isClose(ProgressionEngine.e1RM(set, assumedRIR: nil), 140))
    }

    @Test func e1RMWithNilRIRAssumesTheTarget() {
        let set = ProgressionSet(weightKg: 100, reps: 10, rir: nil)
        #expect(Self.isClose(ProgressionEngine.e1RM(set, assumedRIR: 2), 140))
        #expect(Self.isClose(ProgressionEngine.e1RM(set, assumedRIR: nil), 100 * (1 + 10.0 / 30)))
    }

    @Test func predictedE1RMIsTheMedianOfSessionBests() {
        let input = Self.input([
            Self.session(100, [10, 10, 10]),  // 140
            Self.session(90, [10, 10, 10]),   // 126
            Self.session(200, [10, 10, 10]),  // 280
        ])
        #expect(Self.isClose(ProgressionEngine.predictedE1RM(input), 140))
        let two = Self.input([Self.session(100, [10]), Self.session(90, [10])])
        #expect(Self.isClose(ProgressionEngine.predictedE1RM(two), 133))
    }

    // MARK: - Retarget

    private static let plan = [
        Recommendation(weightKg: 100, targetReps: 10, reason: .addRep(lastReps: 9, targetReps: 10)),
        Recommendation(weightKg: 100, targetReps: 10, reason: .addRep(lastReps: 9, targetReps: 10)),
    ]

    private static func retarget(firstSet: ProgressionSet, predicted: Double = 140, days: Int = 3) -> [Recommendation]? {
        ProgressionEngine.retarget(
            plan: plan,
            firstSet: firstSet,
            predictedE1RMKg: predicted,
            input: input([], days: days)
        )
    }

    @Test func nearThePredictionLeavesThePlanAlone() {
        #expect(Self.retarget(firstSet: ProgressionSet(weightKg: 100, reps: 10, rir: 2)) == nil)
    }

    @Test func justUnderTheThresholdDoesNotRetarget() {
        // 100×10 at 2 RIR is 140; predicted just far enough to stay under 7.5%.
        let predicted = 140 / (1 - ProgressionEngine.retargetThreshold + 0.001)
        #expect(Self.retarget(firstSet: ProgressionSet(weightKg: 100, reps: 10, rir: 2), predicted: predicted) == nil)
    }

    @Test func justOverTheThresholdRetargets() {
        let predicted = 140 / (1 - ProgressionEngine.retargetThreshold - 0.001)
        #expect(Self.retarget(firstSet: ProgressionSet(weightKg: 100, reps: 10, rir: 2), predicted: predicted) != nil)
    }

    @Test func weakFirstSetMovesTheRestDown() throws {
        // 100×6 at 2 RIR: e1RM 126.67, 9.5% under 140, and 100 predicts 6 < min.
        let result = try #require(Self.retarget(firstSet: ProgressionSet(weightKg: 100, reps: 6, rir: 2)))
        #expect(result.count == 2)
        let first = try #require(result.first)
        #expect(first.weightKg < 100)
        #expect(first.targetReps >= 8)
        guard case .retargeted(let actual, let predicted) = first.reason else {
            Issue.record("Expected a retarget reason")
            return
        }
        #expect(Self.isClose(actual, StrengthProgression.epley(weightKg: 100, repsToFailure: 8)))
        #expect(predicted == 140)
    }

    @Test func strongFirstSetMovesTheRestUpIntoTheRange() throws {
        // 100×16 at 2 RIR: predicts 16 at 100, past the range.
        let result = try #require(Self.retarget(firstSet: ProgressionSet(weightKg: 100, reps: 16, rir: 2)))
        let first = try #require(result.first)
        #expect(first.weightKg > 100)
        #expect((8...12).contains(first.targetReps))
    }

    @Test func aTypoInTheFirstSetRaisesOneLoadStepAtMost() throws {
        // 34 reps typed for 3 would otherwise predict 150 kg and more.
        let result = try #require(Self.retarget(firstSet: ProgressionSet(weightKg: 100, reps: 34, rir: 2)))
        #expect(result.first?.weightKg == 102.5)
        #expect(result.first?.targetReps == 12)
    }

    @Test func strongFirstSetInRangeKeepsTheLoadAndRaisesReps() throws {
        // Predicted 125: 100×10 at 2 RIR is 12% over and still fits the range.
        let result = try #require(Self.retarget(firstSet: ProgressionSet(weightKg: 100, reps: 10, rir: 2), predicted: 125))
        #expect(result.first?.weightKg == 100)
        #expect(result.first?.targetReps == 10)
    }

    @Test func nilRIRRetargetAssumesTheTarget() {
        let hard = ProgressionSet(weightKg: 100, reps: 6, rir: nil)
        #expect(Self.retarget(firstSet: hard) != nil)
    }

    @Test func afterALongGapOnlyAWeakSetRetargets() {
        let strong = ProgressionSet(weightKg: 100, reps: 16, rir: 2)
        let weak = ProgressionSet(weightKg: 100, reps: 6, rir: 2)
        #expect(Self.retarget(firstSet: strong, days: 22) == nil)
        #expect(Self.retarget(firstSet: strong, days: 21) != nil)
        #expect(Self.retarget(firstSet: weak, days: 22) != nil)
    }

    @Test func retargetWithoutPredictionOrLoadDoesNothing() {
        #expect(Self.retarget(firstSet: ProgressionSet(weightKg: 100, reps: 6, rir: 2), predicted: 0) == nil)
        #expect(Self.retarget(firstSet: ProgressionSet(weightKg: 0, reps: 6, rir: 2)) == nil)
    }

    @Test func unmodeledRetargetKeepsTheLoadAndClampsReps() throws {
        let result = try #require(ProgressionEngine.retarget(
            plan: Self.plan,
            firstSet: ProgressionSet(weightKg: 100, reps: 6, rir: 2),
            predictedE1RMKg: 140,
            input: Self.input([], equipment: .kettlebell)
        ))
        #expect(result.first?.weightKg == 100)
        #expect(result.first?.targetReps == 8)
    }

    // MARK: - Fix results

    @Test func extendingRepsClearsWarnings() {
        let warned = Recommendation(
            weightKg: 10,
            targetReps: 12,
            reason: .atTopOfRange(topReps: 12),
            warnings: [.noHeavierLoad(currentKg: 10)],
            fixes: [.extendReps(toReps: 13)]
        )
        let extended = ProgressionEngine.extendingReps(warned, toReps: 13)
        #expect(extended.weightKg == 10)
        #expect(extended.targetReps == 13)
        #expect(extended.reason == .extendedReps(targetReps: 13))
        #expect(extended.warnings.isEmpty)
        #expect(extended.fixes.isEmpty)
    }
}
