//
//  WorkoutDeletionServiceTests.swift
//  VoraTests
//
//  Created by Majd Arow on 2026-11-02.
//

import Foundation
import SwiftData
import Testing
@testable import Vora

private enum StubError: Error {
    case failed
}

private final class StubHealth: HealthWorkoutDeleting {
    enum Outcome {
        case result(HealthWorkoutDeletionResult)
        case failure
    }

    private let outcome: Outcome
    private(set) var requests: [HealthWorkoutTarget] = []

    init(_ outcome: Outcome = .result(.deleted)) {
        self.outcome = outcome
    }

    func deleteWorkout(id: UUID) async throws -> HealthWorkoutDeletionResult {
        requests.append(.id(id))
        return try result()
    }

    func deleteWorkout(matching match: HealthWorkoutMatch) async throws -> HealthWorkoutDeletionResult {
        requests.append(.match(match))
        return try result()
    }

    private func result() throws -> HealthWorkoutDeletionResult {
        switch outcome {
        case .result(let result): return result
        case .failure: throw StubError.failed
        }
    }
}

struct WorkoutDeletionServiceTests {
    private let container: ModelContainer
    private let context: ModelContext

    init() throws {
        let schema = Schema(CurrentSchema.models)
        container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        context = ModelContext(container)
    }

    private func date(daysAgo: Int) -> Date {
        Date.now.addingTimeInterval(-Double(daysAgo) * 86_400)
    }

    @discardableResult
    private func insertSession(
        daysAgo: Int = 1,
        exercise: String = "Custom Press",
        weight: Double = 100,
        reps: Int = 5,
        durationSeconds: Int = 3600,
        volume: Double = 500
    ) -> WorkoutSession {
        let log = ExerciseLog(
            exerciseName: exercise,
            orderIndex: 0,
            sets: [SetEntry(setNumber: 1, weightKg: weight, reps: reps, isCompleted: true)]
        )
        let session = WorkoutSession(
            date: date(daysAgo: daysAgo),
            sessionName: "Session",
            durationSeconds: durationSeconds,
            totalVolumeKg: volume,
            exercises: [log]
        )
        context.insert(session)
        return session
    }

    @discardableResult
    private func insertCardio(date: Date, durationSeconds: Int = 1800) -> CardioEntry {
        let entry = CardioEntry(date: date, type: .run, durationSeconds: durationSeconds, estimatedCalories: 300)
        context.insert(entry)
        return entry
    }

    private func count<T: PersistentModel>(_: T.Type) throws -> Int {
        try context.fetchCount(FetchDescriptor<T>())
    }

    // MARK: - Cascade

    @Test func deletingSessionCascadesToExercisesAndSets() throws {
        let doomed = insertSession()
        insertSession(daysAgo: 2)
        try context.save()
        #expect(try count(ExerciseLog.self) == 2)
        #expect(try count(SetEntry.self) == 2)

        _ = try WorkoutDeletionService(health: StubHealth()).delete(doomed, context: context)

        #expect(try count(WorkoutSession.self) == 1)
        #expect(try count(ExerciseLog.self) == 1)
        #expect(try count(SetEntry.self) == 1)
    }

    // MARK: - Cardio

    @Test func deletingCardioRemovesTheEntry() throws {
        let entry = insertCardio(date: date(daysAgo: 1))
        insertCardio(date: date(daysAgo: 2))
        try context.save()

        _ = try WorkoutDeletionService(health: StubHealth()).delete(entry, context: context)

        #expect(try count(CardioEntry.self) == 1)
    }

    @Test func deletingSessionLeavesSameDayCardio() throws {
        let session = insertSession()
        insertCardio(date: session.date.addingTimeInterval(60))
        try context.save()

        _ = try WorkoutDeletionService(health: StubHealth()).delete(session, context: context)

        #expect(try count(WorkoutSession.self) == 0)
        #expect(try count(CardioEntry.self) == 1)
    }

    // MARK: - Personal records

    @Test func deletingThePRSessionFallsBackToTheNextBestSet() throws {
        let prSession = insertSession(daysAgo: 1, weight: 120, reps: 3)
        let nextBest = insertSession(daysAgo: 5, weight: 100, reps: 8)
        insertSession(daysAgo: 9, weight: 90, reps: 10)
        try context.save()
        let nextBestDate = nextBest.date
        #expect(WorkoutHomeViewModel.computePersonalRecords(from: context).first?.weightKg == 120)

        _ = try WorkoutDeletionService(health: StubHealth()).delete(prSession, context: context)

        let records = WorkoutHomeViewModel.computePersonalRecords(from: context)
        #expect(records.count == 1)
        #expect(records.first?.weightKg == 100)
        #expect(records.first?.reps == 8)
        #expect(records.first?.date == nextBestDate)
    }

    @Test func deletingTheOnlySessionForAnExerciseRemovesItsPR() throws {
        let only = insertSession(exercise: "Custom Curl", weight: 30)
        insertSession(daysAgo: 2, exercise: "Custom Press", weight: 100)
        try context.save()

        _ = try WorkoutDeletionService(health: StubHealth()).delete(only, context: context)

        let records = WorkoutHomeViewModel.computePersonalRecords(from: context)
        #expect(records.map(\.exerciseName) == ["Custom Press"])
    }

    // MARK: - Charts

    @Test func chartsDropTheDeletedSessionAfterReload() throws {
        let now = Date.now
        let doomed = insertSession(daysAgo: 1, weight: 120, volume: 900)
        insertSession(daysAgo: 8, weight: 100, volume: 400)
        insertSession(daysAgo: 15, weight: 90, volume: 300)
        try context.save()

        let viewModel = StrengthProgressViewModel()
        viewModel.selectedExercise = "Custom Press"
        viewModel.load(from: context, now: now)
        #expect(viewModel.progression.count == 3)
        #expect(viewModel.weeklyVolume.map(\.volumeKg).reduce(0, +) == 1600)

        _ = try WorkoutDeletionService(health: StubHealth()).delete(doomed, context: context)
        viewModel.load(from: context, now: now)

        #expect(viewModel.progression.count == 2)
        #expect(viewModel.progression.map(\.bestWeightKg).max() == 100)
        #expect(viewModel.weeklyVolume.map(\.volumeKg).reduce(0, +) == 700)
    }

    // MARK: - HealthKit failures never block the delete

    @Test(arguments: [
        StubHealth.Outcome.failure,
        StubHealth.Outcome.result(.noMatch),
        StubHealth.Outcome.result(.ambiguous),
    ])
    fileprivate func healthKitProblemsDoNotBlockSessionDelete(outcome: StubHealth.Outcome) async throws {
        let session = insertSession()
        try context.save()
        let health = StubHealth(outcome)
        let service = WorkoutDeletionService(health: health)

        let match = try service.delete(session, context: context)
        let result = await service.removeFromHealth(match)

        #expect(health.requests.count == 1)
        #expect(result != .deleted)
        #expect(try count(WorkoutSession.self) == 0)
        #expect(try count(ExerciseLog.self) == 0)
        #expect(try count(SetEntry.self) == 0)
    }

    @Test func healthKitFailureDoesNotBlockCardioDelete() async throws {
        let entry = insertCardio(date: date(daysAgo: 1))
        try context.save()
        let service = WorkoutDeletionService(health: StubHealth(.failure))

        let match = try service.delete(entry, context: context)
        let result = await service.removeFromHealth(match)

        #expect(result == nil)
        #expect(try count(CardioEntry.self) == 0)
    }

    @Test func zeroDurationSessionDeletesWithoutAskingHealthKit() async throws {
        let session = insertSession(durationSeconds: 0)
        try context.save()
        let health = StubHealth()
        let service = WorkoutDeletionService(health: health)

        let match = try service.delete(session, context: context)
        let result = await service.removeFromHealth(match)

        #expect(match == nil)
        #expect(result == nil)
        #expect(health.requests.isEmpty)
        #expect(try count(WorkoutSession.self) == 0)
    }

    // MARK: - Stored HealthKit ID

    @Test func storedSessionIDIsUsedInsteadOfMatching() async throws {
        let workoutID = UUID()
        let session = insertSession()
        session.healthKitWorkoutID = workoutID
        try context.save()
        let health = StubHealth()
        let service = WorkoutDeletionService(health: health)

        let target = try service.delete(session, context: context)
        let result = await service.removeFromHealth(target)

        #expect(result == .deleted)
        #expect(health.requests == [.id(workoutID)])
    }

    @Test func storedCardioIDIsUsedInsteadOfMatching() async throws {
        let workoutID = UUID()
        let entry = insertCardio(date: date(daysAgo: 1))
        entry.healthKitWorkoutID = workoutID
        try context.save()
        let health = StubHealth()
        let service = WorkoutDeletionService(health: health)

        let target = try service.delete(entry, context: context)
        await service.removeFromHealth(target)

        #expect(health.requests == [.id(workoutID)])
    }

    @Test func nilIDFallsBackToMatchingForBothKinds() async throws {
        let session = insertSession()
        let entry = insertCardio(date: date(daysAgo: 2))
        try context.save()
        let expectedSession = try #require(HealthWorkoutMatch(session: session))
        let expectedCardio = try #require(HealthWorkoutMatch(cardio: entry))
        let health = StubHealth()
        let service = WorkoutDeletionService(health: health)

        await service.removeFromHealth(try service.delete(session, context: context))
        await service.removeFromHealth(try service.delete(entry, context: context))

        #expect(health.requests == [.match(expectedSession), .match(expectedCardio)])
    }

    /// The workout may have been removed in the Health app; a different one
    /// in the same window must not be deleted in its place.
    @Test func idNotFoundInHealthKitDoesNotFallBackToMatching() async throws {
        let workoutID = UUID()
        let session = insertSession()
        session.healthKitWorkoutID = workoutID
        try context.save()
        let health = StubHealth(.result(.noMatch))
        let service = WorkoutDeletionService(health: health)

        let target = try service.delete(session, context: context)
        let result = await service.removeFromHealth(target)

        #expect(result == .noMatch)
        #expect(health.requests == [.id(workoutID)])
        #expect(try count(WorkoutSession.self) == 0)
    }

    @Test func storedIDIsUsedEvenWithZeroDuration() throws {
        let workoutID = UUID()
        let session = WorkoutSession(date: .now, sessionName: "Push", healthKitWorkoutID: workoutID)
        #expect(HealthWorkoutTarget(session: session) == .id(workoutID))
    }

    @Test func failedSaveWithStoredIDNeverReachesHealthKit() throws {
        let session = insertSession()
        session.healthKitWorkoutID = UUID()
        try context.save()
        let health = StubHealth()
        let service = WorkoutDeletionService(health: health)

        #expect(throws: StubError.self) {
            _ = try service.delete(session, context: context, save: { _ in throw StubError.failed })
        }

        #expect(health.requests.isEmpty)
        #expect(try count(WorkoutSession.self) == 1)
    }

    // MARK: - Failed local save

    @Test func failedSaveKeepsTheSessionAndNeverReachesHealthKit() throws {
        let session = insertSession()
        try context.save()
        let health = StubHealth()
        let service = WorkoutDeletionService(health: health)

        #expect(throws: StubError.self) {
            _ = try service.delete(session, context: context, save: { _ in throw StubError.failed })
        }

        #expect(health.requests.isEmpty)
        #expect(try count(WorkoutSession.self) == 1)
        #expect(try count(ExerciseLog.self) == 1)
        #expect(try count(SetEntry.self) == 1)
        #expect(!context.hasChanges)
    }

    @Test func failedSaveLeavesTheSessionReadable() throws {
        let session = insertSession()
        try context.save()

        #expect(throws: StubError.self) {
            _ = try WorkoutDeletionService(health: StubHealth())
                .delete(session, context: context, save: { _ in throw StubError.failed })
        }

        #expect(session.exercises.count == 1)
        #expect(session.exercises.first?.sets.count == 1)
    }

    @Test func failedSaveKeepsUnrelatedPendingChanges() throws {
        let session = insertSession()
        try context.save()
        insertCardio(date: date(daysAgo: 1))

        #expect(throws: StubError.self) {
            _ = try WorkoutDeletionService(health: StubHealth())
                .delete(session, context: context, save: { _ in throw StubError.failed })
        }

        #expect(context.hasChanges)
        try context.save()
        #expect(try count(CardioEntry.self) == 1)
        #expect(try count(WorkoutSession.self) == 1)
    }

    @Test func successfulDeleteKeepsUnrelatedPendingChanges() throws {
        let session = insertSession()
        try context.save()
        insertCardio(date: date(daysAgo: 1))

        _ = try WorkoutDeletionService(health: StubHealth()).delete(session, context: context)

        try context.save()
        #expect(try count(CardioEntry.self) == 1)
        #expect(try count(WorkoutSession.self) == 0)
    }
}
