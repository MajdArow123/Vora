//
//  WeightTrendCalculatorTests.swift
//  VoraTests
//
//  Created by Majd Arow on 2026-11-02.
//

import Foundation
import Testing
@testable import Vora

struct WeightTrendCalculatorTests {
    private typealias Reading = WeightTrendCalculator.Reading

    private func daily(_ weights: [Double]) -> [Reading] {
        weights.enumerated().map { Reading(dayOffset: $0.offset, weightKg: $0.element) }
    }

    private func isClose(_ value: Double?, to expected: Double, within tolerance: Double = 0.000001) -> Bool {
        guard let value else { return false }
        return abs(value - expected) <= tolerance
    }

    @Test func noReadingsHaveNoTrend() {
        #expect(WeightTrendCalculator.calculate(readings: []) == nil)
    }

    @Test func singleEntryIsItsOwnTrend() throws {
        let result = try #require(WeightTrendCalculator.calculate(readings: [Reading(dayOffset: 4, weightKg: 80.5)]))
        #expect(result.currentKg == 80.5)
        #expect(result.loggedDayCount == 1)
        #expect(result.days == [.init(dayOffset: 4, trendKg: 80.5, scaleKg: 80.5)])
        #expect(result.change7Kg == nil)
        #expect(result.ratePerDay(window: 14) == nil)
    }

    @Test func eachDayMovesTheTrendByTheSmoothingFactor() throws {
        let result = try #require(WeightTrendCalculator.calculate(readings: daily([80, 81])))
        #expect(isClose(result.currentKg, to: 80.1))
    }

    @Test func sameDayWeighInsAreAveragedFirst() throws {
        let result = try #require(WeightTrendCalculator.calculate(readings: [
            Reading(dayOffset: 0, weightKg: 80),
            Reading(dayOffset: 1, weightKg: 80),
            Reading(dayOffset: 1, weightKg: 82),
        ]))
        #expect(result.loggedDayCount == 2)
        #expect(result.days[1].scaleKg == 81)
        #expect(isClose(result.currentKg, to: 80.1))
    }

    @Test func gapDecaysOverTheElapsedDays() throws {
        let result = try #require(WeightTrendCalculator.calculate(readings: [
            Reading(dayOffset: 0, weightKg: 80),
            Reading(dayOffset: 10, weightKg: 90),
        ]))
        // 1 − 0.9¹⁰ of the 10 kg gap closes, not the 0.1 of a single day.
        #expect(isClose(result.currentKg, to: 80 + (1 - pow(0.9, 10)) * 10))
    }

    @Test func gapDaysAreFilledWithoutScaleValues() throws {
        let result = try #require(WeightTrendCalculator.calculate(readings: [
            Reading(dayOffset: 0, weightKg: 80),
            Reading(dayOffset: 3, weightKg: 90),
        ]))
        #expect(result.days.map(\.dayOffset) == [0, 1, 2, 3])
        #expect(result.days.map(\.scaleKg) == [80, nil, nil, 90])
        #expect(result.loggedDayCount == 2)
        // Rises steadily rather than holding flat and jumping on the last day.
        #expect(isClose(result.days[1].trendKg, to: 81))
        #expect(isClose(result.days[2].trendKg, to: 81.9))
        #expect(isClose(result.days[3].trendKg, to: 82.71))
    }

    @Test func aGapMatchesRepeatingTheNextReadingDaily() throws {
        let gapped = try #require(WeightTrendCalculator.calculate(readings: [
            Reading(dayOffset: 0, weightKg: 80),
            Reading(dayOffset: 5, weightKg: 85),
        ]))
        let repeated = try #require(WeightTrendCalculator.calculate(readings: daily([80, 85, 85, 85, 85, 85])))
        #expect(isClose(gapped.currentKg, to: repeated.currentKg))
    }

    @Test func outlierIsDamped() throws {
        var weights = Array(repeating: 80.0, count: 30)
        weights.append(83)
        let result = try #require(WeightTrendCalculator.calculate(readings: daily(weights)))
        #expect(isClose(result.currentKg, to: 80.3))

        weights.append(contentsOf: Array(repeating: 80.0, count: 14))
        let later = try #require(WeightTrendCalculator.calculate(readings: self.daily(weights)))
        #expect(isClose(later.currentKg, to: 80 + 0.3 * pow(0.9, 14)))
    }

    @Test func readingsCanComeInAnyOrder() throws {
        let ordered = daily([80, 81, 79, 82])
        #expect(
            WeightTrendCalculator.calculate(readings: ordered.reversed())
                == WeightTrendCalculator.calculate(readings: ordered)
        )
    }

    @Test func changesNeedHistorySpanningTheirWindow() throws {
        let sixDays = try #require(WeightTrendCalculator.calculate(readings: daily(Array(repeating: 80, count: 7))))
        #expect(sixDays.change7Kg == nil)
        #expect(sixDays.change30Kg == nil)

        let sevenDays = try #require(WeightTrendCalculator.calculate(readings: daily(Array(repeating: 80, count: 8))))
        #expect(sevenDays.change7Kg == 0)
        #expect(sevenDays.change30Kg == nil)

        let thirtyDays = try #require(WeightTrendCalculator.calculate(readings: daily(Array(repeating: 80, count: 31))))
        #expect(thirtyDays.change30Kg == 0)
    }

    @Test func changesAreDifferencesInTheTrend() throws {
        let weights = (0..<40).map { 90 - 0.1 * Double($0) }
        let result = try #require(WeightTrendCalculator.calculate(readings: daily(weights)))
        #expect(isClose(result.change7Kg, to: result.currentKg - result.days[32].trendKg))
        #expect(isClose(result.change30Kg, to: result.currentKg - result.days[9].trendKg))
        #expect(try #require(result.change7Kg) < 0)
    }

    @Test func rateConvergesOnASteadyChange() throws {
        let weights = (0..<90).map { 90 - 0.1 * Double($0) }
        let result = try #require(WeightTrendCalculator.calculate(readings: daily(weights)))
        #expect(isClose(result.ratePerDay(window: 14), to: -0.1, within: 0.001))
    }

    @Test func rateUsesAllOfAShorterHistory() throws {
        let result = try #require(WeightTrendCalculator.calculate(readings: daily([80, 81, 82])))
        let expected = (result.currentKg - 80) / 2
        #expect(isClose(result.ratePerDay(window: 14), to: expected))
    }

    @Test func loggedDaysCountsOnlyDaysWithWeighIns() throws {
        let result = try #require(WeightTrendCalculator.calculate(readings: [
            Reading(dayOffset: 0, weightKg: 80),
            Reading(dayOffset: 20, weightKg: 80),
            Reading(dayOffset: 22, weightKg: 80),
        ]))
        #expect(result.loggedDays(inLast: 15) == 2)
        #expect(result.loggedDays(inLast: 23) == 3)
    }

    // MARK: - Calendar series

    @Test func seriesMatchesAcrossAChartRangeBecauseItUsesAllHistory() throws {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let entries = try (0..<60).map { index in
            WeightEntry(
                date: try #require(cal.date(byAdding: .day, value: index - 59, to: today)),
                weightKg: 85 - 0.05 * Double(index)
            )
        }
        let series = try #require(WeightTrendSeries(entries: entries, calendar: cal))
        let cutoff = try #require(cal.date(byAdding: .day, value: -29, to: today))

        #expect(series.points(onOrAfter: cutoff).count == 30)
        #expect(series.points.count == 60)
        #expect(series.lastDay == today)
        #expect(series.points.last?.trendKg == series.currentKg)
    }

    @Test func seriesCountsCalendarDaysAcrossDaylightSaving() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        // US clocks went back on 2026-11-01, so that day has 25 hours.
        let before = try #require(cal.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 23)))
        let after = try #require(cal.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 1)))
        let series = try #require(WeightTrendSeries(
            entries: [WeightEntry(date: before, weightKg: 80), WeightEntry(date: after, weightKg: 81)],
            calendar: cal
        ))
        #expect(series.points.count == 3)
        #expect(series.points.map(\.scaleKg) == [80, nil, 81])
    }

    @Test func sameDayEntriesBecomeOneDot() throws {
        let cal = Calendar.current
        let day = cal.startOfDay(for: .now)
        let series = try #require(WeightTrendSeries(
            entries: [
                WeightEntry(date: day.addingTimeInterval(3600), weightKg: 80),
                WeightEntry(date: day.addingTimeInterval(7200), weightKg: 81),
            ],
            calendar: cal
        ))
        #expect(series.points.count == 1)
        #expect(series.currentKg == 80.5)
    }
}
