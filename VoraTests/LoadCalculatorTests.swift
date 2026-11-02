//
//  LoadCalculatorTests.swift
//  VoraTests
//
//  Created by Majd Arow on 2026-11-02.
//

import Foundation
import Testing
@testable import Vora

struct LoadCalculatorTests {
    private static let olympic = GymBar(name: "Olympic", weightKg: 20)

    private static func inventory(
        bars: [GymBar] = [olympic],
        plates: [(Double, Int)],
        dumbbell: Double = 2.5,
        machine: Double = 5
    ) -> LoadingInventory {
        LoadingInventory(
            bars: bars,
            plates: plates.map { PlateStock(weightKg: $0.0, pairCount: $0.1) },
            dumbbellIncrementKg: dumbbell,
            machineIncrementKg: machine
        )
    }

    private static func lb(_ pounds: Double) -> Double { UnitConversion.kg(fromPounds: pounds) }

    private static func isClose(_ lhs: Double, _ rhs: Double) -> Bool { abs(lhs - rhs) < 0.001 }

    // MARK: - plateBreakdown: kg gyms

    @Test func breaksDownAStandardKgLoadHeaviestFirst() {
        let stack = LoadCalculator.plateBreakdown(
            totalKg: 102.5, bar: Self.olympic, profile: .standard(units: .metric)
        )
        #expect(stack == [
            PlateCount(weightKg: 25, countPerSide: 1),
            PlateCount(weightKg: 15, countPerSide: 1),
            PlateCount(weightKg: 1.25, countPerSide: 1),
        ])
    }

    @Test func repeatsAPlateWhenPairsAllow() {
        let stack = LoadCalculator.plateBreakdown(
            totalKg: 120, bar: Self.olympic, profile: .standard(units: .metric)
        )
        #expect(stack == [PlateCount(weightKg: 25, countPerSide: 2)])
    }

    @Test func barWeightAloneNeedsNoPlates() {
        #expect(LoadCalculator.plateBreakdown(totalKg: 20, bar: Self.olympic, profile: .standard(units: .metric)) == [])
    }

    @Test func usesTheGivenBarsWeight() {
        let bar = GymBar(name: "EZ", weightKg: 10)
        let stack = LoadCalculator.plateBreakdown(totalKg: 20, bar: bar, profile: .standard(units: .metric))
        #expect(stack == [PlateCount(weightKg: 5, countPerSide: 1)])
    }

    // MARK: - plateBreakdown: impossible loads

    @Test func loadBelowTheBarIsImpossible() {
        #expect(LoadCalculator.plateBreakdown(totalKg: 15, bar: Self.olympic, profile: .standard(units: .metric)) == nil)
    }

    @Test func loadBetweenPlatesIsImpossible() {
        #expect(LoadCalculator.plateBreakdown(totalKg: 21, bar: Self.olympic, profile: .standard(units: .metric)) == nil)
    }

    @Test func loadBeyondTheInventoryIsImpossible() {
        let inventory = Self.inventory(plates: [(25, 2)])
        #expect(LoadCalculator.plateBreakdown(totalKg: 120, bar: Self.olympic, profile: inventory)?.count == 1)
        #expect(LoadCalculator.plateBreakdown(totalKg: 170, bar: Self.olympic, profile: inventory) == nil)
    }

    @Test func noPlatesCanOnlyMakeTheBar() {
        let inventory = Self.inventory(plates: [])
        #expect(LoadCalculator.plateBreakdown(totalKg: 20, bar: Self.olympic, profile: inventory) == [])
        #expect(LoadCalculator.plateBreakdown(totalKg: 25, bar: Self.olympic, profile: inventory) == nil)
    }

    @Test(arguments: [Double.nan, .infinity, -.infinity, 1e20, -5, 0])
    func unusableTotalsAreImpossibleAndDontTrap(total: Double) {
        #expect(LoadCalculator.plateBreakdown(totalKg: total, bar: Self.olympic, profile: .standard(units: .metric)) == nil)
    }

    @Test(arguments: [0, -20, Double.nan])
    func unusableBarsAreImpossible(weight: Double) {
        let bar = GymBar(name: "Broken", weightKg: weight)
        #expect(LoadCalculator.plateBreakdown(totalKg: 40, bar: bar, profile: .standard(units: .metric)) == nil)
    }

    // MARK: - plateBreakdown: limited counts

    /// Taking the largest plate that fits leaves 5 per side with no answer.
    @Test func backtracksWhereGreedyFails() {
        let inventory = Self.inventory(plates: [(25, 1), (20, 1), (10, 1)])
        let stack = LoadCalculator.plateBreakdown(totalKg: 80, bar: Self.olympic, profile: inventory)
        #expect(stack == [
            PlateCount(weightKg: 20, countPerSide: 1),
            PlateCount(weightKg: 10, countPerSide: 1),
        ])
    }

    @Test func respectsPairCounts() {
        let inventory = Self.inventory(plates: [(10, 2), (5, 1)])
        #expect(LoadCalculator.plateBreakdown(totalKg: 70, bar: Self.olympic, profile: inventory) == [
            PlateCount(weightKg: 10, countPerSide: 2),
            PlateCount(weightKg: 5, countPerSide: 1),
        ])
        #expect(LoadCalculator.plateBreakdown(totalKg: 80, bar: Self.olympic, profile: inventory) == nil)
    }

    @Test func aSinglePairGivesOnePlatePerSide() {
        let inventory = Self.inventory(plates: [(25, 1)])
        #expect(LoadCalculator.plateBreakdown(totalKg: 70, bar: Self.olympic, profile: inventory)
                == [PlateCount(weightKg: 25, countPerSide: 1)])
        #expect(LoadCalculator.plateBreakdown(totalKg: 120, bar: Self.olympic, profile: inventory) == nil)
    }

    @Test func ignoresInvalidPlatesAndMergesDuplicates() {
        let inventory = Self.inventory(plates: [(10, 0), (0, 4), (-5, 4), (5, 1), (5, 1)])
        #expect(LoadCalculator.plateBreakdown(totalKg: 40, bar: Self.olympic, profile: inventory)
                == [PlateCount(weightKg: 5, countPerSide: 2)])
        #expect(LoadCalculator.plateBreakdown(totalKg: 60, bar: Self.olympic, profile: inventory) == nil)
    }

    @Test func impossibleLoadOnLargeOddStockFinishesQuickly() {
        let inventory = Self.inventory(plates: [(25, 20), (20, 20), (15, 20), (10, 20), (5, 20), (2.5, 20)])
        #expect(LoadCalculator.plateBreakdown(totalKg: 1001, bar: Self.olympic, profile: inventory) == nil)
    }

    // MARK: - plateBreakdown: microplates

    @Test func microplatesMakeSmallJumps() {
        let inventory = LoadingInventory.standard(units: .metric)
        #expect(LoadCalculator.plateBreakdown(totalKg: 22.5, bar: Self.olympic, profile: inventory)
                == [PlateCount(weightKg: 1.25, countPerSide: 1)])
        #expect(LoadCalculator.plateBreakdown(totalKg: 25, bar: Self.olympic, profile: inventory)
                == [PlateCount(weightKg: 2.5, countPerSide: 1)])
    }

    @Test func withoutMicroplatesSmallJumpsAreImpossible() {
        let inventory = Self.inventory(plates: [(5, 2), (2.5, 2)])
        #expect(LoadCalculator.plateBreakdown(totalKg: 22.5, bar: Self.olympic, profile: inventory) == nil)
    }

    @Test func oneMicroplatePairCantMakeTwoPerSide() {
        let inventory = Self.inventory(plates: [(1.25, 1)])
        #expect(LoadCalculator.plateBreakdown(totalKg: 25, bar: Self.olympic, profile: inventory) == nil)
    }

    // MARK: - plateBreakdown: lb gyms

    @Test func lbGymLoadsWhatLbInputConvertsTo() throws {
        let inventory = LoadingInventory.standard(units: .imperial)
        let bar = try #require(inventory.bars.first)
        let total = try #require(UnitConversion.parseWeight("225", units: .imperial))

        let stack = LoadCalculator.plateBreakdown(totalKg: total, bar: bar, profile: inventory)

        #expect(stack == [PlateCount(weightKg: Self.lb(45), countPerSide: 2)])
    }

    @Test func lbGymHandlesSmallPlates() throws {
        let inventory = LoadingInventory.standard(units: .imperial)
        let bar = try #require(inventory.bars.first)
        let total = try #require(UnitConversion.parseWeight("140", units: .imperial))

        #expect(LoadCalculator.plateBreakdown(totalKg: total, bar: bar, profile: inventory) == [
            PlateCount(weightKg: Self.lb(45), countPerSide: 1),
            PlateCount(weightKg: Self.lb(2.5), countPerSide: 1),
        ])
    }

    @Test func kgPlatesCantMakeARoundLbLoad() throws {
        let total = try #require(UnitConversion.parseWeight("135", units: .imperial))
        #expect(LoadCalculator.plateBreakdown(
            totalKg: total, bar: Self.olympic, profile: .standard(units: .metric)
        ) == nil)
    }

    @Test func mixedKgAndLbStockCombines() {
        let inventory = Self.inventory(plates: [(25, 1), (Self.lb(10), 1)])
        #expect(LoadCalculator.plateBreakdown(
            totalKg: 70 + 2 * Self.lb(10), bar: Self.olympic, profile: inventory
        ) == [
            PlateCount(weightKg: 25, countPerSide: 1),
            PlateCount(weightKg: Self.lb(10), countPerSide: 1),
        ])
    }

    // MARK: - plateBreakdown: floating-point drift

    @Test func floatDriftDoesntBreakAMatch() {
        let inventory = Self.inventory(plates: [(0.1, 3)])
        // 0.1 + 0.1 + ... accumulates binary error a direct comparison would see.
        let drifted = (0..<6).reduce(20.0) { total, _ in total + 0.1 }
        #expect(LoadCalculator.plateBreakdown(totalKg: drifted, bar: Self.olympic, profile: inventory)
                == [PlateCount(weightKg: 0.1, countPerSide: 3)])
    }

    // MARK: - achievableLoads

    @Test func barbellLoadsAreEveryCombination() {
        let inventory = Self.inventory(plates: [(5, 1), (2.5, 1)])
        #expect(LoadCalculator.achievableLoads(equipment: .barbell, profile: inventory) == [20, 25, 30, 35])
    }

    @Test func barbellLoadsCoverEveryBarWithoutDuplicates() {
        let inventory = Self.inventory(
            bars: [Self.olympic, GymBar(name: "Women's", weightKg: 15)],
            plates: [(5, 1), (2.5, 1)]
        )
        #expect(LoadCalculator.achievableLoads(equipment: .barbell, profile: inventory) == [15, 20, 25, 30, 35])
    }

    @Test func barbellLoadsRespectPairCounts() {
        let inventory = Self.inventory(plates: [(10, 2)])
        #expect(LoadCalculator.achievableLoads(equipment: .barbell, profile: inventory) == [20, 40, 60])
    }

    @Test func barbellWithNoBarsHasNoLoads() {
        let inventory = Self.inventory(bars: [], plates: [(10, 2)])
        #expect(LoadCalculator.achievableLoads(equipment: .barbell, profile: inventory).isEmpty)
    }

    @Test func barWithNoPlatesIsTheOnlyLoad() {
        #expect(LoadCalculator.achievableLoads(equipment: .barbell, profile: Self.inventory(plates: [])) == [20])
    }

    @Test(arguments: [LoadingInventory.standard(units: .metric), .standard(units: .imperial)])
    func barbellLoadsAreSortedUniqueAndEachHasABreakdown(inventory: LoadingInventory) throws {
        let bar = try #require(inventory.bars.first)
        let loads = LoadCalculator.plateLoads(bar: bar, profile: inventory)

        #expect(loads == loads.sorted())
        #expect(Set(loads).count == loads.count)
        #expect(loads.first.map { Self.isClose($0, bar.weightKg) } == true)
        for load in loads {
            let stack = LoadCalculator.plateBreakdown(totalKg: load, bar: bar, profile: inventory)
            let rebuilt = (stack ?? []).reduce(bar.weightKg) { $0 + 2 * $1.weightKg * Double($1.countPerSide) }
            #expect(stack != nil, "No breakdown for \(load)")
            #expect(Self.isClose(rebuilt, load), "\(rebuilt) != \(load)")
        }
    }

    @Test func mixedStockStaysBoundedAndSorted() {
        var plates = LoadingInventory.standard(units: .metric).plates
        plates += LoadingInventory.standard(units: .imperial).plates
        let inventory = LoadingInventory(
            bars: [Self.olympic], plates: plates, dumbbellIncrementKg: 2.5, machineIncrementKg: 5
        )
        let loads = LoadCalculator.achievableLoads(equipment: .barbell, profile: inventory)
        #expect(loads.count > 100)
        #expect(loads == loads.sorted())
    }

    @Test func dumbbellLoadsStepToTheCeiling() {
        let loads = LoadCalculator.achievableLoads(equipment: .dumbbell, profile: Self.inventory(plates: []))
        #expect(loads.first == 2.5)
        #expect(loads.last == LoadCalculator.dumbbellCeilingKg)
        #expect(loads.count == 32)
    }

    @Test(arguments: [EquipmentType.machine, .cable])
    func machineLikeEquipmentUsesTheMachineStep(equipment: EquipmentType) {
        let loads = LoadCalculator.achievableLoads(equipment: equipment, profile: Self.inventory(plates: []))
        #expect(loads.first == 5)
        #expect(loads.last == LoadCalculator.machineCeilingKg)
        #expect(loads.count == 40)
    }

    @Test(arguments: [EquipmentType.kettlebell, .resistanceBand, .pullUpBar, .bench, .bodyweight])
    func equipmentWithoutModeledLoadsHasNone(equipment: EquipmentType) {
        #expect(LoadCalculator.achievableLoads(equipment: equipment, profile: .standard(units: .metric)).isEmpty)
    }

    @Test(arguments: [0, -2.5, Double.nan])
    func unusableStepsHaveNoLoads(step: Double) {
        let inventory = Self.inventory(plates: [], dumbbell: step, machine: step)
        #expect(LoadCalculator.achievableLoads(equipment: .dumbbell, profile: inventory).isEmpty)
        #expect(LoadCalculator.achievableLoads(equipment: .machine, profile: inventory).isEmpty)
    }

    @Test func lbDumbbellStepsConvertBackToRoundPounds() throws {
        let loads = LoadCalculator.achievableLoads(equipment: .dumbbell, profile: .standard(units: .imperial))
        let second = try #require(loads.dropFirst().first)
        #expect(UnitConversion.weightNumberText(kg: second, units: .imperial) == "10")
    }

    // MARK: - nearestAchievable

    private static let simple = inventory(plates: [(5, 1), (2.5, 1)])

    private static func nearest(_ target: Double, _ rounding: LoadRounding, equipment: EquipmentType = .barbell) -> Double {
        LoadCalculator.nearestAchievable(targetKg: target, equipment: equipment, profile: simple, rounding: rounding)
    }

    @Test func downReturnsTheHeaviestAtOrBelow() {
        #expect(Self.nearest(29.9, .down) == 25)
        #expect(Self.nearest(30, .down) == 30)
    }

    @Test func downBelowEveryLoadReturnsTheLightest() {
        #expect(Self.nearest(10, .down) == 20)
    }

    @Test func downAboveEveryLoadReturnsTheHeaviest() {
        #expect(Self.nearest(500, .down) == 35)
    }

    @Test func nearestPicksTheCloser() {
        #expect(Self.nearest(26, .nearest) == 25)
        #expect(Self.nearest(29, .nearest) == 30)
    }

    @Test func nearestBreaksTiesDownward() {
        #expect(Self.nearest(27.5, .nearest) == 25)
    }

    @Test func nearestClampsToTheEnds() {
        #expect(Self.nearest(1, .nearest) == 20)
        #expect(Self.nearest(500, .nearest) == 35)
    }

    @Test func exactLoadsComeBackUnchanged() {
        #expect(Self.nearest(25, .nearest) == 25)
        #expect(Self.nearest(25, .down) == 25)
    }

    @Test func snapsDumbbellsToTheStep() {
        #expect(Self.nearest(23, .down, equipment: .dumbbell) == 22.5)
        #expect(Self.nearest(24.5, .nearest, equipment: .dumbbell) == 25)
    }

    @Test func equipmentWithNoLoadsReturnsTheTarget() {
        #expect(Self.nearest(42, .down, equipment: .bodyweight) == 42)
        #expect(Self.nearest(42, .nearest, equipment: .kettlebell) == 42)
    }

    @Test func nonFiniteTargetComesBackUnchanged() {
        #expect(Self.nearest(.nan, .down).isNaN)
        #expect(Self.nearest(.infinity, .nearest) == .infinity)
    }

    // MARK: - Caption text

    @Test func stackTextJoinsPlatesAndMarksRepeats() {
        let stack = [PlateCount(weightKg: 25, countPerSide: 2), PlateCount(weightKg: 2.5, countPerSide: 1)]
        #expect(PlateStackText.summary(stack, units: .metric) == "25 ×2 + 2.5")
        #expect(PlateStackText.summary([], units: .metric) == "Bar only")
    }

    @Test func stackTextUsesTheDisplayUnit() {
        let stack = [PlateCount(weightKg: Self.lb(45), countPerSide: 1)]
        #expect(PlateStackText.summary(stack, units: .imperial) == "45")
    }

    // MARK: - Barbell exercises

    private static func exercise(id: String?, name: String) -> ActiveSessionViewModel.DraftExercise {
        ActiveSessionViewModel.DraftExercise(
            name: name, exerciseId: id, muscleGroups: [], sets: [], previousSets: [], restSeconds: 90, targets: nil
        )
    }

    @Test func barbellExercisesAreIdentifiedByID() {
        #expect(Self.exercise(id: "barbell-bench-press", name: "Renamed").plateLoadedEquipment == .barbell)
        #expect(Self.exercise(id: "lateral-raise", name: "Barbell Lateral Raise").plateLoadedEquipment == nil)
    }

    @Test func customExercisesNeverUseTheCalculator() {
        #expect(Self.exercise(id: nil, name: "Barbell Bench Press").plateLoadedEquipment == nil)
    }

    @Test func plateLoadedEquipmentPrefersTheBarbell() {
        #expect(LoadingInventory.plateLoadedEquipment(in: [.barbell, .bench]) == .barbell)
        #expect(LoadingInventory.plateLoadedEquipment(in: [.smithMachine, .bench]) == .smithMachine)
        #expect(LoadingInventory.plateLoadedEquipment(in: [.barbell, .smithMachine]) == .barbell)
        #expect(LoadingInventory.plateLoadedEquipment(in: [.machine, .dumbbell]) == nil)
    }

    // MARK: - Smith machines

    private static func smithInventory(barKg: Double, plates: [(Double, Int)]) -> LoadingInventory {
        inventory(bars: [olympic, GymBar(name: "Smith bar", weightKg: barKg, kind: .smith)], plates: plates)
    }

    @Test func smithLoadsUseTheSmithBarAndPlates() {
        let inventory = Self.smithInventory(barKg: 15, plates: [(5, 1), (2.5, 1)])
        #expect(LoadCalculator.achievableLoads(equipment: .smithMachine, profile: inventory) == [15, 20, 25, 30])
    }

    @Test func barbellLoadsIgnoreTheSmithBar() {
        let inventory = Self.smithInventory(barKg: 15, plates: [(5, 1), (2.5, 1)])
        #expect(LoadCalculator.achievableLoads(equipment: .barbell, profile: inventory) == [20, 25, 30, 35])
    }

    @Test func smithWithoutASmithBarHasNoLoads() {
        let inventory = Self.inventory(plates: [(5, 1)])
        #expect(LoadCalculator.achievableLoads(equipment: .smithMachine, profile: inventory).isEmpty)
    }

    @Test func smithIgnoresTheMachineStep() {
        let inventory = Self.smithInventory(barKg: 15, plates: [])
        #expect(LoadCalculator.achievableLoads(equipment: .smithMachine, profile: inventory) == [15])
    }

    @Test func nearestAchievableSnapsSmithToPlates() {
        let inventory = Self.smithInventory(barKg: 15, plates: [(5, 1), (2.5, 1)])
        #expect(LoadCalculator.nearestAchievable(
            targetKg: 24, equipment: .smithMachine, profile: inventory, rounding: .down
        ) == 20)
    }

    @Test func smithBreaksDownFromItsOwnBar() {
        let bar = GymBar(name: "Smith bar", weightKg: 15, kind: .smith)
        #expect(LoadCalculator.plateBreakdown(totalKg: 35, bar: bar, profile: .standard(units: .metric))
                == [PlateCount(weightKg: 10, countPerSide: 1)])
    }

    @Test func lbSmithBreaksDownInPounds() throws {
        let bar = LoadingInventory.smithBar(units: .imperial)
        let total = try #require(UnitConversion.parseWeight("125", units: .imperial))
        #expect(LoadCalculator.plateBreakdown(totalKg: total, bar: bar, profile: .standard(units: .imperial))
                == [PlateCount(weightKg: Self.lb(45), countPerSide: 1)])
    }

    @Test func counterbalancedSmithStartsAtZero() {
        let inventory = Self.smithInventory(barKg: 0, plates: [(5, 1)])
        let bar = GymBar(name: "Smith bar", weightKg: 0, kind: .smith)
        #expect(LoadCalculator.achievableLoads(equipment: .smithMachine, profile: inventory) == [0, 10])
        #expect(LoadCalculator.plateBreakdown(totalKg: 10, bar: bar, profile: inventory)
                == [PlateCount(weightKg: 5, countPerSide: 1)])
        #expect(LoadCalculator.plateBreakdown(totalKg: 0, bar: bar, profile: inventory) == [])
    }

    @Test func aNegativeSmithBarIsUnusable() {
        let bar = GymBar(name: "Smith bar", weightKg: -5, kind: .smith)
        let inventory = Self.inventory(bars: [bar], plates: [(5, 1)])
        #expect(LoadCalculator.plateBreakdown(totalKg: 10, bar: bar, profile: inventory) == nil)
        #expect(LoadCalculator.achievableLoads(equipment: .smithMachine, profile: inventory).isEmpty)
    }

    // MARK: - Plate calculator input

    private static func sessionViewModel(units: UnitSystem = .metric) -> (
        viewModel: ActiveSessionViewModel,
        request: ActiveSessionViewModel.PlateCalculatorRequest
    ) {
        let viewModel = ActiveSessionViewModel(sessionName: "Push", units: units, health: NoHealthWrites())
        var set = ActiveSessionViewModel.DraftSet(units: units)
        set.setWeight(kg: 85)
        let exercise = ActiveSessionViewModel.DraftExercise(
            name: "Barbell Bench Press", exerciseId: "barbell-bench-press", muscleGroups: [],
            sets: [set], previousSets: [], restSeconds: 120, targets: nil
        )
        viewModel.exercises = [exercise]
        return (viewModel, .init(setID: set.id, exerciseID: exercise.id))
    }

    /// Regression: a tap can land after the text changed but before the row
    /// re-renders, and a weight copied at that moment stayed on the sheet.
    /// A request made before an edit must still read the edited value.
    @Test func plateCalculatorReadsTheSetsWeightAfterAnEdit() {
        let (viewModel, request) = Self.sessionViewModel()
        #expect(viewModel.plateCalculatorWeightKg(for: request) == 85)

        viewModel.exercises[0].sets[0].weightText = "8"
        #expect(viewModel.plateCalculatorWeightKg(for: request) == 8)

        viewModel.exercises[0].sets[0].weightText = "86"
        #expect(viewModel.plateCalculatorWeightKg(for: request) == 86)
    }

    @Test func plateCalculatorParsesEditsInTheDisplayUnit() {
        let (viewModel, request) = Self.sessionViewModel(units: .imperial)
        viewModel.exercises[0].sets[0].weightText = "225"
        #expect(viewModel.plateCalculatorWeightKg(for: request) == Self.lb(225))
    }

    @Test func plateCalculatorHasNoWeightForAClearedOrRemovedSet() {
        let (viewModel, request) = Self.sessionViewModel()
        viewModel.exercises[0].sets[0].weightText = ""
        #expect(viewModel.plateCalculatorWeightKg(for: request) == nil)

        viewModel.exercises[0].sets[0].weightText = "85"
        viewModel.removeSet(request.setID, from: request.exerciseID)
        #expect(viewModel.plateCalculatorWeightKg(for: request) == nil)
    }
}
