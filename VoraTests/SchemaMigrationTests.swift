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
    private static func temporaryStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("SchemaMigration-\(UUID().uuidString).store")
    }

    private static func removeStore(at url: URL) {
        for suffix in [""] + StoreExporter.sidecarSuffixes {
            try? FileManager.default.removeItem(atPath: url.path + suffix)
        }
    }

    private static func shapes(_ schema: Schema) -> [String: Set<String>] {
        Dictionary(uniqueKeysWithValues: schema.entities.map { entity in
            (entity.name, Set(entity.properties.map(\.name)))
        })
    }

    // MARK: - Schema definitions

    @Test func schemaV1HasEighteenModelsWithFrozenWorkoutCluster() {
        #expect(SchemaV1.versionIdentifier == Schema.Version(1, 0, 0))
        #expect(SchemaV1.models.count == 18)
        let names = SchemaV1.models.map { String(reflecting: $0) }
        #expect(names.contains { $0.hasSuffix("SchemaV1.WorkoutSession") })
        #expect(names.contains { $0.hasSuffix("SchemaV1.ExerciseLog") })
        #expect(names.contains { $0.hasSuffix("SchemaV1.SetEntry") })
    }

    @Test func schemaV2IsCurrentWithSameEntities() {
        #expect(SchemaV2.versionIdentifier == Schema.Version(2, 0, 0))
        #expect(CurrentSchema.versionIdentifier == SchemaV2.versionIdentifier)
        #expect(Set(Self.shapes(Schema(SchemaV2.models)).keys) == Set(Self.shapes(Schema(SchemaV1.models)).keys))
    }

    /// V2 differs from V1 only by the optional ExerciseLog.exerciseId.
    @Test func schemaV2AddsOnlyExerciseID() {
        var expected = Self.shapes(Schema(versionedSchema: SchemaV1.self))
        expected["ExerciseLog", default: []].insert("exerciseId")
        #expect(Self.shapes(PersistenceController.schema) == expected)
    }

    @Test func migrationPlanListsV1ThenV2WithOneStage() {
        let versions = VoraMigrationPlan.schemas.map { $0.versionIdentifier }
        #expect(versions == [Schema.Version(1, 0, 0), Schema.Version(2, 0, 0)])
        #expect(VoraMigrationPlan.stages.count == 1)
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

    // MARK: - V1 -> V2 (frozen types)

    /// A store written with the frozen V1 types opens through the plan with
    /// every row intact, and the post-open backfill fills library IDs.
    @Test @MainActor func v1StoreMigratesAndBackfillsExerciseIDs() throws {
        let storeURL = Self.temporaryStoreURL()
        defer { Self.removeStore(at: storeURL) }

        let sessionDate = Date(timeIntervalSince1970: 1_790_000_000)
        try {
            let schema = Schema(versionedSchema: SchemaV1.self)
            let v1 = try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, url: storeURL)]
            )
            let context = v1.mainContext
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
            let bench = SchemaV1.ExerciseLog(exerciseName: "Barbell Bench Press", muscleGroups: ["chest"], orderIndex: 0)
            bench.sets = [
                SchemaV1.SetEntry(setNumber: 1, weightKg: 80, reps: 10, isCompleted: true),
                SchemaV1.SetEntry(setNumber: 2, weightKg: 82.5, reps: 8, isCompleted: true),
            ]
            let curl = SchemaV1.ExerciseLog(exerciseName: "Leg Curl", muscleGroups: ["hamstrings"], orderIndex: 1)
            curl.sets = [SchemaV1.SetEntry(setNumber: 1, weightKg: 40, reps: 12, isCompleted: true)]
            let sled = SchemaV1.ExerciseLog(exerciseName: "Sled Push", orderIndex: 2)
            sled.sets = [SchemaV1.SetEntry(setNumber: 1, weightKg: 100, reps: 1, isCompleted: true)]
            context.insert(SchemaV1.WorkoutSession(
                date: sessionDate, sessionName: "Push", durationSeconds: 3600,
                totalVolumeKg: 2040, exercises: [bench, curl, sled]
            ))
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
                date: sessionDate, mealSlot: .lunch, foodName: "Chicken Breast",
                servingGrams: 200, calories: 330, proteinG: 62, carbsG: 0, fatG: 7
            ))
            try context.save()
        }()

        let container = try PersistenceController.makeContainer(url: storeURL)
        let context = container.mainContext

        #expect(try ExerciseIDBackfill.run(in: context) == 2)

        let users = try context.fetch(FetchDescriptor<UserProfile>())
        #expect(users.map(\.name) == ["Existing User"])
        #expect(users.first?.biologicalSex == .female)
        #expect(users.first?.goalWeightKg == 68)

        let session = try #require(try context.fetch(FetchDescriptor<WorkoutSession>()).first)
        #expect(session.date == sessionDate)
        let logs = session.exercises.sorted { $0.orderIndex < $1.orderIndex }
        #expect(logs.map(\.exerciseName) == ["Barbell Bench Press", "Leg Curl", "Sled Push"])
        #expect(logs.map(\.exerciseId) == ["barbell-bench-press", "leg-curl", nil])
        #expect(logs[0].sets.sorted { $0.setNumber < $1.setNumber }.map(\.weightKg) == [80, 82.5])
        #expect(try context.fetchCount(FetchDescriptor<SetEntry>()) == 4)

        let weights = try context.fetch(FetchDescriptor<WeightEntry>())
        #expect(weights.map(\.weightKg) == [72.4])
        #expect(weights.first?.bodyFatPercent == 21)
        let gyms = try context.fetch(FetchDescriptor<GymProfile>())
        #expect(gyms.first?.availableEquipment == GymPreset.homeDumbbells.defaultEquipment)
        #expect(try context.fetch(FetchDescriptor<Supplement>()).map(\.name) == ["Creatine"])
        #expect(try context.fetchCount(FetchDescriptor<SupplementLog>()) == 1)
        #expect(try context.fetch(FetchDescriptor<FoodEntry>()).map(\.mealSlot) == [.lunch])
    }

    // MARK: - V1 -> V2 (real store from commit 0cafae8)

    private final class BundleToken {}

    /// `Fixtures/v1-fixture.store` was written by the shipped V1 code
    /// (commit 0cafae8): 2 sessions, each with Barbell Bench Press and
    /// "Leg Curl" (custom then, a library exercise since); the second
    /// session holds the bench PR.
    @Test @MainActor func realV1FixtureMigratesWithoutLoss() throws {
        let bundle = Bundle(for: BundleToken.self)
        let source = try #require(bundle.url(forResource: "v1-fixture", withExtension: "store"))
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("V1Fixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let storeURL = directory.appendingPathComponent("v1-fixture.store")
        for suffix in [""] + StoreExporter.sidecarSuffixes {
            let sidecar = URL(fileURLWithPath: source.path + suffix)
            guard FileManager.default.fileExists(atPath: sidecar.path) else { continue }
            try FileManager.default.copyItem(at: sidecar, to: URL(fileURLWithPath: storeURL.path + suffix))
        }

        let store = AppDataStore(open: { try PersistenceController.makeContainer(url: storeURL) })
        store.load()
        let context = try #require(store.container).mainContext

        let users = try context.fetch(FetchDescriptor<UserProfile>())
        #expect(users.map(\.name) == ["Fixture User"])
        #expect(users.first?.trainingSplit == .upperLower)

        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>(sortBy: [SortDescriptor(\.date)]))
        #expect(sessions.map(\.date) == [
            Date(timeIntervalSince1970: 1_790_841_600),
            Date(timeIntervalSince1970: 1_791_446_400),
        ])
        #expect(try context.fetchCount(FetchDescriptor<ExerciseLog>()) == 4)
        #expect(try context.fetchCount(FetchDescriptor<SetEntry>()) == 10)

        for session in sessions {
            let logs = session.exercises.sorted { $0.orderIndex < $1.orderIndex }
            #expect(logs.map(\.exerciseName) == ["Barbell Bench Press", "Leg Curl"])
            #expect(logs.map(\.exerciseId) == ["barbell-bench-press", "leg-curl"])
        }
        let lastBench = try #require(sessions.last?.exercises.first { $0.orderIndex == 0 })
        #expect(lastBench.sets.sorted { $0.setNumber < $1.setNumber }.map(\.weightKg) == [85, 85, 82.5])

        let records = WorkoutHomeViewModel.computePersonalRecords(from: context)
        let benchPR = try #require(records.first { $0.exerciseId == "barbell-bench-press" })
        #expect(benchPR.weightKg == 85)
        #expect(benchPR.reps == 8)
        #expect(benchPR.date == Date(timeIntervalSince1970: 1_791_446_400))
        let curlPR = try #require(records.first { $0.exerciseName == "Leg Curl" })
        #expect(curlPR.exerciseId == "leg-curl")
        #expect(curlPR.weightKg == 42.5)

        // A second launch finds nothing left to fill.
        #expect(try ExerciseIDBackfill.run(in: context) == 0)
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

    @Test func loadBackfillsExerciseIDsBeforeReady() throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        container.mainContext.insert(ExerciseLog(exerciseName: "back squat", orderIndex: 0))
        try container.mainContext.save()

        let store = AppDataStore(open: { container })
        store.load()

        let ready = try #require(store.container)
        let logs = try ready.mainContext.fetch(FetchDescriptor<ExerciseLog>())
        #expect(logs.map(\.exerciseId) == ["back-squat"])
    }

    @Test func failingBackfillStillReachesReady() {
        let store = AppDataStore(
            open: { try PersistenceController.makeContainer(inMemory: true) },
            backfillExerciseIDs: { _ in throw OpenFailure() }
        )
        store.load()
        #expect(store.container != nil)
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
