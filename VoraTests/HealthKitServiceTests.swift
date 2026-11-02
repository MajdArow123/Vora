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

/// HealthKit's authorized read/write paths need a real device and user
/// consent, so tests cover the synchronous guards and the pure matching;
/// the store-facing code is deliberately best-effort (see HealthKitService).
struct HealthKitServiceTests {
    @Test func invalidDateRangeIsRejectedBeforeTouchingHealthKit() async {
        let service = HealthKitService()
        // end == start and end < start must both return without any
        // HealthKit interaction (no permission prompt in the test host
        // proves the early guard fired).
        #expect(await service.saveStrengthWorkout(start: .now, end: .now) == nil)
        #expect(await service.saveStrengthWorkout(start: .now, end: .now.addingTimeInterval(-60)) == nil)
        #expect(await service.saveCardioWorkout(type: .run, start: .now, end: .now, calories: 300) == nil)
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
