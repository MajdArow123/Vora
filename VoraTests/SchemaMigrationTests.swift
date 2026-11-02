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
            removeTestItem(at: URL(fileURLWithPath: url.path + suffix))
        }
    }

    /// Copies a bundled fixture store (and whichever sidecars exist) into a
    /// fresh temporary directory, so the fixture itself is never modified.
    private static func copyFixtureStore(named name: String) throws -> (directory: URL, store: URL) {
        let bundle = Bundle(for: BundleToken.self)
        let source = try #require(bundle.url(forResource: name, withExtension: "store"))
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Fixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let storeURL = directory.appendingPathComponent("\(name).store")
        for suffix in [""] + StoreExporter.sidecarSuffixes {
            let sidecar = URL(fileURLWithPath: source.path + suffix)
            guard FileManager.default.fileExists(atPath: sidecar.path) else { continue }
            try FileManager.default.copyItem(at: sidecar, to: URL(fileURLWithPath: storeURL.path + suffix))
        }
        return (directory, storeURL)
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

    @Test func schemaV2HasSameEntitiesAsV1() {
        #expect(SchemaV2.versionIdentifier == Schema.Version(2, 0, 0))
        #expect(Set(Self.shapes(Schema(SchemaV2.models)).keys) == Set(Self.shapes(Schema(SchemaV1.models)).keys))
    }

    /// V2 differs from V1 only by the optional ExerciseLog.exerciseId.
    @Test func schemaV2AddsOnlyExerciseID() {
        var expected = Self.shapes(Schema(versionedSchema: SchemaV1.self))
        expected["ExerciseLog", default: []].insert("exerciseId")
        #expect(Self.shapes(Schema(versionedSchema: SchemaV2.self)) == expected)
    }

    @Test func schemaV4IsCurrent() {
        #expect(SchemaV4.versionIdentifier == Schema.Version(4, 0, 0))
        #expect(CurrentSchema.versionIdentifier == SchemaV4.versionIdentifier)
        #expect(SchemaV4.models.count == 20)
    }

    /// V4 changes exactly these columns and nothing else.
    @Test func schemaV4ReplacesRPEWithRIRAndAddsHealthKitIDs() {
        var expected = Self.shapes(Schema(versionedSchema: SchemaV3.self))
        expected["SetEntry", default: []].remove("rpe")
        expected["SetEntry", default: []].insert("rir")
        expected["WorkoutSession", default: []].insert("healthKitWorkoutID")
        expected["CardioEntry", default: []].insert("healthKitWorkoutID")
        #expect(Self.shapes(PersistenceController.schema) == expected)
    }

    /// The freeze held: every earlier version still describes what its
    /// stores contain, not the live classes.
    @Test(arguments: [
        SchemaV1.self as any VersionedSchema.Type,
        SchemaV2.self as any VersionedSchema.Type,
        SchemaV3.self as any VersionedSchema.Type,
    ])
    func earlierVersionsKeepTheirShape(version: any VersionedSchema.Type) {
        let shapes = Self.shapes(Schema(versionedSchema: version))
        let sets = shapes["SetEntry"] ?? []
        #expect(sets.contains("rpe"))
        #expect(!sets.contains("rir"))
        #expect(shapes["WorkoutSession"]?.contains("healthKitWorkoutID") == false)
        #expect(shapes["CardioEntry"]?.contains("healthKitWorkoutID") == false)
    }

    /// V3 is V2 plus the two template entities; no V2 entity changed.
    @Test func schemaV3AddsOnlyTemplateEntities() {
        var expected = Self.shapes(Schema(versionedSchema: SchemaV2.self))
        expected["WorkoutTemplate"] = ["id", "splitRawValue", "dayIndex", "name", "exercises"]
        expected["TemplateExercise"] = [
            "id", "exerciseId", "customName", "orderIndex", "targetSets",
            "repRangeMin", "repRangeMax", "targetRIR", "restSeconds", "parent",
        ]
        #expect(Self.shapes(Schema(versionedSchema: SchemaV3.self)) == expected)
    }

    @Test func migrationPlanListsEveryVersionWithAStageBetweenEach() {
        let versions = VoraMigrationPlan.schemas.map { $0.versionIdentifier }
        #expect(versions == [
            Schema.Version(1, 0, 0), Schema.Version(2, 0, 0), Schema.Version(3, 0, 0), Schema.Version(4, 0, 0),
        ])
        #expect(VoraMigrationPlan.stages.count == 3)
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
        let fixture = try Self.copyFixtureStore(named: "v1-fixture")
        defer { removeTestItem(at: fixture.directory) }
        let storeURL = fixture.store

        let store = AppDataStore(
            open: { try PersistenceController.makeContainer(url: storeURL) },
            migrateTemplates: { _ in TemplateDefaultsMigration.Outcome() }
        )
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

    // MARK: - V2 -> V3 (frozen types)

    /// A store written with the V2 schema opens through the plan with every
    /// row intact and the new template entities usable.
    @Test @MainActor func v2StoreMigratesToV3WithoutLoss() throws {
        let storeURL = Self.temporaryStoreURL()
        defer { Self.removeStore(at: storeURL) }

        let sessionDate = Date(timeIntervalSince1970: 1_792_000_000)
        try {
            let schema = Schema(versionedSchema: SchemaV2.self)
            let v2 = try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, url: storeURL)]
            )
            let context = v2.mainContext
            let bench = SchemaV2.ExerciseLog(
                exerciseName: "Barbell Bench Press", exerciseId: "barbell-bench-press",
                muscleGroups: ["chest"], orderIndex: 0,
                sets: [SchemaV2.SetEntry(setNumber: 1, weightKg: 90, reps: 5, isCompleted: true)]
            )
            let sled = SchemaV2.ExerciseLog(
                exerciseName: "Sled Push", orderIndex: 1,
                sets: [SchemaV2.SetEntry(setNumber: 1, weightKg: 120, reps: 1, isCompleted: true)]
            )
            context.insert(SchemaV2.WorkoutSession(
                date: sessionDate, sessionName: "Push", durationSeconds: 1800,
                totalVolumeKg: 570, exercises: [bench, sled]
            ))
            context.insert(SplitDay(dayIndex: 0, title: "Push", muscleGroups: ["chest"]))
            context.insert(WeightEntry(date: sessionDate, weightKg: 81.2))
            try context.save()
        }()

        let container = try PersistenceController.makeContainer(url: storeURL)
        let context = container.mainContext

        let session = try #require(try context.fetch(FetchDescriptor<WorkoutSession>()).first)
        #expect(session.date == sessionDate)
        let logs = session.exercises.sorted { $0.orderIndex < $1.orderIndex }
        #expect(logs.map(\.exerciseId) == ["barbell-bench-press", nil])
        #expect(logs.flatMap(\.sets).map(\.weightKg).sorted() == [90, 120])
        #expect(try context.fetch(FetchDescriptor<SplitDay>()).map(\.title) == ["Push"])
        #expect(try context.fetch(FetchDescriptor<WeightEntry>()).map(\.weightKg) == [81.2])
        #expect(try context.fetchCount(FetchDescriptor<WorkoutTemplate>()) == 0)

        try WorkoutTemplateService.save(
            [TemplateExerciseSpec(exerciseId: "barbell-bench-press")],
            for: .ppl, dayIndex: 0, context: context
        )
        #expect(try context.fetchCount(FetchDescriptor<TemplateExercise>()) == 1)
    }

    // MARK: - V2 -> V3 (real store and templates from commit 712aea5)

    /// Loads `Fixtures/v2-fixture-templates.plist` (the UserDefaults domain
    /// written by the shipped WorkoutTemplateStore) into a fresh suite.
    private static func fixtureTemplateDefaults() throws -> UserDefaults {
        let bundle = Bundle(for: BundleToken.self)
        let url = try #require(bundle.url(forResource: "v2-fixture-templates", withExtension: "plist"))
        let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil)
        let domain = try #require(plist as? [String: Any])
        let defaults = try makeTestDefaults()
        for (key, value) in domain {
            defaults.set(value, forKey: key)
        }
        return defaults
    }

    /// `Fixtures/v2-fixture.store` was written by the shipped V2 code
    /// (commit 712aea5): 2 Push sessions, each with Barbell Bench Press,
    /// Leg Curl and the custom Sled Push; the second session holds the
    /// bench PR. `v2-fixture-templates.plist` holds the templates that
    /// build saved: ppl.0, ppl.1 (with "Leg Curl" and the alias
    /// "bench press"), an emptied ppl.2, and upperLower.0.
    @Test @MainActor func realV2FixtureMigratesStoreAndTemplatesWithoutLoss() throws {
        let fixture = try Self.copyFixtureStore(named: "v2-fixture")
        defer { removeTestItem(at: fixture.directory) }
        let storeURL = fixture.store
        let defaults = try Self.fixtureTemplateDefaults()
        let open = { try PersistenceController.makeContainer(url: storeURL) }

        let store = AppDataStore(
            open: open,
            migrateTemplates: { try TemplateDefaultsMigration.run(in: $0, defaults: defaults) }
        )
        store.load()
        let context = try #require(store.container).mainContext

        // Every V2 row survived.
        let users = try context.fetch(FetchDescriptor<UserProfile>())
        #expect(users.map(\.name) == ["Fixture User"])
        #expect(users.first?.trainingSplit == .ppl)
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>(sortBy: [SortDescriptor(\.date)]))
        #expect(sessions.map(\.date) == [
            Date(timeIntervalSince1970: 1_792_051_200),
            Date(timeIntervalSince1970: 1_792_656_000),
        ])
        #expect(try context.fetchCount(FetchDescriptor<ExerciseLog>()) == 6)
        #expect(try context.fetchCount(FetchDescriptor<SetEntry>()) == 12)
        for session in sessions {
            let logs = session.exercises.sorted { $0.orderIndex < $1.orderIndex }
            #expect(logs.map(\.exerciseName) == ["Barbell Bench Press", "Leg Curl", "Sled Push"])
            #expect(logs.map(\.exerciseId) == ["barbell-bench-press", "leg-curl", nil])
        }
        #expect(try context.fetch(FetchDescriptor<GymProfile>()).map(\.name) == ["Commercial Gym"])

        let records = WorkoutHomeViewModel.computePersonalRecords(from: context)
        let benchPR = try #require(records.first { $0.exerciseId == "barbell-bench-press" })
        #expect(benchPR.weightKg == 85)
        #expect(benchPR.reps == 8)
        #expect(benchPR.date == Date(timeIntervalSince1970: 1_792_656_000))
        #expect(records.first { $0.exerciseId == "leg-curl" }?.weightKg == 45)
        #expect(records.first { $0.exerciseName == "Sled Push" }?.weightKg == 110)

        // Templates moved from UserDefaults, matched by ID.
        let push = try #require(try WorkoutTemplateService.template(for: .ppl, dayIndex: 0, context: context))
        #expect(push.name == "Push")
        #expect(push.orderedExercises.map(\.exerciseId) == ["barbell-bench-press", "overhead-press", nil])
        #expect(push.orderedExercises.map(\.customName) == [nil, nil, "Sled Push"])
        #expect(push.orderedExercises.map(\.restSeconds) == [120, 120, 90])
        for exercise in push.orderedExercises {
            #expect(exercise.targetSets == 3)
            #expect(exercise.repRangeMin == 8)
            #expect(exercise.repRangeMax == 12)
            #expect(exercise.targetRIR == 2)
        }

        let pull = try #require(try WorkoutTemplateService.template(for: .ppl, dayIndex: 1, context: context))
        #expect(pull.orderedExercises.map(\.exerciseId) == ["pull-up", "leg-curl", "barbell-bench-press"])
        #expect(pull.orderedExercises.map(\.displayName) == ["Pull-Up", "Leg Curl", "Barbell Bench Press"])

        let legs = try #require(try WorkoutTemplateService.template(for: .ppl, dayIndex: 2, context: context))
        #expect(legs.exercises.isEmpty)
        #expect(try WorkoutTemplateService.plan(for: .ppl, dayIndex: 2, context: context).isEmpty)

        let upper = try #require(try WorkoutTemplateService.template(for: .upperLower, dayIndex: 0, context: context))
        #expect(upper.name == "Upper")
        #expect(upper.orderedExercises.map(\.exerciseId) == ["back-squat", "lateral-raise"])
        #expect(upper.orderedExercises.map(\.restSeconds) == [120, 90])

        #expect(try context.fetchCount(FetchDescriptor<WorkoutTemplate>()) == 4)
        #expect(try context.fetchCount(FetchDescriptor<TemplateExercise>()) == 8)
        #expect(defaults.object(forKey: TemplateDefaultsMigration.storageKey) == nil)

        // A second launch, and a rerun with the old key restored (as if the
        // app died between the save and the key removal), add nothing.
        let relaunch = AppDataStore(
            open: open,
            migrateTemplates: { try TemplateDefaultsMigration.run(in: $0, defaults: defaults) }
        )
        relaunch.load()
        let relaunched = try #require(relaunch.container).mainContext
        #expect(try relaunched.fetchCount(FetchDescriptor<WorkoutTemplate>()) == 4)

        let restored = try Self.fixtureTemplateDefaults()
        let rerun = try TemplateDefaultsMigration.run(in: relaunched, defaults: restored)
        #expect(rerun.migrated == 0)
        #expect(rerun.skippedExisting == 4)
        #expect(rerun.removedKey)
        #expect(try relaunched.fetchCount(FetchDescriptor<WorkoutTemplate>()) == 4)
        #expect(try relaunched.fetchCount(FetchDescriptor<TemplateExercise>()) == 8)
    }

    // MARK: - V3 -> V4 (frozen types)

    /// A store written with the frozen V3 types opens through the plan with
    /// every row intact and the new optional columns nil.
    @Test @MainActor func v3StoreMigratesToV4WithoutLoss() throws {
        let storeURL = Self.temporaryStoreURL()
        defer { Self.removeStore(at: storeURL) }

        let sessionDate = Date(timeIntervalSince1970: 1_793_000_000)
        try {
            let schema = Schema(versionedSchema: SchemaV3.self)
            let v3 = try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, url: storeURL)]
            )
            let context = v3.mainContext
            let bench = SchemaV3.ExerciseLog(
                exerciseName: "Barbell Bench Press", exerciseId: "barbell-bench-press",
                muscleGroups: ["chest"], orderIndex: 0,
                sets: [
                    SchemaV3.SetEntry(setNumber: 1, weightKg: 90, reps: 5, isCompleted: true),
                    SchemaV3.SetEntry(setNumber: 2, weightKg: 92.5, reps: 3, isCompleted: true),
                ]
            )
            context.insert(SchemaV3.WorkoutSession(
                date: sessionDate, sessionName: "Push", durationSeconds: 1800,
                totalVolumeKg: 727.5, notes: "Felt good", exercises: [bench]
            ))
            context.insert(SchemaV3.CardioEntry(
                date: sessionDate, type: .row, durationSeconds: 900,
                estimatedCalories: 150, strokesPerMinute: 24
            ))
            try context.save()
        }()

        let container = try PersistenceController.makeContainer(url: storeURL)
        let context = container.mainContext

        let session = try #require(try context.fetch(FetchDescriptor<WorkoutSession>()).first)
        #expect(session.date == sessionDate)
        #expect(session.notes == "Felt good")
        #expect(session.healthKitWorkoutID == nil)
        let sets = try #require(session.exercises.first?.sets).sorted { $0.setNumber < $1.setNumber }
        #expect(sets.map(\.weightKg) == [90, 92.5])
        #expect(sets.map(\.reps) == [5, 3])
        #expect(sets.allSatisfy { $0.rir == nil })

        let cardio = try #require(try context.fetch(FetchDescriptor<CardioEntry>()).first)
        #expect(cardio.type == .row)
        #expect(cardio.strokesPerMinute == 24)
        #expect(cardio.healthKitWorkoutID == nil)
    }

    // MARK: - V3 -> V4 (real store from commit 07190d1)

    /// `Fixtures/v3-fixture.store` was written by the shipped V3 code
    /// (commit 07190d1): 2 Push sessions saved through
    /// `ActiveSessionViewModel.finish()`, each with Barbell Bench Press
    /// (3 sets) and the custom Sled Push (1 set), the second holding the
    /// bench PR; 2 cardio entries; and one template with target RIRs of 2,
    /// 0 and nil.
    @Test @MainActor func realV3FixtureMigratesWithoutLoss() async throws {
        let fixture = try Self.copyFixtureStore(named: "v3-fixture")
        defer { removeTestItem(at: fixture.directory) }
        let storeURL = fixture.store

        let store = AppDataStore(
            open: { try PersistenceController.makeContainer(url: storeURL) },
            migrateTemplates: { _ in TemplateDefaultsMigration.Outcome() }
        )
        store.load()
        let context = try #require(store.container).mainContext

        #expect(try context.fetch(FetchDescriptor<UserProfile>()).map(\.name) == ["Fixture User"])
        #expect(try context.fetch(FetchDescriptor<GymProfile>()).map(\.name) == ["Commercial Gym"])

        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>(sortBy: [SortDescriptor(\.date)]))
        #expect(sessions.map(\.date) == [
            Date(timeIntervalSince1970: 1_793_260_800),
            Date(timeIntervalSince1970: 1_793_865_600),
        ])
        #expect(sessions.map(\.durationSeconds) == [3000, 3000])
        #expect(sessions.allSatisfy { $0.healthKitWorkoutID == nil })
        #expect(try context.fetchCount(FetchDescriptor<ExerciseLog>()) == 4)
        #expect(try context.fetchCount(FetchDescriptor<SetEntry>()) == 8)
        #expect(try context.fetch(FetchDescriptor<SetEntry>()).allSatisfy { $0.rir == nil })
        for session in sessions {
            let logs = session.exercises.sorted { $0.orderIndex < $1.orderIndex }
            #expect(logs.map(\.exerciseName) == ["Barbell Bench Press", "Sled Push"])
            #expect(logs.map(\.exerciseId) == ["barbell-bench-press", nil])
        }
        let lastBench = try #require(sessions.last?.exercises.first { $0.orderIndex == 0 })
        #expect(lastBench.sets.sorted { $0.setNumber < $1.setNumber }.map(\.weightKg) == [85, 85, 82.5])

        let records = WorkoutHomeViewModel.computePersonalRecords(from: context)
        let benchPR = try #require(records.first { $0.exerciseId == "barbell-bench-press" })
        #expect(benchPR.weightKg == 85)
        #expect(benchPR.reps == 8)
        #expect(records.first { $0.exerciseName == "Sled Push" }?.weightKg == 110)

        let cardio = try context.fetch(FetchDescriptor<CardioEntry>(sortBy: [SortDescriptor(\.date)]))
        #expect(cardio.map(\.type) == [.treadmill, .stationaryBike])
        #expect(cardio.first?.speedKmh == 8.5)
        #expect(cardio.first?.inclinePercent == 2)
        #expect(cardio.last?.resistanceLevel == 8)
        #expect(cardio.last?.rpm == 80)
        #expect(cardio.allSatisfy { $0.healthKitWorkoutID == nil })

        let push = try #require(try WorkoutTemplateService.template(for: .ppl, dayIndex: 0, context: context))
        #expect(push.orderedExercises.map(\.exerciseId) == ["barbell-bench-press", "lateral-raise", nil])
        #expect(push.orderedExercises.map(\.targetRIR) == [2, 0, nil])
        #expect(push.orderedExercises.map(\.customName) == [nil, nil, "Sled Push"])

        // The new columns save and reread on migrated rows.
        let workoutID = UUID()
        let firstSet = try #require(lastBench.sets.first)
        firstSet.rir = 0
        let session = try #require(sessions.last)
        session.healthKitWorkoutID = workoutID
        try context.save()
        let setID = firstSet.id
        let reread = try context.fetch(FetchDescriptor<SetEntry>(predicate: #Predicate { $0.id == setID }))
        #expect(reread.map(\.rir) == [0])

        // Migrated rows without an ID still delete through time matching.
        let oldest = try #require(sessions.first)
        #expect(HealthWorkoutTarget(session: oldest) == HealthWorkoutMatch(session: oldest).map(HealthWorkoutTarget.match))
        #expect(HealthWorkoutTarget(session: session) == .id(workoutID))
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

    /// Keeps tests away from the host app's real UserDefaults.
    private static let noTemplateMigration: (ModelContext) throws -> TemplateDefaultsMigration.Outcome = { _ in
        TemplateDefaultsMigration.Outcome()
    }

    @Test func startsLoading() {
        let store = AppDataStore(open: { try PersistenceController.makeContainer(inMemory: true) }, migrateTemplates: Self.noTemplateMigration)
        guard case .loading = store.state else {
            Issue.record("Expected .loading before load()")
            return
        }
    }

    @Test func failedOpenMovesToFailedWithDetails() {
        let store = AppDataStore(open: { throw OpenFailure() }, migrateTemplates: Self.noTemplateMigration)
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
        }, migrateTemplates: Self.noTemplateMigration)

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
        }, migrateTemplates: Self.noTemplateMigration)

        store.load()
        store.load()
        #expect(attempts == 1)
    }

    @Test func loadBackfillsExerciseIDsBeforeReady() throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        container.mainContext.insert(ExerciseLog(exerciseName: "back squat", orderIndex: 0))
        try container.mainContext.save()

        let store = AppDataStore(open: { container }, migrateTemplates: Self.noTemplateMigration)
        store.load()

        let ready = try #require(store.container)
        let logs = try ready.mainContext.fetch(FetchDescriptor<ExerciseLog>())
        #expect(logs.map(\.exerciseId) == ["back-squat"])
    }

    @Test func failingBackfillStillReachesReady() {
        let store = AppDataStore(
            open: { try PersistenceController.makeContainer(inMemory: true) },
            backfillExerciseIDs: { _ in throw OpenFailure() },
            migrateTemplates: Self.noTemplateMigration
        )
        store.load()
        #expect(store.container != nil)
    }

    @Test func loadMigratesSavedTemplatesBeforeReady() throws {
        let defaults = try makeTestDefaults()
        defaults.set(["ppl.0": ["Back Squat", "Sled Push"]], forKey: TemplateDefaultsMigration.storageKey)
        let store = AppDataStore(
            open: { try PersistenceController.makeContainer(inMemory: true) },
            migrateTemplates: { try TemplateDefaultsMigration.run(in: $0, defaults: defaults) }
        )
        store.load()

        let context = try #require(store.container).mainContext
        let plan = try WorkoutTemplateService.plan(for: .ppl, dayIndex: 0, context: context)
        #expect(plan.map(\.displayName) == ["Back Squat", "Sled Push"])
        #expect(defaults.object(forKey: TemplateDefaultsMigration.storageKey) == nil)
    }

    @Test func failingTemplateMigrationStillReachesReady() {
        let store = AppDataStore(
            open: { try PersistenceController.makeContainer(inMemory: true) },
            migrateTemplates: { _ in throw OpenFailure() }
        )
        store.load()
        #expect(store.container != nil)
    }

    @Test func successfulOpenSeedsDefaultGymProfile() throws {
        let store = AppDataStore(open: { try PersistenceController.makeContainer(inMemory: true) }, migrateTemplates: Self.noTemplateMigration)
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
        defer { removeTestItem(at: fake.directory) }

        let day = try #require(ISO8601DateFormatter().date(from: "2026-11-01T12:00:00Z"))
        let archive = try StoreExporter.makeArchive(storeURL: fake.store, now: day)
        defer { removeTestItem(at: archive.deletingLastPathComponent()) }

        #expect(archive.lastPathComponent == "Vora-Data-2026-11-01.zip")
        let data = try Data(contentsOf: archive)
        #expect(data.count > 0)
        #expect(data.prefix(2) == Data("PK".utf8))
    }

    @Test func stagingCopiesStoreAndPresentSidecars() throws {
        let fake = try makeFakeStore(sidecars: ["-wal"])
        defer { removeTestItem(at: fake.directory) }
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
        defer { removeTestItem(at: fake.directory) }
        let before = try fileManager.contentsOfDirectory(atPath: fake.directory.path).sorted()

        let archive = try StoreExporter.makeArchive(storeURL: fake.store)
        defer { removeTestItem(at: archive.deletingLastPathComponent()) }

        #expect(try fileManager.contentsOfDirectory(atPath: fake.directory.path).sorted() == before)
        #expect(try Data(contentsOf: fake.store) == Data("store".utf8))
    }
}
