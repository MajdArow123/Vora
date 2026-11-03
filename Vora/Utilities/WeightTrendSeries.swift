//
//  WeightTrendSeries.swift
//  Vora
//
//  Created by Majd Arow on 2026-11-02.
//

import Foundation

/// `WeightTrendCalculator`'s result placed back on the calendar. Home and
/// Progress both build it from every weigh-in, so they show the same trend
/// and a chart range only changes what's drawn.
struct WeightTrendSeries: Equatable {
    struct Point: Identifiable, Equatable {
        let date: Date
        let trendKg: Double
        let scaleKg: Double?

        var id: Date { date }
    }

    let result: WeightTrendCalculator.Result
    /// One point per day, oldest first, each dated at the start of its day.
    let points: [Point]

    var currentKg: Double { result.currentKg }

    /// The day of the most recent weigh-in.
    var lastDay: Date? { points.last?.date }

    /// nil without entries. Offsets count calendar days, so a daylight
    /// saving change can't shift a weigh-in to another day.
    init?(entries: [WeightEntry], calendar: Calendar) {
        guard let earliest = entries.map(\.date).min() else { return nil }
        let firstDay = calendar.startOfDay(for: earliest)

        let readings = entries.compactMap { entry -> WeightTrendCalculator.Reading? in
            let day = calendar.startOfDay(for: entry.date)
            guard let offset = calendar.dateComponents([.day], from: firstDay, to: day).day else { return nil }
            return WeightTrendCalculator.Reading(dayOffset: offset, weightKg: entry.weightKg)
        }
        guard let result = WeightTrendCalculator.calculate(readings: readings) else { return nil }

        self.result = result
        self.points = result.days.compactMap { day in
            guard let date = calendar.date(byAdding: .day, value: day.dayOffset, to: firstDay) else { return nil }
            return Point(date: date, trendKg: day.trendKg, scaleKg: day.scaleKg)
        }
    }

    func points(onOrAfter cutoff: Date) -> [Point] {
        points.filter { $0.date >= cutoff }
    }
}
