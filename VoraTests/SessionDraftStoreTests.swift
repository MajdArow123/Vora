//
//  SessionDraftStoreTests.swift
//  VoraTests
//
//  Created by Majd Arow on 2026-11-01.
//

import Foundation
import Testing
@testable import Vora

struct SessionDraftStoreTests {
    private let directory: URL
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    init() {
        directory = FileManager.default.temporaryDirectory
            .appending(path: "SessionDraftStoreTests-\(UUID().uuidString)")
    }

    private func store(at now: Date) -> SessionDraftStore {
        SessionDraftStore(directory: directory, now: { now })
    }

    private func sampleDraft(savedAt: Date) -> ActiveSessionDraft {
        ActiveSessionDraft(
            sessionName: "Push",
            startDate: start,
            savedAt: savedAt,
            restEndDate: start.addingTimeInterval(600),
            excludedSeconds: 30,
            exercises: [
                ActiveSessionDraft.Exercise(
                    exerciseId: "barbell-bench-press",
                    customName: nil,
                    muscleGroups: ["chest"],
                    restSeconds: 120,
                    targets: TemplateTargets(targetSets: 3, repRangeMin: 6, repRangeMax: 10, targetRIR: 2),
                    sets: [
                        ActiveSessionDraft.Set(weightKg: 102.25, reps: 8, isCompleted: true),
                        ActiveSessionDraft.Set(weightKg: nil, reps: nil, isCompleted: false),
                    ]
                ),
                ActiveSessionDraft.Exercise(
                    exerciseId: nil,
                    customName: "Sled Push",
                    muscleGroups: [],
                    restSeconds: 90,
                    targets: nil,
                    sets: [ActiveSessionDraft.Set(weightKg: 40, reps: 20, isCompleted: false)]
                ),
            ]
        )
    }

    private func setAsideFiles() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix("ActiveSessionDraft.corrupt-") }
    }

    @Test func saveAndLoadRoundTripsEveryField() throws {
        defer { removeTestItem(at: directory) }
        let draft = sampleDraft(savedAt: start.addingTimeInterval(300))
        try store(at: start).save(draft)

        let loaded = try #require(store(at: start.addingTimeInterval(600)).loadResumable())
        #expect(loaded == draft)
    }

    @Test func missingFileLoadsNothing() {
        defer { removeTestItem(at: directory) }
        #expect(store(at: start).loadResumable() == nil)
    }

    @Test func draftJustUnderTwelveHoursIsResumable() throws {
        defer { removeTestItem(at: directory) }
        try store(at: start).save(sampleDraft(savedAt: start))
        let almost = start.addingTimeInterval(SessionDraftStore.maxAge - 1)
        #expect(store(at: almost).loadResumable() != nil)
    }

    @Test func draftTwelveHoursOldExpiresAndIsCleared() throws {
        defer { removeTestItem(at: directory) }
        let saved = store(at: start)
        try saved.save(sampleDraft(savedAt: start))
        let later = store(at: start.addingTimeInterval(SessionDraftStore.maxAge))

        #expect(later.loadResumable() == nil)
        #expect(!FileManager.default.fileExists(atPath: later.fileURL.path))
    }

    @Test func corruptFileIsSetAsideWithoutCrashing() throws {
        defer { removeTestItem(at: directory) }
        let draftStore = store(at: start)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: draftStore.fileURL)

        #expect(draftStore.loadResumable() == nil)
        #expect(!FileManager.default.fileExists(atPath: draftStore.fileURL.path))
        #expect(try setAsideFiles().count == 1)
        // The next launch sees no draft at all.
        #expect(draftStore.loadResumable() == nil)
    }

    @Test func unknownVersionIsSetAside() throws {
        defer { removeTestItem(at: directory) }
        let draftStore = store(at: start)
        var draft = sampleDraft(savedAt: start)
        draft.version = ActiveSessionDraft.currentVersion + 1
        try draftStore.save(draft)

        #expect(draftStore.loadResumable() == nil)
        #expect(!FileManager.default.fileExists(atPath: draftStore.fileURL.path))
        #expect(try setAsideFiles().count == 1)
    }

    @Test func draftWithoutExercisesIsCleared() throws {
        defer { removeTestItem(at: directory) }
        let draftStore = store(at: start)
        var draft = sampleDraft(savedAt: start)
        draft.exercises = []
        try draftStore.save(draft)

        #expect(draftStore.loadResumable() == nil)
        #expect(!FileManager.default.fileExists(atPath: draftStore.fileURL.path))
    }

    @Test func clearRemovesTheDraftAndToleratesAMissingFile() throws {
        defer { removeTestItem(at: directory) }
        let draftStore = store(at: start)
        try draftStore.save(sampleDraft(savedAt: start))

        draftStore.clear()
        #expect(!FileManager.default.fileExists(atPath: draftStore.fileURL.path))
        draftStore.clear()
    }

    @Test func saveReplacesThePreviousDraft() throws {
        defer { removeTestItem(at: directory) }
        let draftStore = store(at: start)
        try draftStore.save(sampleDraft(savedAt: start))
        var updated = sampleDraft(savedAt: start.addingTimeInterval(60))
        updated.sessionName = "Pull"
        try draftStore.save(updated)

        #expect(draftStore.loadResumable()?.sessionName == "Pull")
    }
}
