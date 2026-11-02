//
//  HealthWorkoutLinkTests.swift
//  VoraTests
//
//  Created by Majd Arow on 2026-11-02.
//

import Foundation
import SwiftData
import Testing
@testable import Vora

private final class StubWriter: HealthWorkoutWriting {
    private let workoutID: UUID?
    private let onWrite: () -> Void
    private(set) var strengthWrites: [(start: Date, end: Date)] = []
    private(set) var cardioWrites: [CardioType] = []

    init(workoutID: UUID?, onWrite: @escaping () -> Void = {}) {
        self.workoutID = workoutID
        self.onWrite = onWrite
    }

    func saveStrengthWorkout(start: Date, end: Date) async -> UUID? {
        strengthWrites.append((start, end))
        onWrite()
        return workoutID
    }

    func saveCardioWorkout(type: CardioType, start: Date, end: Date, calories: Double) async -> UUID? {
        cardioWrites.append(type)
        onWrite()
        return workoutID
    }
}

private struct SaveFailure: Error {}

/// Storing the UUID HealthKit returns on the row it belongs to.
@MainActor
struct HealthWorkoutLinkTests {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    init() throws {
        container = try PersistenceController.makeContainer(inMemory: true)
    }

    private func finishedSession(
        writer: StubWriter,
        save: (ModelContext) throws -> Void = { try $0.save() }
    ) -> ActiveSessionViewModel {
        var now = start
        let viewModel = ActiveSessionViewModel(sessionName: "Push", health: writer, now: { now })
        viewModel.addExercise(name: "Sled Push", muscleGroups: [], context: context)
        viewModel.exercises[0].sets[0].weightText = "100"
        viewModel.exercises[0].sets[0].repsText = "5"
        _ = viewModel.toggleCompletion(setID: viewModel.exercises[0].sets[0].id, in: viewModel.exercises[0].id)
        now = start.addingTimeInterval(1800)
        viewModel.finish(context: context, save: save)
        return viewModel
    }

    private func session() throws -> WorkoutSession {
        try #require(try context.fetch(FetchDescriptor<WorkoutSession>()).first)
    }

    // MARK: - Strength

    @Test func strengthWorkoutIDIsStoredOnTheSession() async throws {
        let workoutID = UUID()
        let writer = StubWriter(workoutID: workoutID)
        let viewModel = finishedSession(writer: writer)

        await viewModel.recordHealthWorkout(context: context)

        #expect(try session().healthKitWorkoutID == workoutID)
        #expect(writer.strengthWrites.count == 1)
        #expect(writer.strengthWrites.first?.start == start)
        #expect(writer.strengthWrites.first?.end == start.addingTimeInterval(1800))
        #expect(!context.hasChanges)
    }

    @Test func strengthWorkoutNotWrittenLeavesTheIDNil() async throws {
        let viewModel = finishedSession(writer: StubWriter(workoutID: nil))

        await viewModel.recordHealthWorkout(context: context)

        #expect(try session().healthKitWorkoutID == nil)
    }

    @Test func failedLocalSaveNeverWritesTheStrengthWorkout() async {
        let writer = StubWriter(workoutID: UUID())
        let viewModel = finishedSession(writer: writer, save: { _ in throw SaveFailure() })
        #expect(viewModel.savedSessionID == nil)

        await viewModel.recordHealthWorkout(context: context)

        #expect(writer.strengthWrites.isEmpty)
    }

    @Test func sessionDeletedDuringTheWriteIsTolerated() async throws {
        let holder = ContextHolder(context: context)
        let writer = StubWriter(workoutID: UUID(), onWrite: { holder.deleteSessions() })
        let viewModel = finishedSession(writer: writer)

        await viewModel.recordHealthWorkout(context: context)

        #expect(try context.fetchCount(FetchDescriptor<WorkoutSession>()) == 0)
    }

    // MARK: - Cardio

    private func entry() throws -> CardioEntry {
        try #require(try context.fetch(FetchDescriptor<CardioEntry>()).first)
    }

    @Test func cardioWorkoutIDIsStoredOnTheEntry() async throws {
        let workoutID = UUID()
        let writer = StubWriter(workoutID: workoutID)
        let viewModel = CardioLogViewModel(health: writer)

        await viewModel.save(in: context)?.value

        #expect(try entry().healthKitWorkoutID == workoutID)
        #expect(writer.cardioWrites == [.treadmill])
        #expect(!context.hasChanges)
    }

    @Test func cardioWorkoutNotWrittenLeavesTheIDNil() async throws {
        let viewModel = CardioLogViewModel(health: StubWriter(workoutID: nil))

        await viewModel.save(in: context)?.value

        #expect(try entry().healthKitWorkoutID == nil)
    }

    @Test func failedLocalSaveNeverWritesTheCardioWorkout() {
        let writer = StubWriter(workoutID: UUID())
        let viewModel = CardioLogViewModel(health: writer)

        let task = viewModel.save(in: context, save: { _ in throw SaveFailure() })

        #expect(task == nil)
        #expect(writer.cardioWrites.isEmpty)
    }

    @Test func cardioDeletedDuringTheWriteIsTolerated() async throws {
        let holder = ContextHolder(context: context)
        let writer = StubWriter(workoutID: UUID(), onWrite: { holder.deleteCardio() })
        let viewModel = CardioLogViewModel(health: writer)

        await viewModel.save(in: context)?.value

        #expect(try context.fetchCount(FetchDescriptor<CardioEntry>()) == 0)
    }
}

/// Lets a stub delete rows mid-write, as a user could from History.
@MainActor
private final class ContextHolder {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func deleteSessions() {
        do {
            try context.delete(model: WorkoutSession.self)
            try context.save()
        } catch {
            Issue.record(error)
        }
    }

    func deleteCardio() {
        do {
            try context.delete(model: CardioEntry.self)
            try context.save()
        } catch {
            Issue.record(error)
        }
    }
}
