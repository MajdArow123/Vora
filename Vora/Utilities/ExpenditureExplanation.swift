//
//  ExpenditureExplanation.swift
//  Vora
//
//  Created by Majd Arow on 2026-11-02.
//

import Foundation

/// Plain-English text for the weekly check-in, in the user's units. Pure.
enum ExpenditureExplanation {
    static func kcal(_ value: Double) -> String {
        "\(Int(value.rounded())) kcal"
    }

    /// e.g. "-0.5 kg/week" or "+1.1 lb/week".
    static func weeklyRate(slopeKgPerDay: Double, units: UnitSystem) -> String {
        "\(UnitConversion.bodyWeightChangeText(kg: slopeKgPerDay * 7, units: units))/week"
    }

    /// e.g. "19 of 21 days".
    static func daysLogged(_ daysUsed: Int) -> String {
        "\(daysUsed) of \(ExpenditureEstimator.defaultWindowDays) days"
    }

    /// Says what the estimate did, and why in one number.
    static func summary(_ proposal: ExpenditureProposal, units: UnitSystem) -> String {
        let result = proposal.result
        guard let intake = result.averageIntake, let slope = result.slopeKgPerDay else { return "" }
        let rate = weeklyRate(slopeKgPerDay: slope, units: units)
        let change = Int(result.estimate.rounded()) - Int(proposal.previousEstimate.rounded())
        let lead = switch change {
        case 0: "Your expenditure estimate is holding steady."
        case ..<0: "Your expenditure estimate went down by \(-change) kcal."
        default: "Your expenditure estimate went up by \(change) kcal."
        }
        return "\(lead) You averaged \(kcal(intake)) a day while your weight changed \(rate)."
    }

    /// Anything the user should know about how far to trust the numbers, in
    /// the order they'd ask about them.
    static func notes(_ proposal: ExpenditureProposal) -> [String] {
        let result = proposal.result
        var notes: [String] = []

        if case .partialData(let completeness) = result.reason {
            notes.append("With \(Int((completeness * 100).rounded()))% of the data for a full estimate, this moved only part of the way toward what your data shows. Log more days to tighten it.")
        }
        if result.wasCapped, let raw = result.rawEstimate {
            notes.append("Your data points to \(kcal(raw)), but one update moves at most \(kcal(ExpenditureEstimator.maximumWeeklyChangeKcal)), so one odd week can't swing your targets.")
        }
        if result.excludedIncompleteDays > 0 {
            notes.append("\(dayCount(result.excludedIncompleteDays)) with very little logged \(result.excludedIncompleteDays == 1 ? "was" : "were") left out as likely incomplete.")
        }
        if proposal.proposedTargets.isFloored {
            notes.append("Calories are held at \(proposal.proposedTargets.calories) kcal, because Vora won't suggest less than \(kcal(proposal.floorCalories)) a day for you.")
        }
        return notes
    }

    /// Says how much more logging an estimate needs.
    static func moreDataNeeded(intakeDays: Int, neededIntakeDays: Int, weighIns: Int, neededWeighIns: Int) -> String {
        let moreDays = max(neededIntakeDays - intakeDays, 0)
        let moreWeighIns = max(neededWeighIns - weighIns, 0)
        let needed = switch (moreDays > 0, moreWeighIns > 0) {
        case (true, true): "Log food on \(dayCount(moreDays, more: true)) and weigh in \(timeCount(moreWeighIns))"
        case (true, false): "Log food on \(dayCount(moreDays, more: true))"
        default: "Weigh in \(timeCount(moreWeighIns))"
        }
        return "\(needed) within the last \(ExpenditureEstimator.defaultWindowDays) days to get your first estimate."
    }

    private static func dayCount(_ count: Int, more: Bool = false) -> String {
        "\(count) \(more ? "more " : "")\(count == 1 ? "day" : "days")"
    }

    private static func timeCount(_ count: Int) -> String {
        "\(count) more \(count == 1 ? "time" : "times")"
    }
}
