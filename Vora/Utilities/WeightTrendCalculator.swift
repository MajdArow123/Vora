//
//  WeightTrendCalculator.swift
//  Vora
//
//  Created by Majd Arow on 2026-11-02.
//

import Foundation

/// Smooths scale weight into a trend with an exponentially weighted moving
/// average. Pure: days are plain offsets and weights are kilograms, so it
/// knows nothing about dates, units or storage.
enum WeightTrendCalculator {
    /// Share of the gap between trend and scale that one day closes. At 0.1
    /// a one-off 3 kg spike moves the trend 0.3 kg, and about 90% of a lasting
    /// change has reached the trend after 22 days.
    static let smoothingFactor = 0.1

    struct Reading: Equatable {
        let dayOffset: Int
        let weightKg: Double
    }

    struct DayPoint: Equatable {
        let dayOffset: Int
        let trendKg: Double
        /// The day's average scale weight; nil on a day with no weigh-in.
        let scaleKg: Double?
    }

    struct Result: Equatable {
        /// One point per day, first reading to last, oldest first.
        let days: [DayPoint]
        let currentKg: Double
        let loggedDayCount: Int

        var change7Kg: Double? { change(overDays: 7) }
        var change30Kg: Double? { change(overDays: 30) }

        /// Trend change over exactly `days` days; nil until history spans them.
        func change(overDays days: Int) -> Double? {
            let index = self.days.count - 1 - days
            guard days > 0, self.days.indices.contains(index) else { return nil }
            return currentKg - self.days[index].trendKg
        }

        /// Trend change per day over the last `window` days, or over all of
        /// the history when it is shorter; nil for a single day.
        func ratePerDay(window: Int) -> Double? {
            let span = min(window, days.count - 1)
            guard span > 0, let change = change(overDays: span) else { return nil }
            return change / Double(span)
        }

        /// Days with a weigh-in among the last `window` days.
        func loggedDays(inLast window: Int) -> Int {
            days.suffix(window).filter { $0.scaleKg != nil }.count
        }
    }

    /// nil without readings. Readings can come in any order.
    static func calculate(readings: [Reading]) -> Result? {
        let byDay = Dictionary(grouping: readings, by: \.dayOffset)
            .mapValues { sameDay in
                sameDay.map(\.weightKg).reduce(0, +) / Double(sameDay.count)
            }
            .sorted { $0.key < $1.key }
        guard let first = byDay.first else { return nil }

        var trend = first.value
        var days = [DayPoint(dayOffset: first.key, trendKg: trend, scaleKg: first.value)]

        for (dayOffset, scaleKg) in byDay.dropFirst() {
            let previous = days[days.count - 1].dayOffset
            let start = trend
            for elapsed in 1...(dayOffset - previous) {
                // After n days a reading has closed 1 − (1 − α)ⁿ of the gap,
                // so a gap decays toward the next reading day by day.
                let weight = 1 - pow(1 - smoothingFactor, Double(elapsed))
                trend = start + weight * (scaleKg - start)
                let day = previous + elapsed
                days.append(DayPoint(
                    dayOffset: day,
                    trendKg: trend,
                    scaleKg: day == dayOffset ? scaleKg : nil
                ))
            }
        }

        return Result(days: days, currentKg: trend, loggedDayCount: byDay.count)
    }
}
