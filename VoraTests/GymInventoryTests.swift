//
//  GymInventoryTests.swift
//  VoraTests
//
//  Created by Majd Arow on 2026-11-02.
//

import Foundation
import SwiftData
import Testing
@testable import Vora

@MainActor
struct GymInventoryTests {
    private let container: ModelContainer
    private let context: ModelContext

    init() throws {
        let schema = Schema([GymProfile.self, UserProfile.self])
        container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        context = container.mainContext
    }

    private static func makeUser(units: UnitSystem) -> UserProfile {
        UserProfile(
            name: "User",
            dateOfBirth: .distantPast,
            heightCm: 180,
            biologicalSex: .male,
            goalType: .maintain,
            activityLevel: .moderatelyActive,
            trainingSplit: .ppl,
            dailyCalorieTarget: 2500,
            proteinTargetG: 160,
            carbsTargetG: 280,
            fatTargetG: 80,
            preferredUnits: units
        )
    }

    private static func lb(_ pounds: Double) -> Double { UnitConversion.kg(fromPounds: pounds) }

    private static func commercialDefault(_ units: UnitSystem) -> LoadingInventory {
        GymPreset.commercial.defaultInventory(units: units, equipment: GymPreset.commercial.defaultEquipment)
    }

    // MARK: - Preset defaults

    @Test func standardKgSetIsWhatThePresetTableSays() {
        let inventory = LoadingInventory.standard(units: .metric)
        #expect(inventory.bars.map(\.weightKg) == [20, 15, 10])
        #expect(inventory.bars.allSatisfy { $0.kind == .free })
        #expect(inventory.plates.map(\.weightKg) == [25, 20, 15, 10, 5, 2.5, 1.25])
        #expect(inventory.plates.map(\.pairCount) == [8, 2, 2, 2, 2, 2, 2])
        #expect(inventory.dumbbellIncrementKg == 2.5)
        #expect(inventory.machineIncrementKg == 5)
    }

    @Test func standardLbSetIsStoredInKg() {
        let inventory = LoadingInventory.standard(units: .imperial)
        #expect(inventory.bars.map(\.weightKg) == [45, 35, 25].map(Self.lb))
        #expect(inventory.plates.map(\.weightKg) == [45, 35, 25, 10, 5, 2.5].map(Self.lb))
        #expect(inventory.dumbbellIncrementKg == Self.lb(5))
        #expect(inventory.machineIncrementKg == Self.lb(10))
    }

    @Test(arguments: [GymPreset.homeDumbbells, .hotel, .bodyweightOnly], [UnitSystem.metric, .imperial])
    func presetsWithoutABarbellHaveNoBarsOrPlates(preset: GymPreset, units: UnitSystem) {
        let inventory = preset.defaultInventory(units: units, equipment: preset.defaultEquipment)
        #expect(inventory.bars.isEmpty)
        #expect(inventory.plates.isEmpty)
        #expect(inventory.dumbbellIncrementKg == LoadingInventory.standard(units: units).dumbbellIncrementKg)
    }

    @Test func customMatchesCommercial() {
        let equipment: Set<EquipmentType> = [.barbell, .smithMachine]
        #expect(GymPreset.custom.defaultInventory(units: .metric, equipment: equipment)
                == GymPreset.commercial.defaultInventory(units: .metric, equipment: equipment))
    }

    // MARK: - Smith bar

    @Test func smithBarDefaultsAreFifteenKgAndThirtyFiveLb() {
        #expect(LoadingInventory.smithBar(units: .metric) == GymBar(name: "Smith bar", weightKg: 15, kind: .smith))
        #expect(LoadingInventory.smithBar(units: .imperial)
                == GymBar(name: "Smith bar", weightKg: Self.lb(35), kind: .smith))
    }

    @Test(arguments: [UnitSystem.metric, .imperial])
    func aGymWithASmithMachineGetsASmithBar(units: UnitSystem) {
        let gym = GymProfile(name: "Big", preset: .commercial, inventoryUnits: units)
        #expect(gym.loadingInventory?.bars(for: .smithMachine) == [LoadingInventory.smithBar(units: units)])
        #expect(gym.loadingInventory?.bars(for: .barbell) == LoadingInventory.standard(units: units).bars)
    }

    @Test func aGymWithoutASmithMachineGetsNoSmithBar() {
        let gym = GymProfile(
            name: "Garage", preset: .custom, availableEquipment: [.barbell, .bench], inventoryUnits: .metric
        )
        #expect(gym.loadingInventory == .standard(units: .metric))
    }

    @Test(arguments: [GymPreset.homeDumbbells, .hotel, .bodyweightOnly])
    func presetsWithoutASmithMachineGetNoSmithBar(preset: GymPreset) {
        let gym = GymProfile(name: "Gym", preset: preset, inventoryUnits: .metric)
        #expect(gym.loadingInventory?.bars(for: .smithMachine) == [])
    }

    @Test func aSmithOnlyGymHasPlatesAndItsBar() {
        let gym = GymProfile(name: "Small", preset: .custom, availableEquipment: [.smithMachine], inventoryUnits: .metric)
        #expect(gym.loadingInventory?.bars(for: .smithMachine).count == 1)
        #expect(gym.loadingInventory?.plates == LoadingInventory.standard(units: .metric).plates)
    }

    @Test func backfillAddsASmithBarOnlyToGymsWithASmithMachine() throws {
        context.insert(Self.makeUser(units: .imperial))
        let with = GymProfile(name: "With", preset: .custom, availableEquipment: [.barbell, .smithMachine])
        let without = GymProfile(name: "Without", preset: .custom, availableEquipment: [.barbell])
        context.insert(with)
        context.insert(without)
        try context.save()

        #expect(try GymInventoryBackfill.run(in: context) == 2)

        #expect(with.loadingInventory?.bars(for: .smithMachine) == [LoadingInventory.smithBar(units: .imperial)])
        #expect(without.loadingInventory?.bars(for: .smithMachine) == [])
    }

    @Test func aCounterbalancedSmithBarPersists() throws {
        let gym = GymProfile(name: "Big", preset: .commercial, inventoryUnits: .metric)
        var inventory = try #require(gym.loadingInventory)
        let index = try #require(inventory.bars.firstIndex { $0.kind == .smith })
        inventory.bars[index].weightKg = 0
        gym.updateInventory(inventory)
        context.insert(gym)
        try context.save()

        let fresh = ModelContext(container)
        let reread = try #require(try fresh.fetch(FetchDescriptor<GymProfile>()).first)
        #expect(reread.loadingInventory?.bars(for: .smithMachine).first?.weightKg == 0)
        #expect(reread.loadingInventory?.bars(for: .smithMachine).first?.kind == .smith)
    }

    // MARK: - When defaults are written

    @Test func aGymWithoutUnitsStaysUnfilled() {
        #expect(GymProfile(name: "Seeded", preset: .commercial).loadingInventory == nil)
    }

    @Test func aGymCreatedWithUnitsIsFilledImmediately() {
        let gym = GymProfile(name: "New", preset: .commercial, inventoryUnits: .imperial)
        #expect(gym.loadingInventory == Self.commercialDefault(.imperial))
    }

    @Test func applyPresetWritesDefaultsImmediately() {
        let gym = GymProfile(name: "Trip", preset: .commercial, inventoryUnits: .metric)
        gym.applyPreset(.hotel, units: .imperial)
        #expect(gym.loadingInventory == .withoutBarbell(units: .imperial))
    }

    @Test func applyingCustomKeepsAnEditedInventory() {
        let gym = GymProfile(name: "Garage", preset: .commercial, inventoryUnits: .metric)
        var edited = LoadingInventory.standard(units: .metric)
        edited.plates = [PlateStock(weightKg: 20, pairCount: 1)]
        gym.updateInventory(edited)

        gym.applyPreset(.custom, units: .imperial)

        #expect(gym.loadingInventory == edited)
    }

    @Test func applyingCustomFillsAnUnfilledGym() {
        let gym = GymProfile(name: "Garage", preset: .commercial)
        gym.applyPreset(.custom, units: .imperial)
        #expect(gym.loadingInventory == Self.commercialDefault(.imperial))
    }

    @Test func fillingLeavesAnEditedInventoryAlone() {
        let gym = GymProfile(name: "Gym", preset: .commercial, inventoryUnits: .metric)
        #expect(!gym.fillInventoryIfNeeded(units: .imperial))
        #expect(gym.loadingInventory == Self.commercialDefault(.metric))
    }

    // MARK: - Switching units

    @Test func switchingUnitsDoesNotChangeAGymsPlates() throws {
        let user = Self.makeUser(units: .metric)
        context.insert(user)
        let filled = GymProfile(name: "Filled", preset: .commercial)
        context.insert(filled)
        try context.save()
        try GymInventoryBackfill.run(in: context)
        let before = try #require(filled.loadingInventory)
        #expect(before == Self.commercialDefault(.metric))

        user.preferredUnits = .imperial
        try context.save()

        #expect(try GymInventoryBackfill.run(in: context) == 0)
        #expect(filled.loadingInventory == before)
    }

    /// Stored values reread from disk, in a fresh container, under the new unit.
    @Test func switchingUnitsKeepsPlatesAcrossAReopen() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GymInventory-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { removeTestItem(at: directory) }
        let url = directory.appendingPathComponent("gym.store")

        try {
            let container = try PersistenceController.makeContainer(url: url)
            let context = container.mainContext
            context.insert(Self.makeUser(units: .metric))
            context.insert(GymProfile(name: "Gym", preset: .commercial))
            try context.save()
            try GymInventoryBackfill.run(in: context)
        }()
        try {
            let container = try PersistenceController.makeContainer(url: url)
            let context = container.mainContext
            try #require(try context.fetch(FetchDescriptor<UserProfile>()).first).preferredUnits = .imperial
            try context.save()
            #expect(try GymInventoryBackfill.run(in: context) == 0)
        }()

        let container = try PersistenceController.makeContainer(url: url)
        let gym = try #require(try container.mainContext.fetch(FetchDescriptor<GymProfile>()).first)
        #expect(gym.loadingInventory == Self.commercialDefault(.metric))
    }

    @Test func editedInventoryPersistsExactly() throws {
        let gym = GymProfile(name: "Garage", preset: .custom, inventoryUnits: .metric)
        context.insert(gym)
        let edited = LoadingInventory(
            bars: [GymBar(name: "Rusty", weightKg: 18.5)],
            plates: [PlateStock(weightKg: Self.lb(45), pairCount: 3), PlateStock(weightKg: 1.25, pairCount: 1)],
            dumbbellIncrementKg: 2,
            machineIncrementKg: 4.5
        )
        gym.updateInventory(edited)
        try context.save()

        let fresh = ModelContext(container)
        let reread = try #require(try fresh.fetch(FetchDescriptor<GymProfile>()).first)
        #expect(reread.loadingInventory == edited)
    }

    // MARK: - Backfill

    @Test func backfillSkipsWhenNoUserProfileExists() throws {
        let gym = GymProfile(name: "Seeded", preset: .commercial)
        context.insert(gym)
        try context.save()

        #expect(try GymInventoryBackfill.run(in: context) == 0)
        #expect(gym.loadingInventory == nil)
    }

    @Test func backfillUsesEachGymsPresetAndTheUsersUnits() throws {
        context.insert(Self.makeUser(units: .imperial))
        let commercial = GymProfile(name: "A", preset: .commercial)
        let home = GymProfile(name: "B", preset: .homeDumbbells)
        context.insert(commercial)
        context.insert(home)
        try context.save()

        #expect(try GymInventoryBackfill.run(in: context) == 2)

        #expect(commercial.loadingInventory == Self.commercialDefault(.imperial))
        #expect(home.loadingInventory == .withoutBarbell(units: .imperial))
    }

    @Test func backfillIsIdempotent() throws {
        context.insert(Self.makeUser(units: .metric))
        let gym = GymProfile(name: "A", preset: .commercial)
        context.insert(gym)
        try context.save()

        #expect(try GymInventoryBackfill.run(in: context) == 1)
        let first = gym.loadingInventory
        #expect(try GymInventoryBackfill.run(in: context) == 0)
        #expect(gym.loadingInventory == first)
    }

    @Test func backfillLeavesEditedGymsAlone() throws {
        context.insert(Self.makeUser(units: .imperial))
        let edited = LoadingInventory(
            bars: [], plates: [PlateStock(weightKg: 20, pairCount: 1)],
            dumbbellIncrementKg: 1, machineIncrementKg: 1
        )
        let gym = GymProfile(name: "Edited", preset: .custom)
        gym.updateInventory(edited)
        context.insert(gym)
        try context.save()

        #expect(try GymInventoryBackfill.run(in: context) == 0)
        #expect(gym.loadingInventory == edited)
    }

    @Test func backfillPersistsItsWrites() throws {
        context.insert(Self.makeUser(units: .imperial))
        context.insert(GymProfile(name: "A", preset: .commercial))
        try context.save()

        try GymInventoryBackfill.run(in: context)

        let fresh = ModelContext(container)
        let gym = try #require(try fresh.fetch(FetchDescriptor<GymProfile>()).first)
        #expect(gym.loadingInventory == Self.commercialDefault(.imperial))
    }

    // MARK: - Editor draft

    @Test func untouchedKgPlatesSaveExactlyUnderLbDisplay() {
        let inventory = LoadingInventory.standard(units: .metric)
        let draft = LoadingInventoryDraft(inventory: inventory, units: .imperial)
        #expect(draft.plates.first?.weight.text == "55.12")
        #expect(draft.inventory(for: [.barbell, .dumbbell, .machine]) == inventory)
    }

    @Test func untouchedLbPlatesShowRoundPounds() {
        let draft = LoadingInventoryDraft(inventory: .standard(units: .imperial), units: .imperial)
        #expect(draft.plates.first?.weight.text == "45")
        #expect(draft.bars.first?.weight.text == "45")
    }

    @Test func typedWeightsParseInTheDisplayUnit() {
        var draft = LoadingInventoryDraft(inventory: .standard(units: .imperial), units: .imperial)
        draft.plates[0].weight.text = "100"
        #expect(draft.inventory(for: [.barbell])?.plates.first?.weightKg == Self.lb(100))
    }

    @Test(arguments: ["", "abc", "0", "-5"])
    func invalidVisibleValuesBlockSaving(text: String) {
        var draft = LoadingInventoryDraft(inventory: .standard(units: .metric), units: .metric)
        draft.plates[0].weight.text = text
        #expect(draft.inventory(for: [.barbell]) == nil)

        var step = LoadingInventoryDraft(inventory: .standard(units: .metric), units: .metric)
        step.dumbbellIncrement.text = text
        #expect(step.inventory(for: [.dumbbell]) == nil)
    }

    @Test func aBarNeedsAName() {
        var draft = LoadingInventoryDraft(inventory: .standard(units: .metric), units: .metric)
        draft.bars[0].name = "   "
        #expect(draft.inventory(for: [.barbell]) == nil)
    }

    @Test func aNewEmptyRowBlocksSavingUntilFilled() {
        var draft = LoadingInventoryDraft(inventory: .standard(units: .metric), units: .metric)
        draft.addPlate()
        #expect(draft.inventory(for: [.barbell]) == nil)

        let last = draft.plates.count - 1
        draft.plates[last].weight.text = "50"
        #expect(draft.inventory(for: [.barbell])?.plates.last == PlateStock(weightKg: 50, pairCount: 1))
    }

    @Test func hiddenSectionsDontBlockSaving() {
        var draft = LoadingInventoryDraft(inventory: .standard(units: .metric), units: .metric)
        draft.plates[0].weight.text = ""
        draft.dumbbellIncrement.text = ""
        draft.machineIncrement.text = ""

        let saved = draft.inventory(for: [.bodyweight])

        #expect(saved?.plates.count == LoadingInventory.standard(units: .metric).plates.count - 1)
        #expect(saved?.dumbbellIncrementKg == 2.5)
        #expect(saved?.machineIncrementKg == 5)
    }

    @Test func aHomeGymGainingABarbellGetsTheStandardSet() {
        var draft = LoadingInventoryDraft(inventory: .withoutBarbell(units: .imperial), units: .imperial)
        draft.seedBarbellIfEmpty()
        let saved = draft.inventory(for: [.barbell])
        #expect(saved?.bars == LoadingInventory.standard(units: .imperial).bars)
        #expect(saved?.plates == LoadingInventory.standard(units: .imperial).plates)
    }

    @Test func seedingLeavesExistingRowsAlone() {
        var draft = LoadingInventoryDraft(inventory: .standard(units: .metric), units: .metric)
        draft.plates.removeLast()
        let before = draft.plates
        draft.seedBarbellIfEmpty()
        #expect(draft.plates == before)
    }

    @Test func sectionVisibilityFollowsEquipment() {
        #expect(LoadingInventoryDraft.showsBarsAndPlates(for: [.barbell]))
        #expect(LoadingInventoryDraft.showsBarsAndPlates(for: [.smithMachine]))
        #expect(!LoadingInventoryDraft.showsBarsAndPlates(for: [.dumbbell]))
        #expect(LoadingInventoryDraft.showsFreeBarActions(for: [.barbell]))
        #expect(!LoadingInventoryDraft.showsFreeBarActions(for: [.smithMachine]))
        #expect(LoadingInventoryDraft.showsDumbbellStep(for: [.dumbbell]))
        for equipment in [EquipmentType.machine, .cable] {
            #expect(LoadingInventoryDraft.showsMachineStep(for: [equipment]))
        }
        #expect(!LoadingInventoryDraft.showsMachineStep(for: [.barbell, .smithMachine, .bodyweight]))
    }

    // MARK: - Editor draft: Smith bar

    private static func smithDraft() -> LoadingInventoryDraft {
        var draft = LoadingInventoryDraft(inventory: .standard(units: .metric), units: .metric)
        draft.seedSmithIfMissing()
        return draft
    }

    private static func smithIndex(_ draft: LoadingInventoryDraft) throws -> Int {
        try #require(draft.bars.firstIndex { $0.kind == .smith })
    }

    @Test func aSmithBarCanBeEditedToZero() throws {
        var draft = Self.smithDraft()
        draft.bars[try Self.smithIndex(draft)].weight.text = "0"
        let saved = draft.inventory(for: [.smithMachine])
        #expect(saved?.bars(for: .smithMachine).first?.weightKg == 0)
    }

    @Test func aFreeBarCantBeZero() {
        var draft = Self.smithDraft()
        draft.bars[0].weight.text = "0"
        #expect(draft.inventory(for: [.barbell]) == nil)
    }

    @Test(arguments: ["", "abc", "-5"])
    func aSmithBarNeedsAValidWeight(text: String) throws {
        var draft = Self.smithDraft()
        draft.bars[try Self.smithIndex(draft)].weight.text = text
        #expect(draft.inventory(for: [.smithMachine]) == nil)
    }

    @Test func aSmithBarNameIsEditable() throws {
        var draft = Self.smithDraft()
        draft.bars[try Self.smithIndex(draft)].name = "Hammer Strength"
        #expect(draft.inventory(for: [.smithMachine])?.bars(for: .smithMachine).first?.name == "Hammer Strength")
    }

    @Test func aSmithBarIsDroppedWithoutASmithMachine() {
        let saved = Self.smithDraft().inventory(for: [.barbell])
        #expect(saved?.bars(for: .smithMachine) == [])
        #expect(saved?.bars(for: .barbell).count == 3)
    }

    @Test func anInvalidSmithBarDoesntBlockAGymWithoutOne() throws {
        var draft = Self.smithDraft()
        draft.bars[try Self.smithIndex(draft)].weight.text = ""
        #expect(draft.inventory(for: [.barbell]) != nil)
    }

    @Test func aGymGainingASmithMachineGetsItsBarAndPlates() {
        var draft = LoadingInventoryDraft(inventory: .withoutBarbell(units: .imperial), units: .imperial)
        draft.seedSmithIfMissing()
        let saved = draft.inventory(for: [.smithMachine])
        #expect(saved?.bars == [LoadingInventory.smithBar(units: .imperial)])
        #expect(saved?.plates == LoadingInventory.standard(units: .imperial).plates)
    }

    @Test func seedingSmithKeepsAnEditedBarAndPlates() throws {
        var draft = Self.smithDraft()
        let index = try Self.smithIndex(draft)
        draft.bars[index].weight.text = "20"
        draft.plates.removeLast()
        let plates = draft.plates

        draft.seedSmithIfMissing()

        #expect(draft.bars.filter { $0.kind == .smith }.count == 1)
        #expect(draft.bars[index].weight.text == "20")
        #expect(draft.plates == plates)
    }

    @Test func aSmithOnlyGymGainingABarbellGetsFreeBars() {
        var draft = LoadingInventoryDraft(inventory: .withoutBarbell(units: .metric), units: .metric)
        draft.seedSmithIfMissing()
        draft.seedBarbellIfEmpty()
        let saved = draft.inventory(for: [.barbell, .smithMachine])
        #expect(saved?.bars(for: .barbell) == LoadingInventory.standard(units: .metric).bars)
        #expect(saved?.bars(for: .smithMachine).count == 1)
    }
}
