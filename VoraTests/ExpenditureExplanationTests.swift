//
//  ExpenditureExplanationTests.swift
//  VoraTests
//
//  Created by Majd Arow on 2026-11-02.
//

import Foundation
import Testing
@testable import Vora

struct ExpenditureExplanationTests {
    private static func proposal(
        estimate: Double = 3150,
        previous: Double = 3000,
        raw: Double = 3150,
        excluded: Int = 0,
        wasCapped: Bool = false,
        reason: ExpenditureEstimator.Reason = .fullData,
        isFloored: Bool = false
    ) -> ExpenditureProposal {
        ExpenditureProposal(
            checkInDate: Date(timeIntervalSince1970: 1_795_075_200),
            previousEstimate: previous,
            result: ExpenditureEstimator.Result(
                estimate: estimate,
                rawEstimate: raw,
                averageIntake: 2600,
                slopeKgPerDay: -0.5 / 7,
                daysUsed: 19,
                weighInsUsed: 18,
                excludedIncompleteDays: excluded,
                wasCapped: wasCapped,
                reason: reason
            ),
            currentTargets: MacroTargets(calories: 2400, proteinG: 160, carbsG: 250, fatG: 65),
            proposedTargets: ExpenditureTargets(calories: 2520, proteinG: 162, carbsG: 310, fatG: 70, isFloored: isFloored),
            floorCalories: 1800
        )
    }

    @Test func weeklyRateRespectsUnits() {
        #expect(ExpenditureExplanation.weeklyRate(slopeKgPerDay: -0.5 / 7, units: .metric) == "-0.5 kg/week")
        #expect(ExpenditureExplanation.weeklyRate(slopeKgPerDay: -0.5 / 7, units: .imperial) == "-1.1 lb/week")
        #expect(ExpenditureExplanation.weeklyRate(slopeKgPerDay: 0.25 / 7, units: .imperial) == "+0.6 lb/week")
        #expect(ExpenditureExplanation.weeklyRate(slopeKgPerDay: 0, units: .metric) == "0.0 kg/week")
    }

    @Test func summaryNamesTheChangeAndItsCausesInTheUsersUnits() {
        #expect(ExpenditureExplanation.summary(Self.proposal(), units: .metric)
            == "Your expenditure estimate went up by 150 kcal. You averaged 2600 kcal a day while your weight changed -0.5 kg/week.")
        #expect(ExpenditureExplanation.summary(Self.proposal(), units: .imperial).hasSuffix("-1.1 lb/week."))
        #expect(ExpenditureExplanation.summary(Self.proposal(estimate: 2900), units: .metric).hasPrefix("Your expenditure estimate went down by 100 kcal."))
        #expect(ExpenditureExplanation.summary(Self.proposal(estimate: 3000), units: .metric).hasPrefix("Your expenditure estimate is holding steady."))
    }

    @Test func daysLoggedCountsAgainstTheWindow() {
        #expect(ExpenditureExplanation.daysLogged(19) == "19 of 21 days")
    }

    @Test func fullUncappedDataNeedsNoNotes() {
        #expect(ExpenditureExplanation.notes(Self.proposal()).isEmpty)
    }

    @Test func eachCaveatGetsANote() {
        let notes = ExpenditureExplanation.notes(Self.proposal(
            raw: 3600,
            excluded: 2,
            wasCapped: true,
            reason: .partialData(completeness: 0.5),
            isFloored: true
        ))
        #expect(notes.count == 4)
        #expect(notes[0].contains("50%"))
        #expect(notes[1].contains("3600 kcal"))
        #expect(notes[1].contains("150 kcal"))
        #expect(notes[2].hasPrefix("2 days with very little logged were"))
        #expect(notes[3].contains("1800 kcal"))
    }

    @Test func aSingleExcludedDayIsSingular() {
        let notes = ExpenditureExplanation.notes(Self.proposal(excluded: 1))
        #expect(notes == ["1 day with very little logged was left out as likely incomplete."])
    }

    @Test func moreDataNamesWhatIsMissing() {
        #expect(ExpenditureExplanation.moreDataNeeded(intakeDays: 6, neededIntakeDays: 10, weighIns: 3, neededWeighIns: 8)
            == "Log food on 4 more days and weigh in 5 more times within the last 21 days to get your first estimate.")
        #expect(ExpenditureExplanation.moreDataNeeded(intakeDays: 9, neededIntakeDays: 10, weighIns: 8, neededWeighIns: 8)
            == "Log food on 1 more day within the last 21 days to get your first estimate.")
        #expect(ExpenditureExplanation.moreDataNeeded(intakeDays: 12, neededIntakeDays: 10, weighIns: 7, neededWeighIns: 8)
            == "Weigh in 1 more time within the last 21 days to get your first estimate.")
    }
}
