//
//  WarmUpGeneratorTests.swift
//  VoraTests
//
//  Created by Majd Arow on 2026-11-02.
//

import Foundation
import Testing
@testable import Vora

struct WarmUpGeneratorTests {
    private let kgGym = LoadingInventory.standard(units: .metric)
    private let lbGym = LoadingInventory.standard(units: .imperial)

    private func sets(
        _ workingKg: Double,
        mechanics: ExerciseMechanics = .compound,
        equipment: EquipmentType = .barbell,
        inventory: LoadingInventory? = nil
    ) -> [WarmUpSet] {
        WarmUpGenerator.sets(
            workingKg: workingKg,
            mechanics: mechanics,
            equipment: equipment,
            inventory: inventory ?? kgGym
        )
    }

    private func set(_ kg: Double, _ reps: Int) -> WarmUpSet { WarmUpSet(weightKg: kg, reps: reps) }

    @Test func documentedConstants() {
        #expect(WarmUpGenerator.barReps == 10)
        #expect(WarmUpGenerator.ramp.map(\.fractionOfWorkingWeight) == [0.5, 0.7, 0.85])
        #expect(WarmUpGenerator.ramp.map(\.reps) == [5, 3, 1])
    }

    @Test func fullRampInAKgGym() {
        #expect(sets(100) == [set(20, 10), set(50, 5), set(70, 3), set(85, 1)])
    }

    @Test func stepsRoundToLoadableWeights() {
        #expect(sets(60) == [set(20, 10), set(30, 5), set(42.5, 3), set(50, 1)])
    }

    @Test func lbGymRoundsToItsOwnPlates() {
        let working = UnitConversion.kg(fromPounds: 225)
        let warmUps = sets(working, inventory: lbGym)
        #expect(warmUps.map(\.reps) == [10, 5, 3, 1])
        let pounds = warmUps.map { ($0.weightKg / UnitConversion.kg(fromPounds: 1) * 100).rounded() / 100 }
        #expect(pounds == [45, 110, 155, 190])
        let bar = lbGym.bars(for: .barbell)[0]
        for warmUp in warmUps {
            #expect(LoadCalculator.plateBreakdown(totalKg: warmUp.weightKg, bar: bar, profile: lbGym) != nil)
        }
    }

    @Test func plateLimitedGymSkipsWhatItCantMake() {
        let gym = LoadingInventory(
            bars: [GymBar(name: "Bar", weightKg: 20)],
            plates: [PlateStock(weightKg: 20, pairCount: 1)],
            dumbbellIncrementKg: 2.5,
            machineIncrementKg: 5
        )
        // Only 20 and 60 can be made: the ramp rounds to one or the other.
        #expect(sets(60, inventory: gym) == [set(20, 10)])
    }

    @Test func lightWeightsCollapse() {
        #expect(sets(30) == [set(20, 10), set(25, 1)])
        #expect(sets(25) == [set(20, 10)])
    }

    @Test func theBarAloneNeedsNoWarmUp() {
        #expect(sets(20).isEmpty)
    }

    /// 15 kg can only be made on the Women's Bar.
    @Test func staysOnTheBarThatMakesTheWeight() {
        #expect(sets(15).isEmpty)
        #expect(sets(17.5) == [set(15, 10)])
    }

    @Test func dumbbellsAndMachinesHaveNoBarStep() {
        #expect(sets(30, equipment: .dumbbell) == [set(15, 5), set(20, 3), set(25, 1)])
        #expect(sets(100, equipment: .machine) == [set(50, 5), set(70, 3), set(85, 1)])
        #expect(sets(100, equipment: .cable) == [set(50, 5), set(70, 3), set(85, 1)])
    }

    @Test func aWeightLiftedOnStepEquipmentCounts() {
        let warmUps = WarmUpGenerator.sets(
            workingKg: 102,
            mechanics: .compound,
            equipment: .machine,
            inventory: kgGym,
            loggedKg: [51]
        )
        #expect(warmUps.first == set(51, 5))
    }

    @Test func counterbalancedSmithHasNoBarStep() {
        let gym = LoadingInventory(
            bars: [GymBar(name: "Smith", weightKg: 0, kind: .smith)],
            plates: kgGym.plates,
            dumbbellIncrementKg: 2.5,
            machineIncrementKg: 5
        )
        #expect(sets(60, equipment: .smithMachine, inventory: gym) == [set(30, 5), set(42.5, 3), set(50, 1)])
    }

    @Test func isolationLiftsGetNone() {
        #expect(sets(100, mechanics: .isolation).isEmpty)
    }

    @Test func noWeightOrNoKnownLoadsGetNone() {
        #expect(sets(0).isEmpty)
        #expect(sets(-10).isEmpty)
        #expect(sets(.nan).isEmpty)
        #expect(sets(.infinity).isEmpty)
        #expect(sets(50, equipment: .kettlebell).isEmpty)
        #expect(sets(50, equipment: .bodyweight).isEmpty)
    }

    @Test(arguments: [UnitSystem.metric, UnitSystem.imperial], [EquipmentType.barbell, .dumbbell, .machine])
    func alwaysAscendingAndBelowTheWorkingWeight(units: UnitSystem, equipment: EquipmentType) {
        let gym = LoadingInventory.standard(units: units)
        for working in stride(from: 2.5, through: 300, by: 2.5) {
            let warmUps = sets(working, equipment: equipment, inventory: gym)
            #expect(warmUps.count <= WarmUpGenerator.ramp.count + 1)
            for (lighter, heavier) in zip(warmUps, warmUps.dropFirst()) {
                #expect(lighter.weightKg < heavier.weightKg)
            }
            #expect(warmUps.allSatisfy { $0.weightKg > 0 && $0.weightKg < working })
        }
    }
}
