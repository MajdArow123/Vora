//
//  WarmUpGenerator.swift
//  Vora
//
//  Created by Majd Arow on 2026-11-02.
//

import Foundation

/// A suggested warm-up set.
nonisolated struct WarmUpSet: Equatable {
    let weightKg: Double
    let reps: Int
}

/// Ramp-up sets for the first working weight of a compound lift. Pure: takes
/// plain values and touches no storage.
nonisolated enum WarmUpGenerator {
    struct Step: Equatable {
        let fractionOfWorkingWeight: Double
        let reps: Int
    }

    /// The empty bar, on bar-loaded equipment only.
    static let barReps = 10
    /// Enough to groove the movement and feel the load without tiring it.
    static let ramp = [
        Step(fractionOfWorkingWeight: 0.5, reps: 5),
        Step(fractionOfWorkingWeight: 0.7, reps: 3),
        Step(fractionOfWorkingWeight: 0.85, reps: 1),
    ]
    /// Loads closer than this are the same load, as in `LoadCalculator`.
    private static let toleranceKg = 0.005

    /// Nothing for isolation lifts, a weight of zero, or equipment with no
    /// known loads. Each step rounds to the nearest load this gym can make,
    /// staying on the bar that can make the working weight. A step is skipped
    /// when it wouldn't be heavier than the one before, or wouldn't be lighter
    /// than the working weight, so light lifts collapse to fewer sets.
    static func sets(
        workingKg: Double,
        mechanics: ExerciseMechanics,
        equipment: EquipmentType,
        inventory: LoadingInventory,
        loggedKg: [Double] = []
    ) -> [WarmUpSet] {
        guard mechanics == .compound, workingKg > 0, workingKg.isFinite else { return [] }
        let loads = LoadCalculator.workingLoads(
            equipment: equipment,
            profile: inventory,
            referenceKg: workingKg,
            loggedKg: loggedKg
        )
        guard !loads.isEmpty else { return [] }

        var result: [WarmUpSet] = []
        var heaviestKg = 0.0
        func add(_ kg: Double, reps: Int) {
            guard kg > heaviestKg + toleranceKg, kg < workingKg - toleranceKg else { return }
            result.append(WarmUpSet(weightKg: kg, reps: reps))
            heaviestKg = kg
        }

        if !LoadCalculator.usesStepLoads(equipment), let bar = LoadCalculator.preferredBar(
            forKg: workingKg,
            equipment: equipment,
            profile: inventory
        ) {
            add(bar.weightKg, reps: barReps)
        }
        for step in ramp {
            let target = workingKg * step.fractionOfWorkingWeight
            add(LoadCalculator.nearest(toKg: target, in: loads, rounding: .nearest), reps: step.reps)
        }
        return result
    }
}
