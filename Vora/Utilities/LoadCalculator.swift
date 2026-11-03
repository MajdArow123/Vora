//
//  LoadCalculator.swift
//  Vora
//
//  Created by Majd Arow on 2026-11-02.
//

import Foundation

nonisolated enum LoadRounding {
    case down
    case nearest
}

/// Plates of one weight on each side of the bar.
nonisolated struct PlateCount: Equatable {
    let weightKg: Double
    let countPerSide: Int
}

/// Works out which loads a gym's equipment can make. Pure: takes plain
/// values and touches no storage. Sums run in integer milligrams so that
/// floating-point drift can't break a match, and loads within `toleranceMg`
/// (far below any real plate) count as the same load.
nonisolated enum LoadCalculator {
    /// Upper bounds for equipment described only by a step.
    static let dumbbellCeilingKg = 80.0
    static let machineCeilingKg = 200.0

    private static let milligramsPerKg = 1_000_000.0
    private static let toleranceMg = 5_000
    /// Beyond any real load, and small enough to convert to Int safely.
    private static let largestWeightKg = 1_000_000.0

    /// Every load the equipment can make, sorted ascending. Barbells and
    /// Smith machines take plates; barbell loads cover all of the gym's free
    /// bars and Smith loads its Smith bar. Equipment with no modeled load
    /// (kettlebells, bands, bodyweight, benches, pull-up bars) returns [].
    static func achievableLoads(equipment: EquipmentType, profile: LoadingInventory) -> [Double] {
        switch equipment {
        case .barbell, .smithMachine:
            let loads = profile.bars(for: equipment).flatMap { plateLoadsMg(bar: $0, profile: profile) }
            return kilograms(collapsed(loads))
        case .dumbbell:
            return multiples(of: profile.dumbbellIncrementKg, upTo: dumbbellCeilingKg)
        case .machine, .cable:
            return multiples(of: profile.machineIncrementKg, upTo: machineCeilingKg)
        case .kettlebell, .resistanceBand, .pullUpBar, .bench, .bodyweight:
            return []
        }
    }

    /// Every load one bar can make, sorted ascending, starting at the bar.
    static func plateLoads(bar: GymBar, profile: LoadingInventory) -> [Double] {
        kilograms(collapsed(plateLoadsMg(bar: bar, profile: profile)))
    }

    /// The achievable load closest to the target. `.down` never goes over
    /// the target unless the target is below every load, where it returns
    /// the lightest. `.nearest` breaks ties downward. With nothing achievable
    /// the target comes back unchanged, as there is nothing to snap to.
    static func nearestAchievable(
        targetKg: Double,
        equipment: EquipmentType,
        profile: LoadingInventory,
        rounding: LoadRounding,
        loggedKg: [Double] = []
    ) -> Double {
        let loads = usesStepLoads(equipment)
            ? achievableLoads(equipment: equipment, profile: profile, addingLogged: loggedKg)
            : achievableLoads(equipment: equipment, profile: profile)
        return nearest(toKg: targetKg, in: loads, rounding: rounding)
    }

    /// Whether the equipment is described by a step rather than exact plates.
    static func usesStepLoads(_ equipment: EquipmentType) -> Bool {
        switch equipment {
        case .dumbbell, .machine, .cable: true
        default: false
        }
    }

    /// The step grid plus every weight actually lifted on this equipment. A
    /// step is only an approximation of a real stack, so a logged weight is
    /// proof it can be loaded, even off the grid or above the ceiling.
    private static func achievableLoads(
        equipment: EquipmentType,
        profile: LoadingInventory,
        addingLogged loggedKg: [Double]
    ) -> [Double] {
        let logged = loggedKg.filter { $0 > 0 }.compactMap(milligrams)
        let grid = achievableLoads(equipment: equipment, profile: profile).compactMap(milligrams)
        return kilograms(collapsed(grid + logged))
    }

    /// `nearestAchievable` over an already computed, ascending list of loads.
    static func nearest(toKg targetKg: Double, in loads: [Double], rounding: LoadRounding) -> Double {
        guard let lightest = loads.first, let targetMg = milligrams(targetKg) else { return targetKg }

        switch rounding {
        case .down:
            return loads.last { load in
                milligrams(load).map { $0 <= targetMg + toleranceMg } ?? false
            } ?? lightest
        case .nearest:
            var best = lightest
            var bestDistance = Int.max
            for load in loads {
                guard let loadMg = milligrams(load) else { continue }
                let distance = abs(loadMg - targetMg)
                if distance < bestDistance {
                    best = load
                    bestDistance = distance
                }
            }
            return best
        }
    }

    /// The lightest load strictly above `aboveKg`, or nil when none is.
    static func nextAchievable(aboveKg: Double, in loads: [Double]) -> Double? {
        guard let aboveMg = milligrams(aboveKg) else { return nil }
        return loads.first { load in
            milligrams(load).map { $0 > aboveMg + toleranceMg } ?? false
        }
    }

    /// The bar a load belongs on: the first that can make it, else the first.
    static func preferredBar(forKg totalKg: Double, equipment: EquipmentType, profile: LoadingInventory) -> GymBar? {
        let bars = profile.bars(for: equipment)
        return bars.first { plateBreakdown(totalKg: totalKg, bar: $0, profile: profile) != nil } ?? bars.first
    }

    /// The loads to progress within. `achievableLoads` merges every bar, so
    /// a step there could silently mean changing bars; plate-loaded
    /// equipment stays on the bar that can make the reference load, exactly
    /// as plated. Step equipment also counts `loggedKg`: weights already
    /// lifted on it.
    static func workingLoads(
        equipment: EquipmentType,
        profile: LoadingInventory,
        referenceKg: Double,
        loggedKg: [Double] = []
    ) -> [Double] {
        if usesStepLoads(equipment) {
            return achievableLoads(equipment: equipment, profile: profile, addingLogged: loggedKg)
        }
        switch equipment {
        case .barbell, .smithMachine:
            return preferredBar(forKg: referenceKg, equipment: equipment, profile: profile)
                .map { plateLoads(bar: $0, profile: profile) } ?? []
        default:
            return achievableLoads(equipment: equipment, profile: profile)
        }
    }

    /// The closest loads this bar can make on either side of a total.
    static func nearestLoads(aroundKg totalKg: Double, bar: GymBar, profile: LoadingInventory) -> (below: Double?, above: Double?) {
        guard let totalMg = milligrams(totalKg) else { return (nil, nil) }
        let loads = plateLoads(bar: bar, profile: profile)
        let below = loads.last { load in milligrams(load).map { $0 < totalMg - toleranceMg } ?? false }
        return (below, nextAchievable(aboveKg: totalKg, in: loads))
    }

    /// The plates to put on each side, heaviest first, or nil when the total
    /// can't be made with this bar and these pairs. An empty result means
    /// the bar alone. Searches rather than taking the largest plate that
    /// fits: from one pair each of 25, 20 and 10, 30 per side is 20 + 10.
    static func plateBreakdown(totalKg: Double, bar: GymBar, profile: LoadingInventory) -> [PlateCount]? {
        guard let totalMg = milligrams(totalKg), let barMg = barWeightMg(bar) else { return nil }

        let needed = totalMg - barMg
        if abs(needed) <= toleranceMg { return [] }
        guard needed > 0 else { return nil }

        let stock = plateStock(profile)
        var deadEnds = Set<SearchState>()
        guard let counts = search(
            index: 0,
            remainingMg: needed,
            stock: stock,
            deadEnds: &deadEnds
        ) else { return nil }

        return zip(stock, counts).compactMap { plate, count in
            count > 0 ? PlateCount(weightKg: plate.weightKg, countPerSide: count) : nil
        }
    }

    // MARK: - Search

    private struct Plate {
        let weightKg: Double
        let weightMg: Int
        let pairCount: Int
    }

    private struct SearchState: Hashable {
        let index: Int
        let remainingMg: Int
    }

    /// Picks a count for each plate, largest counts first, so the first
    /// answer found is the one with the heaviest plates.
    private static func search(
        index: Int,
        remainingMg: Int,
        stock: [Plate],
        deadEnds: inout Set<SearchState>
    ) -> [Int]? {
        if abs(remainingMg) <= toleranceMg {
            return Array(repeating: 0, count: stock.count - index)
        }
        guard index < stock.count, remainingMg > 0 else { return nil }

        let state = SearchState(index: index, remainingMg: remainingMg)
        guard !deadEnds.contains(state) else { return nil }

        let plate = stock[index]
        // A pair adds its weight to both sides.
        let pairMg = plate.weightMg * 2
        let mostThatFit = min(plate.pairCount, (remainingMg + toleranceMg) / pairMg)
        for count in stride(from: mostThatFit, through: 0, by: -1) {
            if let rest = search(
                index: index + 1,
                remainingMg: remainingMg - count * pairMg,
                stock: stock,
                deadEnds: &deadEnds
            ) {
                return [count] + rest
            }
        }
        deadEnds.insert(state)
        return nil
    }

    // MARK: - Helpers

    /// Usable plates, heaviest first, with duplicate weights merged.
    private static func plateStock(_ profile: LoadingInventory) -> [Plate] {
        var pairsByWeight: [Int: (weightKg: Double, pairs: Int)] = [:]
        for plate in profile.plates where plate.pairCount > 0 {
            guard let weightMg = milligrams(plate.weightKg), weightMg > 0 else { continue }
            let pairs = pairsByWeight[weightMg]?.pairs ?? 0
            pairsByWeight[weightMg] = (plate.weightKg, pairs + plate.pairCount)
        }
        return pairsByWeight
            .map { Plate(weightKg: $0.value.weightKg, weightMg: $0.key, pairCount: $0.value.pairs) }
            .sorted { $0.weightMg > $1.weightMg }
    }

    /// Nil for an unusable bar. Only a counterbalanced Smith bar can be 0.
    private static func barWeightMg(_ bar: GymBar) -> Int? {
        guard let barMg = milligrams(bar.weightKg) else { return nil }
        switch bar.kind {
        case .free: return barMg > 0 ? barMg : nil
        case .smith: return barMg >= 0 ? barMg : nil
        }
    }

    private static func plateLoadsMg(bar: GymBar, profile: LoadingInventory) -> [Int] {
        guard let barMg = barWeightMg(bar) else { return [] }

        // Collapsing after each plate keeps this bounded for mixed kg and lb
        // stock, whose sums would otherwise multiply.
        var perSide = [0]
        for plate in plateStock(profile) {
            var next = perSide
            for count in 1...plate.pairCount {
                next += perSide.map { $0 + count * plate.weightMg }
            }
            perSide = collapsed(next)
        }
        return perSide.map { barMg + $0 * 2 }
    }

    /// Sorted, with loads within the tolerance of each other merged.
    private static func collapsed(_ values: [Int]) -> [Int] {
        var result: [Int] = []
        for value in values.sorted() {
            if let last = result.last, value - last <= toleranceMg { continue }
            result.append(value)
        }
        return result
    }

    private static func multiples(of stepKg: Double, upTo ceilingKg: Double) -> [Double] {
        guard let stepMg = milligrams(stepKg), stepMg > 0,
              let ceilingMg = milligrams(ceilingKg)
        else { return [] }
        return kilograms(Array(stride(from: stepMg, through: ceilingMg + toleranceMg, by: stepMg)))
    }

    private static func kilograms(_ values: [Int]) -> [Double] {
        values.map { Double($0) / milligramsPerKg }
    }

    /// Nil for values that aren't a usable weight, such as NaN or a typed
    /// number too large to convert.
    private static func milligrams(_ kg: Double) -> Int? {
        guard kg.isFinite, abs(kg) <= largestWeightKg else { return nil }
        return Int((kg * milligramsPerKg).rounded())
    }
}
