//
//  ExpenditureEstimator.swift
//  Vora
//
//  Created by Majd Arow on 2026-11-02.
//

import Foundation

/// Estimates daily energy expenditure from intake and the rate of weight
/// change: what you eat, minus what you stored. Pure: days are plain offsets
/// and weights are kilograms, so it knows nothing about dates, units or storage.
enum ExpenditureEstimator {
    /// Long enough for water swings to average out of the slope, short enough
    /// to follow a real change in expenditure within a few weeks.
    static let defaultWindowDays = 21
    /// Energy in a kilogram of body weight change. An approximation: the real
    /// figure depends on the mix of fat, lean mass and water, and early water
    /// shifts carry almost no energy, which is why the estimate is smoothed.
    static let energyDensityKcalPerKg = 7700.0
    /// A day under this share of the current estimate is likely half-logged,
    /// so it says more about the log than about what was eaten.
    static let incompleteDayFraction = 0.4
    /// Below these, the estimate would mostly be noise.
    static let minimumIntakeDays = 10
    static let minimumWeighIns = 8
    /// A least-squares slope is reliable without daily weigh-ins, so weigh-ins
    /// stop limiting completeness at this many.
    static let fullCompletenessWeighIns = 14
    /// The most one weekly update can move the estimate, so one odd week
    /// can't swing targets.
    static let maximumWeeklyChangeKcal = 150.0

    struct IntakeDay: Equatable {
        let dayOffset: Int
        /// nil when nothing was logged that day.
        let kcal: Double?
    }

    struct WeightDay: Equatable {
        let dayOffset: Int
        let weightKg: Double
    }

    struct Input: Equatable {
        var intake: [IntakeDay]
        var weights: [WeightDay]
        /// Mifflin-St Jeor × activity: the starting point before any estimate.
        var formulaTDEE: Double
        var previousEstimate: Double?
        /// The newest day the window covers.
        var lastDayOffset: Int
        var windowDays = defaultWindowDays
    }

    enum Reason: Equatable {
        case notEnoughData(intakeDays: Int, neededIntakeDays: Int, weighIns: Int, neededWeighIns: Int)
        /// Moved only part of the way to the raw estimate.
        case partialData(completeness: Double)
        case fullData
    }

    struct Result: Equatable {
        /// The prior, unchanged, when there's not enough data.
        let estimate: Double
        /// What this window alone says; nil without enough data, as are
        /// `averageIntake` and `slopeKgPerDay`.
        let rawEstimate: Double?
        let averageIntake: Double?
        let slopeKgPerDay: Double?
        /// Intake days that counted.
        let daysUsed: Int
        let weighInsUsed: Int
        let excludedIncompleteDays: Int
        /// True when the weekly limit held the estimate back.
        let wasCapped: Bool
        let reason: Reason
    }

    /// How much of the gap to the raw estimate one update closes, from 0 to 1.
    static func completeness(intakeDaysUsed: Int, weighInsUsed: Int, windowDays: Int = defaultWindowDays) -> Double {
        guard windowDays > 0 else { return 0 }
        return min(
            min(1, Double(intakeDaysUsed) / Double(windowDays)),
            min(1, Double(weighInsUsed) / Double(fullCompletenessWeighIns))
        )
    }

    static func estimate(_ input: Input) -> Result {
        let current = input.previousEstimate ?? input.formulaTDEE
        let window = (input.lastDayOffset - input.windowDays + 1)...input.lastDayOffset

        let logged = input.intake.filter { window.contains($0.dayOffset) }.compactMap(\.kcal)
        let used = logged.filter { $0 >= current * incompleteDayFraction }

        let readings = Dictionary(grouping: input.weights.filter { window.contains($0.dayOffset) }, by: \.dayOffset)
            .map { day, sameDay in
                WeightDay(dayOffset: day, weightKg: sameDay.map(\.weightKg).reduce(0, +) / Double(sameDay.count))
            }

        guard used.count >= minimumIntakeDays,
              readings.count >= minimumWeighIns,
              let slope = leastSquaresSlope(readings)
        else {
            return Result(
                estimate: current,
                rawEstimate: nil,
                averageIntake: nil,
                slopeKgPerDay: nil,
                daysUsed: used.count,
                weighInsUsed: readings.count,
                excludedIncompleteDays: logged.count - used.count,
                wasCapped: false,
                reason: .notEnoughData(
                    intakeDays: used.count,
                    neededIntakeDays: minimumIntakeDays,
                    weighIns: readings.count,
                    neededWeighIns: minimumWeighIns
                )
            )
        }

        let averageIntake = used.reduce(0, +) / Double(used.count)
        let raw = averageIntake - slope * energyDensityKcalPerKg
        let share = completeness(intakeDaysUsed: used.count, weighInsUsed: readings.count, windowDays: input.windowDays)
        let change = share * (raw - current)
        let capped = max(-maximumWeeklyChangeKcal, min(maximumWeeklyChangeKcal, change))

        return Result(
            estimate: current + capped,
            rawEstimate: raw,
            averageIntake: averageIntake,
            slopeKgPerDay: slope,
            daysUsed: used.count,
            weighInsUsed: readings.count,
            excludedIncompleteDays: logged.count - used.count,
            wasCapped: capped != change,
            reason: share < 1 ? .partialData(completeness: share) : .fullData
        )
    }

    /// Kilograms per day, from the scale readings directly. The EWMA trend
    /// isn't used here: it lags a steady change by about 35% early on, and
    /// that lag would read as lower or higher expenditure.
    /// nil when the readings don't span at least two days.
    static func leastSquaresSlope(_ readings: [WeightDay]) -> Double? {
        guard !readings.isEmpty else { return nil }
        let count = Double(readings.count)
        let meanDay = readings.map { Double($0.dayOffset) }.reduce(0, +) / count
        let meanKg = readings.map(\.weightKg).reduce(0, +) / count
        let spread = readings.reduce(0) { $0 + pow(Double($1.dayOffset) - meanDay, 2) }
        guard spread > 0 else { return nil }
        let covariance = readings.reduce(0) { $0 + (Double($1.dayOffset) - meanDay) * ($1.weightKg - meanKg) }
        return covariance / spread
    }
}
