//
//  GymProfileTests.swift
//  VoraTests
//
//  Created by Majd Arow on 2026-08-10.
//

import Foundation
import SwiftData
import Testing
@testable import Vora

struct GymProfileTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([GymProfile.self])
        return try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
    }

    // MARK: - Preset seeding

    @Test func commercialPresetSeedsAllEquipment() {
        #expect(GymPreset.commercial.defaultEquipment == Set(EquipmentType.allCases))
    }

    @Test func presetDefaultsMatchSpecification() {
        #expect(GymPreset.homeDumbbells.defaultEquipment
                == [.dumbbell, .bench, .bodyweight, .pullUpBar])
        #expect(GymPreset.hotel.defaultEquipment
                == [.dumbbell, .machine, .cable, .bench, .bodyweight])
        #expect(GymPreset.bodyweightOnly.defaultEquipment == [.bodyweight, .pullUpBar])
        #expect(GymPreset.custom.defaultEquipment.isEmpty)
    }

    @Test func initSeedsEquipmentFromPreset() {
        let profile = GymProfile(name: "Hotel", preset: .hotel)
        #expect(profile.availableEquipment == GymPreset.hotel.defaultEquipment)
    }

    @Test func initHonorsExplicitEquipmentOverPreset() {
        let profile = GymProfile(name: "Garage", preset: .custom, availableEquipment: [.barbell, .bench])
        #expect(profile.availableEquipment == [.barbell, .bench])
    }

    // MARK: - Subset filtering

    @Test func exerciseIsAvailableOnlyWhenEquipmentIsSubset() throws {
        let benchPress = try #require(ExerciseLibrary.definition(named: "Barbell Bench Press"))
        #expect(benchPress.equipment == [.barbell, .bench])
        #expect(benchPress.isAvailable(with: [.barbell, .bench, .dumbbell]))
        #expect(!benchPress.isAvailable(with: [.barbell]))
        #expect(!benchPress.isAvailable(with: GymPreset.hotel.defaultEquipment))
    }

    @Test func latPulldownRequiresCableAndMachine() throws {
        let pulldown = try #require(ExerciseLibrary.definition(named: "Lat Pulldown"))
        #expect(pulldown.equipment == [.cable, .machine])
        #expect(pulldown.isAvailable(with: GymPreset.hotel.defaultEquipment))
        #expect(!pulldown.isAvailable(with: GymPreset.homeDumbbells.defaultEquipment))
    }

    @Test func customExercisesAlwaysCountAsAvailable() {
        #expect(ExerciseLibrary.isAvailable(name: "Yoga Flow", with: [.bodyweight]))
        #expect(ExerciseLibrary.isAvailable(name: "Yoga Flow", with: []))
    }

    /// Bodyweight-tagged exercises must be doable in every profile that
    /// offers bodyweight (plus a pull-up bar where one is required), so
    /// their tags may only be [bodyweight] or [bodyweight, pullUpBar].
    @Test func bodyweightExercisesPassEveryProfileThatIncludesBodyweight() {
        let allowed: [Set<EquipmentType>] = [[.bodyweight], [.bodyweight, .pullUpBar]]
        for exercise in ExerciseLibrary.all where exercise.equipment.contains(.bodyweight) {
            #expect(allowed.contains(exercise.equipment),
                    "\(exercise.name) has non-minimal bodyweight tagging")
        }

        for preset in GymPreset.allCases where preset.defaultEquipment.contains(.bodyweight) {
            let pureBodyweight = ExerciseLibrary.all.filter { $0.equipment == [.bodyweight] }
            for exercise in pureBodyweight {
                #expect(exercise.isAvailable(with: preset.defaultEquipment),
                        "\(exercise.name) unavailable in \(preset.rawValue)")
            }
        }
    }

    @Test func everyLibraryExerciseHasEquipmentTags() {
        for exercise in ExerciseLibrary.all {
            #expect(!exercise.equipment.isEmpty, "\(exercise.name) has no equipment tags")
        }
    }

    @Test func commercialProfilePassesEntireLibrary() {
        let equipment = GymPreset.commercial.defaultEquipment
        for exercise in ExerciseLibrary.all {
            #expect(exercise.isAvailable(with: equipment))
        }
    }

    // MARK: - Custom flip on edit

    @Test func editingEquipmentAwayFromPresetFlipsToCustom() {
        let profile = GymProfile(name: "Home", preset: .homeDumbbells)
        var equipment = profile.availableEquipment
        equipment.insert(.barbell)
        profile.updateEquipment(equipment)
        #expect(profile.preset == .custom)
        #expect(profile.availableEquipment.contains(.barbell))
    }

    @Test func reapplyingPresetDefaultsDoesNotFlipToCustom() {
        let profile = GymProfile(name: "Home", preset: .homeDumbbells)
        profile.updateEquipment(GymPreset.homeDumbbells.defaultEquipment)
        #expect(profile.preset == .homeDumbbells)
    }

    @Test func applyPresetReseedsEquipment() {
        let profile = GymProfile(name: "Trip", preset: .commercial)
        profile.applyPreset(.bodyweightOnly)
        #expect(profile.preset == .bodyweightOnly)
        #expect(profile.availableEquipment == [.bodyweight, .pullUpBar])
    }

    // MARK: - Seeding and active-profile invariant

    @Test @MainActor func ensureDefaultProfileSeedsCommercialForEmptyStore() throws {
        let container = try makeContainer()
        let context = container.mainContext

        GymProfileService.ensureDefaultProfile(context: context)

        let profiles = try context.fetch(FetchDescriptor<GymProfile>())
        #expect(profiles.count == 1)
        #expect(profiles.first?.preset == .commercial)
        #expect(profiles.first?.isActive == true)
        #expect(profiles.first?.availableEquipment == Set(EquipmentType.allCases))
    }

    @Test @MainActor func ensureDefaultProfileIsIdempotent() throws {
        let container = try makeContainer()
        let context = container.mainContext

        GymProfileService.ensureDefaultProfile(context: context)
        GymProfileService.ensureDefaultProfile(context: context)

        #expect(try context.fetchCount(FetchDescriptor<GymProfile>()) == 1)
    }

    @Test @MainActor func ensureDefaultProfileRepairsMissingActiveFlag() throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(GymProfile(name: "A", preset: .commercial, isActive: false))
        context.insert(GymProfile(name: "B", preset: .hotel, isActive: false))
        try context.save()

        GymProfileService.ensureDefaultProfile(context: context)

        let active = try context.fetch(FetchDescriptor<GymProfile>()).filter(\.isActive)
        #expect(active.count == 1)
    }

    @Test @MainActor func activateMakesExactlyOneProfileActive() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let first = GymProfile(name: "A", preset: .commercial, isActive: true)
        let second = GymProfile(name: "B", preset: .bodyweightOnly)
        context.insert(first)
        context.insert(second)
        try context.save()

        GymProfileService.activate(second, context: context)

        let profiles = try context.fetch(FetchDescriptor<GymProfile>())
        #expect(profiles.filter(\.isActive).count == 1)
        #expect(second.isActive)
        #expect(!first.isActive)
    }

    @Test @MainActor func deletingActiveProfileActivatesAnother() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let first = GymProfile(name: "A", preset: .commercial, isActive: true, createdAt: .now)
        let second = GymProfile(name: "B", preset: .hotel, createdAt: .now.addingTimeInterval(1))
        context.insert(first)
        context.insert(second)
        try context.save()

        #expect(GymProfileService.delete(first, context: context))

        let profiles = try context.fetch(FetchDescriptor<GymProfile>())
        #expect(profiles.count == 1)
        #expect(profiles.first?.isActive == true)
        #expect(profiles.first?.name == "B")
    }

    @Test @MainActor func deletingLastProfileIsRefused() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let only = GymProfile(name: "A", preset: .commercial, isActive: true)
        context.insert(only)
        try context.save()

        #expect(!GymProfileService.delete(only, context: context))
        #expect(try context.fetchCount(FetchDescriptor<GymProfile>()) == 1)
    }

    // MARK: - Migration

    /// Opening a store created before GymProfile existed must succeed
    /// (purely additive schema change), keep existing data intact, and
    /// seed the default commercial profile for that existing user.
    @Test @MainActor func addingGymProfileToExistingStoreMigratesCleanly() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("GymProfileMigration-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: storeURL) }

        let oldSchema = Schema([UserProfile.self])
        let oldContainer = try ModelContainer(
            for: oldSchema,
            configurations: [ModelConfiguration(schema: oldSchema, url: storeURL)]
        )
        oldContainer.mainContext.insert(UserProfile(
            name: "Existing User",
            dateOfBirth: .distantPast,
            heightCm: 180,
            biologicalSex: .male,
            goalType: .maintain,
            activityLevel: .moderatelyActive,
            trainingSplit: .ppl,
            dailyCalorieTarget: 2500,
            proteinTargetG: 160,
            carbsTargetG: 280,
            fatTargetG: 80
        ))
        try oldContainer.mainContext.save()

        let newSchema = Schema([UserProfile.self, GymProfile.self])
        let newContainer = try ModelContainer(
            for: newSchema,
            configurations: [ModelConfiguration(schema: newSchema, url: storeURL)]
        )
        let context = newContainer.mainContext

        GymProfileService.ensureDefaultProfile(context: context)

        let users = try context.fetch(FetchDescriptor<UserProfile>())
        #expect(users.count == 1)
        #expect(users.first?.name == "Existing User")

        let profiles = try context.fetch(FetchDescriptor<GymProfile>())
        #expect(profiles.count == 1)
        #expect(profiles.first?.preset == .commercial)
        #expect(profiles.first?.isActive == true)
    }
}
