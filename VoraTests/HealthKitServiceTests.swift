//
//  HealthKitServiceTests.swift
//  VoraTests
//
//  Created by Majd Arow on 2026-07-21.
//

import Foundation
import HealthKit
import Testing
@testable import Vora

private final class StubRecorder: HealthWorkoutRecording {
    struct Write: Equatable {
        let activity: HKWorkoutActivityType
        let start: Date
        let end: Date
        let calories: Double?
    }

    struct RecordFailure: Error {}

    private let result: Result<UUID?, RecordFailure>
    private(set) var writes: [Write] = []

    init(result: Result<UUID?, RecordFailure> = .success(UUID())) {
        self.result = result
    }

    func record(activity: HKWorkoutActivityType, start: Date, end: Date, calories: Double?) async throws -> UUID? {
        writes.append(Write(activity: activity, start: start, end: end, calories: calories))
        return try result.get()
    }
}

/// HealthKit's authorized read/write paths need a real device and user
/// consent, so tests cover the guards through a stub recorder, plus the pure
/// matching; the store-facing code is deliberately best-effort (see
/// HealthKitService). Dates are fixed: a second `.now` usually equals the
/// first but can land on the next clock tick and pass the guard.
struct HealthKitServiceTests {
    @Test func invalidDateRangeIsRejectedBeforeTouchingHealthKit() async {
        let recorder = StubRecorder()
        let service = HealthKitService(recorder: recorder)
        let start = Date(timeIntervalSince1970: 1_000_000)
        let earlier = start.addingTimeInterval(-60)

        #expect(await service.saveStrengthWorkout(start: start, end: start) == nil)
        #expect(await service.saveStrengthWorkout(start: start, end: earlier) == nil)
        #expect(await service.saveCardioWorkout(type: .run, start: start, end: start, calories: 300) == nil)
        #expect(await service.saveCardioWorkout(type: .run, start: start, end: earlier, calories: 300) == nil)
        #expect(recorder.writes.isEmpty)
    }

    @Test func validDateRangeReachesTheRecorder() async {
        let id = UUID()
        let recorder = StubRecorder(result: .success(id))
        let service = HealthKitService(recorder: recorder)
        let start = Date(timeIntervalSince1970: 1_000_000)
        let end = start.addingTimeInterval(1)

        #expect(await service.saveStrengthWorkout(start: start, end: end) == id)
        #expect(await service.saveCardioWorkout(type: .row, start: start, end: end, calories: 300) == id)
        #expect(recorder.writes == [
            .init(activity: .traditionalStrengthTraining, start: start, end: end, calories: nil),
            .init(activity: .rowing, start: start, end: end, calories: 300),
        ])
    }

    @Test func recorderFailureIsAbsorbed() async {
        let recorder = StubRecorder(result: .failure(.init()))
        let service = HealthKitService(recorder: recorder)
        let start = Date(timeIntervalSince1970: 1_000_000)

        #expect(await service.saveStrengthWorkout(start: start, end: start.addingTimeInterval(1)) == nil)
        #expect(recorder.writes.count == 1)
    }

    // MARK: - Target construction

    @Test func targetPrefersTheStoredID() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let id = UUID()
        let session = WorkoutSession(date: start, sessionName: "Push", durationSeconds: 3600, healthKitWorkoutID: id)
        let entry = CardioEntry(date: start, type: .run, durationSeconds: 1800, estimatedCalories: 200, healthKitWorkoutID: id)

        #expect(HealthWorkoutTarget(session: session) == .id(id))
        #expect(HealthWorkoutTarget(cardio: entry) == .id(id))
    }

    @Test func targetFallsBackToTheMatchWithoutAnID() throws {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let session = WorkoutSession(date: start, sessionName: "Push", durationSeconds: 3600)
        let entry = CardioEntry(date: start, type: .run, durationSeconds: 1800, estimatedCalories: 200)

        let sessionMatch = try #require(HealthWorkoutMatch(session: session))
        let cardioMatch = try #require(HealthWorkoutMatch(cardio: entry))
        #expect(HealthWorkoutTarget(session: session) == .match(sessionMatch))
        #expect(HealthWorkoutTarget(cardio: entry) == .match(cardioMatch))
    }

    @Test func noTargetWithoutAnIDOrADuration() {
        let date = Date(timeIntervalSince1970: 1_000_000)
        #expect(HealthWorkoutTarget(session: WorkoutSession(date: date, sessionName: "Push")) == nil)
        #expect(HealthWorkoutTarget(cardio: CardioEntry(
            date: date, type: .run, durationSeconds: 0, estimatedCalories: 0
        )) == nil)
    }

    // MARK: - Match construction

    @Test func sessionMatchStartsAtTheSessionDate() throws {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let session = WorkoutSession(date: start, sessionName: "Push", durationSeconds: 3600)

        let match = try #require(HealthWorkoutMatch(session: session))

        #expect(match.activityType == .traditionalStrengthTraining)
        #expect(match.start == start)
        #expect(match.end == start.addingTimeInterval(3600))
    }

    @Test func cardioMatchEndsAtTheEntryDate() throws {
        let end = Date(timeIntervalSince1970: 1_000_000)
        let entry = CardioEntry(date: end, type: .stationaryBike, durationSeconds: 1800, estimatedCalories: 200)

        let match = try #require(HealthWorkoutMatch(cardio: entry))

        #expect(match.activityType == .cycling)
        #expect(match.start == end.addingTimeInterval(-1800))
        #expect(match.end == end)
    }

    @Test func zeroDurationHasNoMatchBecauseItWasNeverWritten() {
        let date = Date(timeIntervalSince1970: 1_000_000)
        #expect(HealthWorkoutMatch(session: WorkoutSession(date: date, sessionName: "Push")) == nil)
        #expect(HealthWorkoutMatch(cardio: CardioEntry(
            date: date, type: .run, durationSeconds: 0, estimatedCalories: 0
        )) == nil)
    }

    // MARK: - Matching

    private let start = Date(timeIntervalSince1970: 1_000_000)
    private var end: Date { start.addingTimeInterval(3600) }

    private func match() throws -> HealthWorkoutMatch {
        try #require(HealthWorkoutMatch(activityType: .running, start: start, end: end))
    }

    private func candidate(
        activity: HKWorkoutActivityType = .running,
        startOffset: TimeInterval = 0,
        endOffset: TimeInterval = 0
    ) -> HealthWorkoutCandidate {
        HealthWorkoutCandidate(
            id: UUID(),
            activityType: activity,
            start: start.addingTimeInterval(startOffset),
            end: end.addingTimeInterval(endOffset)
        )
    }

    @Test func selectsTheOnlyFittingWorkout() throws {
        let exact = candidate()
        let other = candidate(startOffset: -7200, endOffset: -7200)

        let selection = HealthWorkoutMatcher.select(candidates: [other, exact], match: try match())

        #expect(selection == .match(exact.id))
    }

    @Test func toleratesTheLateEndTimeOfOlderSessions() throws {
        let late = candidate(endOffset: HealthWorkoutMatcher.tolerance)

        #expect(HealthWorkoutMatcher.select(candidates: [late], match: try match()) == .match(late.id))
    }

    @Test func rejectsWorkoutsOutsideTheTolerance() throws {
        let tolerance = HealthWorkoutMatcher.tolerance
        let candidates = [
            candidate(startOffset: tolerance + 1),
            candidate(startOffset: -(tolerance + 1)),
            candidate(endOffset: tolerance + 1),
            candidate(endOffset: -(tolerance + 1)),
        ]

        #expect(HealthWorkoutMatcher.select(candidates: candidates, match: try match()) == .none)
    }

    @Test func ignoresOtherActivities() throws {
        let selection = HealthWorkoutMatcher.select(candidates: [candidate(activity: .walking)], match: try match())

        #expect(selection == .none)
    }

    @Test func twoFittingWorkoutsAreAmbiguousAndNeitherIsSelected() throws {
        let selection = HealthWorkoutMatcher.select(
            candidates: [candidate(), candidate(startOffset: 1)],
            match: try match()
        )

        #expect(selection == .ambiguous)
    }

    @Test func noCandidatesIsNoMatch() throws {
        #expect(HealthWorkoutMatcher.select(candidates: [], match: try match()) == .none)
    }
}
