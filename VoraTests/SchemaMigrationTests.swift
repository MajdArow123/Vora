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

    @Test func schemaV8IsCurrent() {
        #expect(SchemaV9.versionIdentifier == Schema.Version(9, 0, 0))
        #expect(CurrentSchema.versionIdentifier == SchemaV9.versionIdentifier)
        #expect(SchemaV9.models.count == 23)
    }

    /// V8 changes exactly these columns and nothing else.
    @Test func schemaV8AddsOnlySetTypesSidesAndSupersets() {
        var expected = Self.shapes(Schema(versionedSchema: SchemaV7.self))
        expected["SetEntry", default: []].formUnion(["setTypeRawValue", "sideRawValue"])
        expected["ExerciseLog", default: []].insert("supersetGroup")
        #expect(Self.shapes(Schema(versionedSchema: SchemaV8.self)) == expected)
    }

    /// V9 changes exactly these columns and adds exactly these entities.
    @Test func schemaV9AddsTheCycleAndNothingElse() {
        var expected = Self.shapes(Schema(versionedSchema: SchemaV8.self))
        expected["TemplateExercise", default: []].insert("supersetGroup")
        expected["WorkoutTemplate", default: []].insert("cycleDay")
        expected["TrainingProgram"] = ["id", "scheduleModeRawValue", "currentDayID", "restDay", "days"]
        expected["CycleDay"] = ["id", "orderIndex", "title", "muscleGroups", "isRest", "program", "template"]
        #expect(Self.shapes(PersistenceController.schema) == expected)
    }

    /// V3 to V8 listed the live template cluster, and now each hold their own.
    @Test(arguments: [
        SchemaV3.self as any VersionedSchema.Type,
        SchemaV4.self as any VersionedSchema.Type,
        SchemaV5.self as any VersionedSchema.Type,
        SchemaV6.self as any VersionedSchema.Type,
        SchemaV7.self as any VersionedSchema.Type,
        SchemaV8.self as any VersionedSchema.Type,
    ])
    func v3ToV8ListAFrozenTemplateCluster(version: any VersionedSchema.Type) {
        let names = version.models.map { String(reflecting: $0) }
        #expect(names.contains("Vora.\(version).WorkoutTemplate"))
        #expect(names.contains("Vora.\(version).TemplateExercise"))
        let shapes = Self.shapes(Schema(versionedSchema: version))
        #expect(shapes["WorkoutTemplate"] == ["id", "splitRawValue", "dayIndex", "name", "exercises"])
        #expect(!(shapes["TemplateExercise"] ?? []).contains("supersetGroup"))
        #expect(shapes["TrainingProgram"] == nil)
    }

    /// V6 and V7 listed the live workout cluster, and now each hold their own.
    @Test(arguments: [
        SchemaV6.self as any VersionedSchema.Type,
        SchemaV7.self as any VersionedSchema.Type,
    ])
    func v6AndV7ListAFrozenWorkoutCluster(version: any VersionedSchema.Type) {
        let names = version.models.map { String(reflecting: $0) }
        for model in ["WorkoutSession", "ExerciseLog", "SetEntry"] {
            #expect(names.contains("Vora.\(version).\(model)"))
        }
        let shapes = Self.shapes(Schema(versionedSchema: version))
        #expect((shapes["SetEntry"] ?? []).isDisjoint(with: ["setTypeRawValue", "sideRawValue"]))
        #expect((shapes["ExerciseLog"] ?? []).isSuperset(of: ["repRangeMin", "repRangeMax", "targetRIR", "targetSets"]))
        #expect(!(shapes["ExerciseLog"] ?? []).contains("supersetGroup"))
    }

    /// V7 adds one entity and changes nothing else.
    @Test func schemaV7AddsOnlyTheCheckInEntity() {
        var expected = Self.shapes(Schema(versionedSchema: SchemaV6.self))
        expected["ExpenditureCheckIn"] = [
            "id", "date", "estimateKcal", "rawEstimateKcal", "avgIntakeKcal", "slopeKgPerDay", "daysUsed", "applied",
            "appliedCalories", "appliedProteinG", "appliedCarbsG", "appliedFatG",
        ]
        #expect(Self.shapes(Schema(versionedSchema: SchemaV7.self)) == expected)
    }

    /// V6 changes exactly these columns and nothing else.
    @Test func schemaV6AddsOnlyTheTargetSnapshot() {
        var expected = Self.shapes(Schema(versionedSchema: SchemaV5.self))
        expected["ExerciseLog", default: []].formUnion(["repRangeMin", "repRangeMax", "targetRIR", "targetSets"])
        #expect(Self.shapes(Schema(versionedSchema: SchemaV6.self)) == expected)
    }

    /// V4 and V5 listed the live workout cluster, and now each hold their own.
    @Test(arguments: [
        SchemaV4.self as any VersionedSchema.Type,
        SchemaV5.self as any VersionedSchema.Type,
    ])
    func v4AndV5ListAFrozenWorkoutCluster(version: any VersionedSchema.Type) {
        let names = version.models.map { String(reflecting: $0) }
        for model in ["WorkoutSession", "ExerciseLog", "SetEntry"] {
            #expect(names.contains("Vora.\(version).\(model)"))
        }
        let log = Self.shapes(Schema(versionedSchema: version))["ExerciseLog"] ?? []
        #expect(log.isDisjoint(with: ["repRangeMin", "repRangeMax", "targetRIR", "targetSets"]))
        #expect(log.contains("exerciseId"))
    }

    /// V5 changes exactly these columns and nothing else.
    @Test func schemaV5AddsOnlyTheLoadingInventory() {
        var expected = Self.shapes(Schema(versionedSchema: SchemaV4.self))
        expected["GymProfile", default: []].formUnion([
            "storedBars", "storedPlates", "storedDumbbellIncrementKg", "storedMachineIncrementKg",
        ])
        #expect(Self.shapes(Schema(versionedSchema: SchemaV5.self)) == expected)
    }

    /// Every version that listed the live GymProfile now lists a frozen one.
    @Test(arguments: [
        SchemaV1.self as any VersionedSchema.Type,
        SchemaV2.self as any VersionedSchema.Type,
        SchemaV3.self as any VersionedSchema.Type,
        SchemaV4.self as any VersionedSchema.Type,
    ])
    func earlierVersionsListAFrozenGymProfile(version: any VersionedSchema.Type) {
        let gymModels = version.models.map { String(reflecting: $0) }.filter { $0.hasSuffix(".GymProfile") }
        #expect(gymModels == ["Vora.\(version).GymProfile"])
        let gym = Self.shapes(Schema(versionedSchema: version))["GymProfile"] ?? []
        #expect(gym == ["name", "preset", "equipmentRawValues", "isActive", "createdAt"])
    }

    /// V4 changes exactly these columns and nothing else.
    @Test func schemaV4ReplacesRPEWithRIRAndAddsHealthKitIDs() {
        var expected = Self.shapes(Schema(versionedSchema: SchemaV3.self))
        expected["SetEntry", default: []].remove("rpe")
        expected["SetEntry", default: []].insert("rir")
        expected["WorkoutSession", default: []].insert("healthKitWorkoutID")
        expected["CardioEntry", default: []].insert("healthKitWorkoutID")
        #expect(Self.shapes(Schema(versionedSchema: SchemaV4.self)) == expected)
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
            Schema.Version(5, 0, 0), Schema.Version(6, 0, 0), Schema.Version(7, 0, 0), Schema.Version(8, 0, 0),
            Schema.Version(9, 0, 0),
        ])
        #expect(VoraMigrationPlan.stages.count == 8)
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
            context.insert(SchemaV1.GymProfile(name: "Home", preset: .homeDumbbells, isActive: true))
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

    // MARK: - V7 -> V8 (frozen types)

    @Test @MainActor func v7StoreMigratesToNormalUnlinkedSets() throws {
        let storeURL = Self.temporaryStoreURL()
        defer { Self.removeStore(at: storeURL) }

        let date = Date(timeIntervalSince1970: 1_795_075_200)
        let workoutID = UUID()
        try {
            let schema = Schema(versionedSchema: SchemaV7.self)
            let container = try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, url: storeURL)]
            )
            let session = SchemaV7.WorkoutSession(
                date: date, sessionName: "Push", durationSeconds: 3000, totalVolumeKg: 1000, healthKitWorkoutID: workoutID
            )
            container.mainContext.insert(session)
            let log = SchemaV7.ExerciseLog(
                exerciseName: "Barbell Bench Press",
                exerciseId: "barbell-bench-press",
                muscleGroups: ["chest"],
                orderIndex: 0,
                targets: TemplateTargets(targetSets: 3, repRangeMin: 6, repRangeMax: 10, targetRIR: 2)
            )
            session.exercises.append(log)
            log.sets.append(SchemaV7.SetEntry(setNumber: 1, weightKg: 102.25, reps: 8, isCompleted: true, rir: 1))
            log.sets.append(SchemaV7.SetEntry(setNumber: 2, weightKg: 100, reps: 9, isCompleted: true))
            try container.mainContext.save()
        }()

        let container = try PersistenceController.makeContainer(url: storeURL)
        let context = container.mainContext
        let session = try #require(try context.fetch(FetchDescriptor<WorkoutSession>()).first)
        #expect(session.date == date)
        #expect(session.totalVolumeKg == 1000)
        #expect(session.healthKitWorkoutID == workoutID)
        let log = try #require(session.exercises.first)
        #expect(log.supersetGroup == nil)
        #expect(log.targetSnapshot == TemplateTargets(targetSets: 3, repRangeMin: 6, repRangeMax: 10, targetRIR: 2))
        let sets = log.sets.sorted { $0.setNumber < $1.setNumber }
        #expect(sets.map(\.weightKg) == [102.25, 100])
        #expect(sets.map(\.rir) == [1, nil])
        #expect(sets.allSatisfy { $0.setTypeRawValue == nil && $0.setType == .normal && $0.side == nil })
    }

    // MARK: - V8 -> V9

    /// A store made from V8's frozen types reads the same through the plan,
    /// with no links and no program.
    @Test @MainActor func frozenV8TemplatesMigrateWithoutLoss() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("V8-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { removeTestItem(at: directory) }
        let url = directory.appendingPathComponent("v8.store")

        do {
            let schema = Schema(versionedSchema: SchemaV8.self)
            let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url))
            let context = ModelContext(container)
            let template = SchemaV8.WorkoutTemplate(splitRawValue: "ppl", dayIndex: 3, name: "Push B")
            context.insert(template)
            template.exercises.append(SchemaV8.TemplateExercise(
                exerciseId: "dip", orderIndex: 0, targetSets: 4, repRangeMin: 6, repRangeMax: 9, targetRIR: nil, restSeconds: 150
            ))
            try context.save()
        }

        let container = try PersistenceController.makeContainer(url: url)
        let context = container.mainContext
        let template = try #require(try WorkoutTemplateService.template(for: .ppl, dayIndex: 3, context: context))
        #expect(template.name == "Push B")
        #expect(template.cycleDay == nil)
        let exercise = try #require(template.exercises.first)
        #expect(exercise.exerciseId == "dip")
        #expect(exercise.targetSets == 4)
        #expect(exercise.targetRIR == nil)
        #expect(exercise.restSeconds == 150)
        #expect(exercise.supersetGroup == nil)
        #expect(try TrainingProgramService.mode(context: context) == .weekly)
    }

    /// `Fixtures/v8-fixture.store` was written by the shipped V8 code (commit
    /// 2517af9): a PPL profile and split, a saved Monday template (bench and a
    /// custom Sled Push), and a Push session with a superset, a warm-up and a
    /// left-side failure set.
    @Test @MainActor func realV8FixtureMigratesWithoutLoss() throws {
        let fixture = try Self.copyFixtureStore(named: "v8-fixture")
        defer { removeTestItem(at: fixture.directory) }
        let storeURL = fixture.store

        let store = AppDataStore(
            open: { try PersistenceController.makeContainer(url: storeURL) },
            migrateTemplates: { _ in TemplateDefaultsMigration.Outcome() }
        )
        store.load()
        let context = try #require(store.container).mainContext

        let profile = try #require(try context.fetch(FetchDescriptor<UserProfile>()).first)
        #expect(profile.trainingSplit == .ppl)
        #expect(try context.fetchCount(FetchDescriptor<SplitDay>()) == 7)

        // Existing data reads as weekly, with the same plan as before.
        #expect(try TrainingProgramService.mode(context: context) == .weekly)
        #expect(try context.fetchCount(FetchDescriptor<TrainingProgram>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<CycleDay>()) == 0)

        let plan = try WorkoutTemplateService.plan(for: .ppl, dayIndex: 0, context: context)
        #expect(plan.map(\.displayName) == ["Barbell Bench Press", "Sled Push"])
        #expect(plan.map(\.targetSets) == [4, 2])
        #expect(plan.map(\.repRangeMin) == [6, 10])
        #expect(plan.map(\.targetRIR) == [1, nil])
        #expect(plan.map(\.restSeconds) == [150, 60])
        #expect(plan.allSatisfy { $0.supersetGroup == nil })

        let session = try #require(try context.fetch(FetchDescriptor<WorkoutSession>()).first)
        #expect(session.sessionName == "Push")
        #expect(session.totalVolumeKg == 1648)
        let logs = session.exercises.sorted { $0.orderIndex < $1.orderIndex }
        #expect(logs.map(\.exerciseId) == ["barbell-bench-press", "barbell-row"])
        #expect(logs.map(\.supersetGroup) == [1, 1])
        let bench = logs[0].sets.sorted { $0.setNumber < $1.setNumber }
        #expect(bench.map(\.setType) == [.warmUp, .normal])
        #expect(bench.map(\.weightKg) == [60, 102.25])
        #expect(logs[1].sets.first?.setType == .failure)
        #expect(logs[1].sets.first?.side == .left)

        // And it can switch to a cycle and back on migrated data.
        try TrainingProgramService.setMode(.cycle, context: context)
        let days = try #require(try TrainingProgramService.today(context: context)).days
        #expect(days.count == 6)
        let copied = try WorkoutTemplateService.plan(for: days[0].slot, context: context)
        #expect(copied.map(\.displayName) == ["Barbell Bench Press", "Sled Push"])
        #expect(Set(copied.map(\.id)).isDisjoint(with: plan.map(\.id)))
        try TrainingProgramService.setMode(.weekly, context: context)
        #expect(try WorkoutTemplateService.plan(for: .ppl, dayIndex: 0, context: context).map(\.id) == plan.map(\.id))
    }

    // MARK: - V7 -> V8 (real store from commit 0dbc46f)

    /// `Fixtures/v7-fixture.store` was written by the shipped V7 code (commit
    /// 0dbc46f): a Push session with Barbell Bench Press (2 sets, a target
    /// snapshot) and a custom Sled Push, a weigh-in and an applied check-in.
    @Test @MainActor func realV7FixtureMigratesWithoutLoss() throws {
        let fixture = try Self.copyFixtureStore(named: "v7-fixture")
        defer { removeTestItem(at: fixture.directory) }
        let storeURL = fixture.store

        let store = AppDataStore(
            open: { try PersistenceController.makeContainer(url: storeURL) },
            migrateTemplates: { _ in TemplateDefaultsMigration.Outcome() }
        )
        store.load()
        let context = try #require(store.container).mainContext

        let session = try #require(try context.fetch(FetchDescriptor<WorkoutSession>()).first)
        #expect(session.sessionName == "Push")
        #expect(session.durationSeconds == 3000)
        #expect(session.totalVolumeKg == 1648)
        #expect(session.healthKitWorkoutID == UUID(uuidString: "11111111-2222-3333-4444-555555555555"))

        let logs = session.exercises.sorted { $0.orderIndex < $1.orderIndex }
        #expect(logs.map(\.exerciseName) == ["Barbell Bench Press", "Sled Push"])
        #expect(logs.map(\.exerciseId) == ["barbell-bench-press", nil])
        #expect(logs.allSatisfy { $0.supersetGroup == nil })
        #expect(logs[0].targetSnapshot == TemplateTargets(targetSets: 3, repRangeMin: 6, repRangeMax: 10, targetRIR: 2))
        let bench = logs[0].sets.sorted { $0.setNumber < $1.setNumber }
        #expect(bench.map(\.weightKg) == [102.25, 100])
        #expect(bench.map(\.rir) == [1, nil])

        let sets = try context.fetch(FetchDescriptor<SetEntry>())
        #expect(sets.count == 3)
        #expect(sets.allSatisfy { $0.setTypeRawValue == nil && $0.setType == .normal && $0.side == nil })

        #expect(try context.fetch(FetchDescriptor<WeightEntry>()).map(\.weightKg) == [80.25])
        #expect(try context.fetch(FetchDescriptor<ExpenditureCheckIn>()).map(\.appliedCalories) == [2320])
        #expect(try context.fetchCount(FetchDescriptor<GymProfile>()) == 1)

        // PRs and history read migrated rows as they always did.
        #expect(WorkoutHomeViewModel.computePersonalRecords(from: context).first?.weightKg == 102.25)

        // The new columns save and reread on migrated rows.
        let firstSet = try #require(bench.first)
        firstSet.setTypeRawValue = SetType.failure.rawValue
        firstSet.sideRawValue = SetSide.left.rawValue
        logs[0].supersetGroup = 1
        try context.save()
        let reread = try ModelContext(context.container).fetch(FetchDescriptor<SetEntry>())
        let saved = try #require(reread.first { $0.id == firstSet.id })
        #expect(saved.setType == .failure)
        #expect(saved.side == .left)
    }

    // MARK: - V6 -> V7 (frozen types)

    /// V6 lists live classes only, so the store it creates has no check-ins.
    @Test @MainActor func v6StoreMigratesWithNoCheckIns() throws {
        let storeURL = Self.temporaryStoreURL()
        defer { Self.removeStore(at: storeURL) }

        let date = Date(timeIntervalSince1970: 1_795_075_200)
        try {
            let schema = Schema(versionedSchema: SchemaV6.self)
            let container = try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, url: storeURL)]
            )
            container.mainContext.insert(WeightEntry(date: date, weightKg: 80.25))
            try container.mainContext.save()
        }()

        let container = try PersistenceController.makeContainer(url: storeURL)
        let context = container.mainContext
        #expect(try context.fetch(FetchDescriptor<WeightEntry>()).map(\.weightKg) == [80.25])
        #expect(try context.fetchCount(FetchDescriptor<ExpenditureCheckIn>()) == 0)
    }

    // MARK: - V6 -> V7 (real store from commit 5228197)

    /// `Fixtures/v6-fixture.store` was written by the shipped V6 code (commit
    /// 5228197) for a metric user on fat loss: three daily weigh-ins and
    /// lunches, and a Push session with Barbell Bench Press (2 sets, a target
    /// snapshot of 3 sets at 6–10 reps and RIR 2).
    @Test @MainActor func realV6FixtureMigratesWithoutLoss() throws {
        let fixture = try Self.copyFixtureStore(named: "v6-fixture")
        defer { removeTestItem(at: fixture.directory) }
        let storeURL = fixture.store

        let store = AppDataStore(
            open: { try PersistenceController.makeContainer(url: storeURL) },
            migrateTemplates: { _ in TemplateDefaultsMigration.Outcome() }
        )
        store.load()
        let context = try #require(store.container).mainContext

        let user = try #require(try context.fetch(FetchDescriptor<UserProfile>()).first)
        #expect(user.name == "Fixture User")
        #expect(user.goalType == .fatLoss)
        #expect(user.dailyCalorieTarget == 2300)
        #expect(user.proteinTargetG == 160)
        #expect(user.carbsTargetG == 250)
        #expect(user.fatTargetG == 65)

        let weights = try context.fetch(FetchDescriptor<WeightEntry>(sortBy: [SortDescriptor(\.date)]))
        #expect(weights.map(\.weightKg) == [80.2, 80.1, 79.95])
        let food = try context.fetch(FetchDescriptor<FoodEntry>(sortBy: [SortDescriptor(\.date)]))
        #expect(food.map(\.calories) == [2400, 2410, 2420])

        let log = try #require(try context.fetch(FetchDescriptor<ExerciseLog>()).first)
        #expect(log.exerciseId == "barbell-bench-press")
        #expect(log.targetSnapshot == TemplateTargets(targetSets: 3, repRangeMin: 6, repRangeMax: 10, targetRIR: 2))
        #expect(log.sets.map(\.weightKg).sorted() == [102.25, 102.25])

        // The new entity starts empty, then saves and rereads on a migrated store.
        #expect(try context.fetchCount(FetchDescriptor<ExpenditureCheckIn>()) == 0)
        context.insert(ExpenditureCheckIn(
            date: Date(timeIntervalSince1970: 1_795_680_000),
            estimateKcal: 2900,
            rawEstimateKcal: 2950,
            avgIntakeKcal: 2410,
            slopeKgPerDay: -0.07,
            daysUsed: 3,
            applied: true,
            appliedCalories: 2320
        ))
        try context.save()
        let reread = try ModelContext(context.container).fetch(FetchDescriptor<ExpenditureCheckIn>())
        #expect(reread.map(\.appliedCalories) == [2320])
    }

    // MARK: - V5 -> V6 (frozen types)

    @Test @MainActor func v5StoreMigratesWithNilSnapshots() throws {
        let storeURL = Self.temporaryStoreURL()
        defer { Self.removeStore(at: storeURL) }

        let date = Date(timeIntervalSince1970: 1_795_075_200)
        let workoutID = UUID()
        try {
            let schema = Schema(versionedSchema: SchemaV5.self)
            let container = try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, url: storeURL)]
            )
            let session = SchemaV5.WorkoutSession(
                date: date, sessionName: "Push", durationSeconds: 3000, totalVolumeKg: 1000, healthKitWorkoutID: workoutID
            )
            container.mainContext.insert(session)
            let log = SchemaV5.ExerciseLog(
                exerciseName: "Barbell Bench Press", exerciseId: "barbell-bench-press", muscleGroups: ["chest"], orderIndex: 0
            )
            session.exercises.append(log)
            log.sets.append(SchemaV5.SetEntry(setNumber: 1, weightKg: 102.25, reps: 8, isCompleted: true, rir: 1))
            log.sets.append(SchemaV5.SetEntry(setNumber: 2, weightKg: 100, reps: 9, isCompleted: true))
            try container.mainContext.save()
        }()

        let container = try PersistenceController.makeContainer(url: storeURL)
        let context = container.mainContext
        let session = try #require(try context.fetch(FetchDescriptor<WorkoutSession>()).first)
        #expect(session.date == date)
        #expect(session.sessionName == "Push")
        #expect(session.durationSeconds == 3000)
        #expect(session.healthKitWorkoutID == workoutID)
        let log = try #require(session.exercises.first)
        #expect(log.exerciseId == "barbell-bench-press")
        #expect(log.muscleGroups == ["chest"])
        #expect(log.targetSnapshot == nil)
        #expect(log.repRangeMin == nil)
        #expect(log.repRangeMax == nil)
        #expect(log.targetRIR == nil)
        #expect(log.targetSets == nil)
        let sets = log.sets.sorted { $0.setNumber < $1.setNumber }
        #expect(sets.map(\.weightKg) == [102.25, 100])
        #expect(sets.map(\.rir) == [1, nil])
    }

    // MARK: - V5 -> V6 (real store from commit ec4b816)

    /// `Fixtures/v5-fixture.store` was written by the shipped V5 code (commit
    /// ec4b816) for a metric user: 2 Push sessions saved through
    /// `ActiveSessionViewModel.finish()`, each with Barbell Bench Press (3
    /// sets, RIRs including nil, the last set lighter) and the custom Sled
    /// Push (1 set); a template for PPL day 0 with bench at 6–10 reps; and
    /// a Commercial Gym (active) with a filled inventory.
    @Test @MainActor func realV5FixtureMigratesWithoutLoss() throws {
        let fixture = try Self.copyFixtureStore(named: "v5-fixture")
        defer { removeTestItem(at: fixture.directory) }
        let storeURL = fixture.store

        let store = AppDataStore(
            open: { try PersistenceController.makeContainer(url: storeURL) },
            migrateTemplates: { _ in TemplateDefaultsMigration.Outcome() }
        )
        store.load()
        let context = try #require(store.container).mainContext

        let user = try #require(try context.fetch(FetchDescriptor<UserProfile>()).first)
        #expect(user.name == "Fixture User")
        #expect(user.preferredUnits == .metric)

        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>(sortBy: [SortDescriptor(\.date)]))
        #expect(sessions.map(\.date) == [
            Date(timeIntervalSince1970: 1_795_075_200),
            Date(timeIntervalSince1970: 1_795_680_000),
        ])
        #expect(try context.fetchCount(FetchDescriptor<ExerciseLog>()) == 4)
        #expect(try context.fetchCount(FetchDescriptor<SetEntry>()) == 8)
        for session in sessions {
            let logs = session.exercises.sorted { $0.orderIndex < $1.orderIndex }
            #expect(logs.map(\.exerciseName) == ["Barbell Bench Press", "Sled Push"])
            #expect(logs.map(\.exerciseId) == ["barbell-bench-press", nil])
            #expect(logs.allSatisfy { $0.targetSnapshot == nil })
        }
        let lastBench = try #require(sessions.last?.exercises.first { $0.orderIndex == 0 })
            .sets.sorted { $0.setNumber < $1.setNumber }
        #expect(lastBench.map(\.weightKg) == [102.25, 102.25, 100])
        #expect(lastBench.map(\.reps) == [8, 8, 9])
        #expect(lastBench.map(\.rir) == [1, 0, 2])

        let plan = try WorkoutTemplateService.plan(for: .ppl, dayIndex: 0, context: context)
        #expect(plan.first?.repRange == 6...10)
        #expect(plan.last?.customName == "Sled Push")

        let gym = try #require(try context.fetch(FetchDescriptor<GymProfile>()).first { $0.name == "Commercial Gym" })
        #expect(gym.isActive)
        #expect(gym.loadingInventory?.plates.isEmpty == false)

        // Old logs fall back to current targets, and the engine reads them.
        let vm = ActiveSessionViewModel(sessionName: "Push", health: NoHealthWrites(), now: { Date(timeIntervalSince1970: 1_795_852_800) })
        vm.prefill(
            with: plan,
            context: context,
            progression: ProgressionContext(mode: .repsFirst, inventory: gym.loadingInventory)
        )
        #expect(vm.exercises.first?.sets.first?.recommendation != nil)

        // The new columns save and reread on migrated rows.
        let edited = try #require(sessions.first?.exercises.first)
        edited.repRangeMin = 6
        edited.repRangeMax = 10
        edited.targetSets = 3
        edited.targetRIR = 2
        try context.save()
        let rereadContext = ModelContext(context.container)
        let reread = try rereadContext.fetch(FetchDescriptor<ExerciseLog>()).filter { $0.targetSnapshot != nil }
        #expect(reread.count == 1)
        #expect(reread.first?.targetSnapshot == TemplateTargets(targetSets: 3, repRangeMin: 6, repRangeMax: 10, targetRIR: 2))
    }

    // MARK: - V4 -> V5 (frozen types)

    @Test @MainActor func v4StoreOpensWithUnfilledInventoryUntilTheBackfillRuns() throws {
        let storeURL = Self.temporaryStoreURL()
        defer { Self.removeStore(at: storeURL) }

        try {
            let schema = Schema(versionedSchema: SchemaV4.self)
            let container = try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, url: storeURL)]
            )
            let gym = SchemaV4.GymProfile(name: "Garage", preset: .homeDumbbells, isActive: true)
            gym.updateEquipment([.barbell, .bench])
            container.mainContext.insert(gym)
            container.mainContext.insert(SchemaV4.GymProfile(name: "Hotel", preset: .hotel))
            try container.mainContext.save()
        }()

        let container = try PersistenceController.makeContainer(url: storeURL)
        let context = container.mainContext
        let gyms = try context.fetch(FetchDescriptor<GymProfile>(sortBy: [SortDescriptor(\.name)]))

        #expect(gyms.map(\.name) == ["Garage", "Hotel"])
        #expect(gyms.map(\.preset) == [.custom, .hotel])
        #expect(gyms.first?.availableEquipment == [.barbell, .bench])
        #expect(gyms.first?.isActive == true)
        #expect(gyms.allSatisfy { $0.loadingInventory == nil })

        // No user yet: still unfilled. Once there is one, filled in their units.
        #expect(try GymInventoryBackfill.run(in: context) == 0)
        context.insert(UserProfile(
            name: "User", dateOfBirth: .distantPast, heightCm: 180, biologicalSex: .female,
            goalType: .maintain, activityLevel: .moderatelyActive, trainingSplit: .ppl,
            dailyCalorieTarget: 2000, proteinTargetG: 120, carbsTargetG: 220, fatTargetG: 70,
            preferredUnits: .imperial
        ))
        try context.save()
        #expect(try GymInventoryBackfill.run(in: context) == 2)
        #expect(gyms.first?.loadingInventory == .standard(units: .imperial))
        #expect(gyms.last?.loadingInventory == .withoutBarbell(units: .imperial))
    }

    // MARK: - V4 -> V5 (real store from commit 2b8a20e)

    /// `Fixtures/v4-fixture.store` was written by the shipped V4 code
    /// (commit 2b8a20e) for an imperial user: 2 Push sessions saved through
    /// `ActiveSessionViewModel.finish()` with typed lb weights, each with
    /// Barbell Bench Press (3 sets, RIRs including nil) and the custom Sled
    /// Push (1 set), the second with a HealthKit workout ID; 2 cardio entries,
    /// one with an ID; one template with target RIRs of 2, 0 and nil; and
    /// 3 gyms: Commercial Gym (active), Home, and Garage, hand-edited to
    /// custom.
    @Test @MainActor func realV4FixtureMigratesWithoutLoss() throws {
        let fixture = try Self.copyFixtureStore(named: "v4-fixture")
        defer { removeTestItem(at: fixture.directory) }
        let storeURL = fixture.store

        let store = AppDataStore(
            open: { try PersistenceController.makeContainer(url: storeURL) },
            migrateTemplates: { _ in TemplateDefaultsMigration.Outcome() }
        )
        store.load()
        let context = try #require(store.container).mainContext

        let user = try #require(try context.fetch(FetchDescriptor<UserProfile>()).first)
        #expect(user.name == "Fixture User")
        #expect(user.preferredUnits == .imperial)

        // Gyms keep everything, and load() filled them in the user's units.
        let gyms = try context.fetch(FetchDescriptor<GymProfile>(sortBy: [SortDescriptor(\.createdAt)]))
        #expect(gyms.map(\.name) == ["Commercial Gym", "Home", "Garage"])
        #expect(gyms.map(\.preset) == [.commercial, .homeDumbbells, .custom])
        #expect(gyms.map(\.isActive) == [true, false, false])
        #expect(gyms[0].availableEquipment == Set(EquipmentType.allCases))
        #expect(gyms[1].availableEquipment == GymPreset.homeDumbbells.defaultEquipment)
        #expect(gyms[2].availableEquipment == [.barbell, .bench, .bodyweight])
        #expect(gyms[0].loadingInventory
                == GymPreset.commercial.defaultInventory(units: .imperial, equipment: Set(EquipmentType.allCases)))
        #expect(gyms[0].loadingInventory?.bars(for: .smithMachine).count == 1)
        #expect(gyms[1].loadingInventory == .withoutBarbell(units: .imperial))
        #expect(gyms[2].loadingInventory == .standard(units: .imperial))
        #expect(try GymInventoryBackfill.run(in: context) == 0)

        // Workouts, RIR and HealthKit IDs are untouched.
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>(sortBy: [SortDescriptor(\.date)]))
        #expect(sessions.map(\.date) == [
            Date(timeIntervalSince1970: 1_794_470_400),
            Date(timeIntervalSince1970: 1_795_075_200),
        ])
        #expect(sessions.map(\.durationSeconds) == [3000, 3000])
        #expect(sessions.first?.healthKitWorkoutID == nil)
        #expect(sessions.last?.healthKitWorkoutID == UUID(uuidString: "11111111-2222-3333-4444-555555555555"))
        #expect(try context.fetchCount(FetchDescriptor<ExerciseLog>()) == 4)
        #expect(try context.fetchCount(FetchDescriptor<SetEntry>()) == 8)
        for session in sessions {
            let logs = session.exercises.sorted { $0.orderIndex < $1.orderIndex }
            #expect(logs.map(\.exerciseName) == ["Barbell Bench Press", "Sled Push"])
            #expect(logs.map(\.exerciseId) == ["barbell-bench-press", nil])
        }
        let firstBench = try #require(sessions.first?.exercises.first { $0.orderIndex == 0 })
            .sets.sorted { $0.setNumber < $1.setNumber }
        #expect(firstBench.map(\.weightKg) == [185, 185, 175].map(UnitConversion.kg(fromPounds:)))
        #expect(firstBench.map(\.reps) == [10, 8, 9])
        #expect(firstBench.map(\.rir) == [2, 1, nil])
        let lastBench = try #require(sessions.last?.exercises.first { $0.orderIndex == 0 })
            .sets.sorted { $0.setNumber < $1.setNumber }
        #expect(lastBench.map(\.weightKg) == [190, 190, 185].map(UnitConversion.kg(fromPounds:)))
        #expect(lastBench.map(\.rir) == [1, 0, 2])

        let records = WorkoutHomeViewModel.computePersonalRecords(from: context)
        let benchPR = try #require(records.first { $0.exerciseId == "barbell-bench-press" })
        #expect(benchPR.weightKg == UnitConversion.kg(fromPounds: 190))
        #expect(records.first { $0.exerciseName == "Sled Push" }?.weightKg == UnitConversion.kg(fromPounds: 245))

        let cardio = try context.fetch(FetchDescriptor<CardioEntry>(sortBy: [SortDescriptor(\.date)]))
        #expect(cardio.map(\.type) == [.treadmill, .stationaryBike])
        #expect(cardio.first?.healthKitWorkoutID == UUID(uuidString: "66666666-7777-8888-9999-000000000000"))
        #expect(cardio.last?.healthKitWorkoutID == nil)
        #expect(cardio.last?.resistanceLevel == 8)

        let push = try #require(try WorkoutTemplateService.template(for: .ppl, dayIndex: 0, context: context))
        #expect(push.orderedExercises.map(\.exerciseId) == ["barbell-bench-press", "lateral-raise", nil])
        #expect(push.orderedExercises.map(\.targetRIR) == [2, 0, nil])
        #expect(push.orderedExercises.map(\.customName) == [nil, nil, "Sled Push"])

        // The new columns save and reread on migrated rows.
        let edited = LoadingInventory(
            bars: [GymBar(name: "Rusty", weightKg: 18)],
            plates: [PlateStock(weightKg: 20, pairCount: 1)],
            dumbbellIncrementKg: 2,
            machineIncrementKg: 4
        )
        gyms[2].updateInventory(edited)
        try context.save()
        let reread = try ModelContext(context.container).fetch(FetchDescriptor<GymProfile>())
        #expect(reread.first { $0.name == "Garage" }?.loadingInventory == edited)
    }

    /// Older stores reach V5 through the whole chain and fill the same way.
    @Test @MainActor func realV3FixtureReachesV5WithAFilledGym() throws {
        let fixture = try Self.copyFixtureStore(named: "v3-fixture")
        defer { removeTestItem(at: fixture.directory) }
        let storeURL = fixture.store

        let store = AppDataStore(
            open: { try PersistenceController.makeContainer(url: storeURL) },
            migrateTemplates: { _ in TemplateDefaultsMigration.Outcome() }
        )
        store.load()
        let context = try #require(store.container).mainContext
        let units = try #require(try context.fetch(FetchDescriptor<UserProfile>()).first).preferredUnits

        let gym = try #require(try context.fetch(FetchDescriptor<GymProfile>()).first)
        #expect(gym.loadingInventory
                == gym.preset.defaultInventory(units: units, equipment: gym.availableEquipment))
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

    /// A new install has no user yet, so nothing is known about its plates.
    @Test func freshInstallLeavesTheSeededGymUnfilled() throws {
        let store = AppDataStore(open: { try PersistenceController.makeContainer(inMemory: true) }, migrateTemplates: Self.noTemplateMigration)
        store.load()

        let container = try #require(store.container)
        let gym = try #require(try container.mainContext.fetch(FetchDescriptor<GymProfile>()).first)
        #expect(gym.loadingInventory == nil)
    }

    @Test func gymInventoryBackfillFailureDoesNotBlockLaunch() {
        let store = AppDataStore(
            open: { try PersistenceController.makeContainer(inMemory: true) },
            migrateTemplates: Self.noTemplateMigration,
            backfillGymInventories: { _ in throw OpenFailure() }
        )
        store.load()
        #expect(store.container != nil)
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
