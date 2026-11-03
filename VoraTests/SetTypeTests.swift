//
//  SetTypeTests.swift
//  VoraTests
//
//  Created by Majd Arow on 2026-11-02.
//

import Foundation
import Testing
@testable import Vora

struct SetTypeTests {
    /// Persisted in the store and the draft, so these can never change.
    @Test func rawValuesArePinned() {
        #expect(SetType.allCases.map(\.rawValue) == ["normal", "warmUp", "drop", "failure", "myoRep"])
        #expect(SetSide.allCases.map(\.rawValue) == ["left", "right"])
    }

    @Test func nilAndUnknownStoredValuesAreNormal() {
        #expect(SetType(stored: nil) == .normal)
        #expect(SetType(stored: "giantSet") == .normal)
        #expect(SetType(stored: "drop") == .drop)
        #expect(SetEntry(setNumber: 1, weightKg: 50, reps: 5).setType == .normal)
        #expect(SetEntry(setNumber: 1, weightKg: 50, reps: 5).setTypeRawValue == nil)
    }

    @Test func consumerRulesTable() {
        let rules: [(SetType, records: Bool, working: Bool, volume: Bool, training: Bool)] = [
            (.normal, true, true, true, true),
            (.failure, true, true, true, true),
            (.drop, false, false, true, true),
            (.myoRep, false, false, true, true),
            (.warmUp, false, false, false, false),
        ]
        #expect(rules.count == SetType.allCases.count)
        for rule in rules {
            #expect(rule.0.countsTowardRecords == rule.records)
            #expect(rule.0.isWorkingSet == rule.working)
            #expect(rule.0.countsTowardVolume == rule.volume)
            #expect(rule.0.countsAsTrainingSet == rule.training)
        }
    }

    @Test func failureImpliesRIRZeroUnlessLogged() {
        #expect(SetEntry(setNumber: 1, weightKg: 50, reps: 5, setType: .failure).effectiveRIR == 0)
        #expect(SetEntry(setNumber: 1, weightKg: 50, reps: 5, rir: 2, setType: .failure).effectiveRIR == 2)
        // Never stored: "not logged" stays true in the data.
        #expect(SetEntry(setNumber: 1, weightKg: 50, reps: 5, setType: .failure).rir == nil)
        for type in SetType.allCases where type != .failure {
            #expect(SetEntry(setNumber: 1, weightKg: 50, reps: 5, setType: type).effectiveRIR == nil)
        }
    }

    @Test func aLeftAndRightPairIsOneTrainingSet() {
        let pair: [(type: SetType, side: SetSide?)] = [(.normal, .left), (.normal, .right)]
        #expect(SetCounting.trainingSetCount(pair) == 1)
        #expect(SetCounting.trainingSetCount(pair + pair) == 2)
        #expect(SetCounting.trainingSetCount([(.normal, .left)]) == 1)
        #expect(SetCounting.trainingSetCount(pair + [(.normal, .left)]) == 2)
        #expect(SetCounting.trainingSetCount(pair + [(.normal, nil)]) == 2)
    }

    @Test func warmUpsAreNotTrainingSets() {
        #expect(SetCounting.trainingSetCount([(.warmUp, nil), (.warmUp, .left), (.drop, nil), (.myoRep, nil), (.failure, nil)]) == 3)
    }

    @Test func labelsNumberNormalSetsAmongThemselves() {
        #expect(SetCounting.labels([.warmUp, .warmUp, .normal, .normal, .failure, .normal, .drop, .myoRep])
                == ["W", "W", "1", "2", "F", "3", "D", "M"])
    }

    @Test func supersetGroupsAreDenseConsecutiveAndNeverAlone() {
        #expect(SetCounting.normalizedSupersetGroups([]) == [])
        #expect(SetCounting.normalizedSupersetGroups([nil, nil]) == [nil, nil])
        #expect(SetCounting.normalizedSupersetGroups([7, 7, nil, 3, 3, 3]) == [1, 1, nil, 2, 2, 2])
        // Lone exercises lose the link.
        #expect(SetCounting.normalizedSupersetGroups([1, nil, 2, 2]) == [nil, nil, 1, 1])
        // A later run of the same number is its own group.
        #expect(SetCounting.normalizedSupersetGroups([1, 1, nil, 1, 1]) == [1, 1, nil, 2, 2])
        // Something moved into the middle splits the group.
        #expect(SetCounting.normalizedSupersetGroups([1, nil, 1]) == [nil, nil, nil])
    }
}
