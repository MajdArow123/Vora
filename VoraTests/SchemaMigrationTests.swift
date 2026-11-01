//
//  SchemaMigrationTests.swift
//  VoraTests
//
//  Created by Majd Arow on 2026-11-01.
//

import Foundation
import SwiftData
import Testing
@testable import Vora

struct SchemaMigrationTests {
    /// The flat model list VoraApp used before versioning was introduced.
    private static let legacyModels: [any PersistentModel.Type] = [
        UserProfile.self, FoodEntry.self, CustomFood.self, WorkoutSession.self,
        ExerciseLog.self, SetEntry.self, WeightEntry.self, BodyMeasurement.self,
        WaterEntry.self, CardioEntry.self, SplitDay.self, SavedMeal.self,
        SavedMealItem.self, Recipe.self, RecipeIngredient.self, Supplement.self,
        SupplementLog.self, GymProfile.self,
    ]

    private static func temporaryStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("SchemaMigration-\(UUID().uuidString).store")
    }

    private static func removeStore(at url: URL) {
        for suffix in [""] + StoreExporter.sidecarSuffixes {
            try? FileManager.default.removeItem(atPath: url.path + suffix)
        }
    }

    private static func entityNames(_ models: [any PersistentModel.Type]) -> Set<String> {
        Set(Schema(models).entities.map(\.name))
    }

    // MARK: - Schema definition

    @Test func schemaV1IsVersionOneWithAllEighteenModels() {
        #expect(SchemaV1.versionIdentifier == Schema.Version(1, 0, 0))
        #expect(SchemaV1.models.count == 18)
        #expect(Self.entityNames(SchemaV1.models) == Self.entityNames(Self.legacyModels))
    }

    @Test func migrationPlanStartsAtV1AndEndsAtCurrentSchema() {
        let versions = VoraMigrationPlan.schemas.map { $0.versionIdentifier }
        #expect(versions.first == SchemaV1.versionIdentifier)
        #expect(versions.last == CurrentSchema.versionIdentifier)
        #expect(versions == versions.sorted())
    }

    /// V1 must describe exactly what pre-versioning stores contain, down
    /// to each entity's stored properties.
    @Test func currentSchemaMatchesLegacyEntityShapes() {
        func shapes(_ schema: Schema) -> [String: Set<String>] {
            Dictionary(uniqueKeysWithValues: schema.entities.map { entity in
                (entity.name, Set(entity.properties.map(\.name)))
            })
        }
        #expect(shapes(PersistenceController.schema) == shapes(Schema(Self.legacyModels)))
    }

    // MARK: - Container

    @Test @MainActor func inMemoryContainerBuildsWithPlan() throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let context = container.mainContext
        context.insert(WeightEntry(date: .now, weightKg: 80))
        try context.save()

        #expect(try context.fetchCount(FetchDescriptor<WeightEntry>()) == 1)
    }

    @Test func defaultStoreURLMatchesPreVersioningLocation() {
        #expect(PersistenceController.defaultStoreURL.lastPathComponent == "default.store")
    }

    /// A store written by the pre-versioning flat schema must open through
    /// the migration plan with every row and relationship intact.
    @Test @MainActor func legacyFlatStoreOpensWithoutLoss() throws {
        let storeURL = Self.temporaryStoreURL()
        defer { Self.removeStore(at: storeURL) }

        let sessionDate = Date(timeIntervalSince1970: 1_790_000_000)
        try {
            let schema = Schema(Self.legacyModels)
            let legacy = try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, url: storeURL)]
            )
            let context = legacy.mainContext
            context.insert(UserProfile(
                name: "Existing User",
                dateOfBirth: .distantPast,
                heightCm: 180,
                biologicalSex: .female,
                goalType: .fatLoss,
                activityLevel: .veryActive,
                trainingSplit: .ppl,
                dailyCalorieTarget: 2100,
                proteinTargetG: 150,
                carbsTargetG: 200,
                fatTargetG: 65,
                goalWeightKg: 68
            ))
            let session = WorkoutSession(date: sessionDate, sessionName: "Push", durationSeconds: 3600, totalVolumeKg: 1600)
            let log = ExerciseLog(exerciseName: "Barbell Bench Press", muscleGroups: ["chest"], orderIndex: 0)
            log.sets = [
                SetEntry(setNumber: 1, weightKg: 80, reps: 10, isCompleted: true),
                SetEntry(setNumber: 2, weightKg: 82.5, reps: 8, isCompleted: true),
            ]
            session.exercises = [log]
            context.insert(session)
            context.insert(WeightEntry(date: sessionDate, weightKg: 72.4, bodyFatPercent: 21))
            context.insert(GymProfile(name: "Home", preset: .homeDumbbells, isActive: true))
            let supplement = Supplement(name: "Creatine", dose: "5 g", orderIndex: 0)
            context.insert(supplement)
            context.insert(SupplementLog(
                supplementID: supplement.id,
                supplementName: supplement.name,
                dose: supplement.dose,
                date: sessionDate
            ))
            context.insert(FoodEntry(
                date: sessionDate,
                mealSlot: .lunch,
                foodName: "Chicken Breast",
                servingGrams: 200,
                calories: 330,
                proteinG: 62,
                carbsG: 0,
                fatG: 7
            ))
            try context.save()
        }()

        let container = try PersistenceController.makeContainer(url: storeURL)
        let context = container.mainContext

        let users = try context.fetch(FetchDescriptor<UserProfile>())
        #expect(users.count == 1)
        #expect(users.first?.name == "Existing User")
        #expect(users.first?.biologicalSex == .female)
        #expect(users.first?.goalWeightKg == 68)

        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        #expect(sessions.count == 1)
        #expect(sessions.first?.date == sessionDate)
        let exercise = try #require(sessions.first?.exercises.first)
        #expect(exercise.exerciseName == "Barbell Bench Press")
        #expect(exercise.sets.sorted { $0.setNumber < $1.setNumber }.map(\.weightKg) == [80, 82.5])
        #expect(try context.fetchCount(FetchDescriptor<SetEntry>()) == 2)

        let weights = try context.fetch(FetchDescriptor<WeightEntry>())
        #expect(weights.map(\.weightKg) == [72.4])
        #expect(weights.first?.bodyFatPercent == 21)

        let gyms = try context.fetch(FetchDescriptor<GymProfile>())
        #expect(gyms.count == 1)
        #expect(gyms.first?.availableEquipment == GymPreset.homeDumbbells.defaultEquipment)

        #expect(try context.fetch(FetchDescriptor<Supplement>()).map(\.name) == ["Creatine"])
        #expect(try context.fetchCount(FetchDescriptor<SupplementLog>()) == 1)
        #expect(try context.fetch(FetchDescriptor<FoodEntry>()).map(\.mealSlot) == [.lunch])
    }

    @Test @MainActor func versionedStoreReopensRepeatedly() throws {
        let storeURL = Self.temporaryStoreURL()
        defer { Self.removeStore(at: storeURL) }

        try {
            let container = try PersistenceController.makeContainer(url: storeURL)
            container.mainContext.insert(WaterEntry(date: .now, amountMl: 500))
            try container.mainContext.save()
        }()

        for _ in 0..<2 {
            let container = try PersistenceController.makeContainer(url: storeURL)
            #expect(try container.mainContext.fetchCount(FetchDescriptor<WaterEntry>()) == 1)
        }
    }
}

// MARK: - AppDataStore

@MainActor
struct AppDataStoreTests {
    private struct OpenFailure: Error {}

    @Test func startsLoading() {
        let store = AppDataStore(open: { try PersistenceController.makeContainer(inMemory: true) })
        guard case .loading = store.state else {
            Issue.record("Expected .loading before load()")
            return
        }
    }

    @Test func failedOpenMovesToFailedWithDetails() {
        let store = AppDataStore(open: { throw OpenFailure() })
        store.load()

        guard case .failed(let details) = store.state else {
            Issue.record("Expected .failed, got \(store.state)")
            return
        }
        #expect(details.contains("OpenFailure"))
        #expect(store.container == nil)
    }

    @Test func retryAfterFailureCanSucceed() {
        var attempts = 0
        let store = AppDataStore(open: {
            attempts += 1
            if attempts == 1 { throw OpenFailure() }
            return try PersistenceController.makeContainer(inMemory: true)
        })

        store.load()
        #expect(store.container == nil)

        store.retry()
        #expect(store.container != nil)
        #expect(attempts == 2)
    }

    @Test func loadIsNoOpOnceReady() {
        var attempts = 0
        let store = AppDataStore(open: {
            attempts += 1
            return try PersistenceController.makeContainer(inMemory: true)
        })

        store.load()
        store.load()
        #expect(attempts == 1)
    }

    @Test func successfulOpenSeedsDefaultGymProfile() throws {
        let store = AppDataStore(open: { try PersistenceController.makeContainer(inMemory: true) })
        store.load()

        let container = try #require(store.container)
        let profiles = try container.mainContext.fetch(FetchDescriptor<GymProfile>())
        #expect(profiles.count == 1)
        #expect(profiles.first?.isActive == true)
    }
}

// MARK: - StoreExporter

struct StoreExporterTests {
    private let fileManager = FileManager.default

    private func makeFakeStore(sidecars: [String]) throws -> (directory: URL, store: URL) {
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("StoreExporter-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = directory.appendingPathComponent("default.store")
        try Data("store".utf8).write(to: store)
        for suffix in sidecars {
            try Data("sidecar\(suffix)".utf8).write(to: URL(fileURLWithPath: store.path + suffix))
        }
        return (directory, store)
    }

    @Test func archiveIsANonEmptyZipNamedForTheDay() throws {
        let fake = try makeFakeStore(sidecars: ["-wal", "-shm"])
        defer { try? fileManager.removeItem(at: fake.directory) }

        let day = try #require(ISO8601DateFormatter().date(from: "2026-11-01T12:00:00Z"))
        let archive = try StoreExporter.makeArchive(storeURL: fake.store, now: day)
        defer { try? fileManager.removeItem(at: archive.deletingLastPathComponent()) }

        #expect(archive.lastPathComponent == "Vora-Data-2026-11-01.zip")
        let data = try Data(contentsOf: archive)
        #expect(data.count > 0)
        #expect(data.prefix(2) == Data("PK".utf8))
    }

    @Test func stagingCopiesStoreAndPresentSidecars() throws {
        let fake = try makeFakeStore(sidecars: ["-wal"])
        defer { try? fileManager.removeItem(at: fake.directory) }
        let destination = fake.directory.appendingPathComponent("out", isDirectory: true)
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)

        let copied = try StoreExporter.stageFiles(storeURL: fake.store, into: destination)

        #expect(copied.map(\.lastPathComponent) == ["default.store", "default.store-wal"])
        #expect(try Data(contentsOf: copied[1]) == Data("sidecar-wal".utf8))
    }

    @Test func missingStoreThrowsStoreMissing() {
        let missing = fileManager.temporaryDirectory
            .appendingPathComponent("Missing-\(UUID().uuidString).store")

        #expect {
            try StoreExporter.makeArchive(storeURL: missing)
        } throws: { error in
            guard case StoreExportError.storeMissing = error else { return false }
            return true
        }
    }

    @Test func exportLeavesSourceFilesUntouched() throws {
        let fake = try makeFakeStore(sidecars: ["-wal", "-shm"])
        defer { try? fileManager.removeItem(at: fake.directory) }
        let before = try fileManager.contentsOfDirectory(atPath: fake.directory.path).sorted()

        let archive = try StoreExporter.makeArchive(storeURL: fake.store)
        defer { try? fileManager.removeItem(at: archive.deletingLastPathComponent()) }

        #expect(try fileManager.contentsOfDirectory(atPath: fake.directory.path).sorted() == before)
        #expect(try Data(contentsOf: fake.store) == Data("store".utf8))
    }
}
