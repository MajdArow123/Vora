//
//  SupplementStatsTests.swift
//  VoraTests
//
//  Created by Majd Arow on 2026-07-26.
//

import Foundation
import Testing
@testable import Vora

struct SupplementStatsTests {
    private let cal = Calendar.current

    /// Wednesday 2026-07-22, noon.
    private var now: Date {
        cal.date(from: DateComponents(year: 2026, month: 7, day: 22, hour: 12))!
    }

    private func day(_ offset: Int) -> Date {
        cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: now))!
    }

    // MARK: - Qualifying days

    @Test func dayQualifiesOnlyWhenAllSupplementsTaken() {
        let creatine = UUID()
        let vitaminD = UUID()
        let supplements = [(id: creatine, createdAt: day(-10)), (id: vitaminD, createdAt: day(-10))]

        let qualifying = StreakCalculator.qualifyingSupplementDays(
            logs: [
                (supplementID: creatine, date: day(-1)),
                (supplementID: vitaminD, date: day(-1)),
                (supplementID: creatine, date: day(-2)), // partial day
            ],
            activeSupplements: supplements,
            calendar: cal
        )

        #expect(qualifying == [day(-1)])
    }

    @Test func supplementAddedLaterDoesNotBreakEarlierDays() {
        let creatine = UUID()
        let magnesium = UUID()
        // Magnesium only exists from yesterday.
        let supplements = [(id: creatine, createdAt: day(-10)), (id: magnesium, createdAt: day(-1))]

        let qualifying = StreakCalculator.qualifyingSupplementDays(
            logs: [
                (supplementID: creatine, date: day(-3)),
                (supplementID: creatine, date: day(-1)),
                (supplementID: magnesium, date: day(-1)),
            ],
            activeSupplements: supplements,
            calendar: cal
        )

        // Day -3 predates magnesium, so creatine alone qualifies it.
        #expect(qualifying.contains(day(-3)))
        #expect(qualifying.contains(day(-1)))
    }

    @Test func missingNewSupplementDisqualifiesRecentDay() {
        let creatine = UUID()
        let magnesium = UUID()
        let supplements = [(id: creatine, createdAt: day(-10)), (id: magnesium, createdAt: day(-1))]

        let qualifying = StreakCalculator.qualifyingSupplementDays(
            logs: [(supplementID: creatine, date: day(-1))],
            activeSupplements: supplements,
            calendar: cal
        )

        #expect(!qualifying.contains(day(-1)))
    }

    @Test func noActiveSupplementsMeansNoQualifyingDays() {
        let qualifying = StreakCalculator.qualifyingSupplementDays(
            logs: [(supplementID: UUID(), date: day(-1))],
            activeSupplements: [],
            calendar: cal
        )
        #expect(qualifying.isEmpty)
    }

    // MARK: - Streak via foodStreak semantics

    @Test func streakCountsBackFromTodayWithGraceDay() {
        let qualifying: Set<Date> = [day(-1), day(-2), day(-3)]
        // Today not yet qualified — grace day keeps the streak at 3.
        #expect(StreakCalculator.foodStreak(qualifyingDays: qualifying, today: now, calendar: cal) == 3)
        // Today qualified extends it to 4.
        let withToday = qualifying.union([day(0)])
        #expect(StreakCalculator.foodStreak(qualifyingDays: withToday, today: now, calendar: cal) == 4)
    }

    @Test func gapBreaksStreak() {
        let qualifying: Set<Date> = [day(0), day(-2), day(-3)]
        #expect(StreakCalculator.foodStreak(qualifyingDays: qualifying, today: now, calendar: cal) == 1)
    }

    // MARK: - Monthly consistency

    @Test func fullMonthConsistency() {
        // July 22nd: 22 window days, all qualified.
        let monthStart = cal.date(from: DateComponents(year: 2026, month: 7, day: 1))!
        let qualifying = Set((0...21).map {
            cal.date(byAdding: .day, value: $0, to: monthStart)!
        })
        let percent = StreakCalculator.monthlyConsistency(
            qualifyingDays: qualifying,
            earliestCreatedAt: cal.date(from: DateComponents(year: 2026, month: 6, day: 1))!,
            today: now,
            calendar: cal
        )
        #expect(percent == 100)
    }

    @Test func midMonthCreationShrinksWindow() {
        // First supplement added 2 days ago; both days since qualified.
        let percent = StreakCalculator.monthlyConsistency(
            qualifyingDays: [day(-2), day(-1), day(0)],
            earliestCreatedAt: day(-2),
            today: now,
            calendar: cal
        )
        #expect(percent == 100)

        // One of the three window days missed → 67%.
        let partial = StreakCalculator.monthlyConsistency(
            qualifyingDays: [day(-2), day(0)],
            earliestCreatedAt: day(-2),
            today: now,
            calendar: cal
        )
        #expect(partial == 67)
    }

    @Test func nilCreationDateGivesZero() {
        let percent = StreakCalculator.monthlyConsistency(
            qualifyingDays: [day(0)],
            earliestCreatedAt: nil,
            today: now,
            calendar: cal
        )
        #expect(percent == 0)
    }

    @Test func qualifyingDaysOutsideWindowAreIgnored() {
        // Qualified days last month don't inflate this month's number.
        let lastMonth = cal.date(from: DateComponents(year: 2026, month: 6, day: 15))!
        let percent = StreakCalculator.monthlyConsistency(
            qualifyingDays: [lastMonth, day(0)],
            earliestCreatedAt: day(-1),
            today: now,
            calendar: cal
        )
        #expect(percent == 50)
    }
}
