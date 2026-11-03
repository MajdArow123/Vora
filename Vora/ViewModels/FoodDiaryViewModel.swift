//
//  FoodDiaryViewModel.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import Foundation
import Observation
import OSLog
import SwiftData

@Observable
final class FoodDiaryViewModel {
    static let glassMl: Double = 250
    private static let logger = Logger(subsystem: "com.majdarow.Vora", category: "FoodDiary")

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private(set) var selectedDate = Calendar.current.startOfDay(for: .now)
    private(set) var entries: [FoodEntry] = []
    private(set) var waterEntries: [WaterEntry] = []
    private(set) var profile: UserProfile?
    /// The selected day's targets, which calorie cycling can change.
    private(set) var dayTargets: DayTargets?

    /// Non-nil while the add-food sheet is presented for a slot.
    var addingToSlot: MealSlot?

    // MARK: - Loading

    func load(from context: ModelContext) {
        do {
            profile = try context.fetch(FetchDescriptor<UserProfile>()).first
        } catch {
            Self.logger.error("Failed to load the profile: \(String(describing: error), privacy: .public)")
            profile = nil
        }
        dayTargets = profile.map {
            CalorieCyclingService.targets(on: selectedDate, profile: $0, context: context, defaults: defaults)
        }

        let start = selectedDate
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start

        let foodDescriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate { $0.date >= start && $0.date < end },
            sortBy: [SortDescriptor(\.date)]
        )
        do {
            entries = try context.fetch(foodDescriptor)
        } catch {
            Self.logger.error("Failed to load food entries: \(String(describing: error), privacy: .public)")
            entries = []
        }

        let waterDescriptor = FetchDescriptor<WaterEntry>(
            predicate: #Predicate { $0.date >= start && $0.date < end },
            sortBy: [SortDescriptor(\.date)]
        )
        do {
            waterEntries = try context.fetch(waterDescriptor)
        } catch {
            Self.logger.error("Failed to load water entries: \(String(describing: error), privacy: .public)")
            waterEntries = []
        }
    }

    // MARK: - Date navigation

    func goToPreviousDay(context: ModelContext) {
        shiftDay(by: -1, context: context)
    }

    func goToNextDay(context: ModelContext) {
        shiftDay(by: 1, context: context)
    }

    private func shiftDay(by days: Int, context: ModelContext) {
        selectedDate = Calendar.current.date(byAdding: .day, value: days, to: selectedDate) ?? selectedDate
        load(from: context)
    }

    var dateTitle: String {
        let cal = Calendar.current
        if cal.isDateInToday(selectedDate) { return "Today" }
        if cal.isDateInYesterday(selectedDate) { return "Yesterday" }
        if cal.isDateInTomorrow(selectedDate) { return "Tomorrow" }
        return selectedDate.formatted(.dateTime.weekday(.wide))
    }

    var dateSubtitle: String {
        selectedDate.formatted(.dateTime.day().month(.wide))
    }

    /// Timestamp for a new entry on the selected day: now for today,
    /// midday for other days.
    var logTimestamp: Date {
        if Calendar.current.isDateInToday(selectedDate) { return .now }
        return selectedDate.addingTimeInterval(12 * 3600)
    }

    // MARK: - Totals

    func entries(for slot: MealSlot) -> [FoodEntry] {
        entries.filter { $0.mealSlot == slot }
    }

    var totalCalories: Double { entries.reduce(0) { $0 + $1.calories } }
    var totalProtein: Double { entries.reduce(0) { $0 + $1.proteinG } }
    var totalCarbs: Double { entries.reduce(0) { $0 + $1.carbsG } }
    var totalFat: Double { entries.reduce(0) { $0 + $1.fatG } }
    var totalFibre: Double { entries.reduce(0) { $0 + $1.fibreG } }
    var totalSugar: Double { entries.reduce(0) { $0 + $1.sugarG } }
    var totalSodiumMg: Double { entries.reduce(0) { $0 + $1.sodiumMg } }

    var calorieTarget: Int { dayTargets?.targets.calories ?? 0 }
    var proteinTarget: Int { dayTargets?.targets.proteinG ?? 0 }
    var carbsTarget: Int { dayTargets?.targets.carbsG ?? 0 }
    var fatTarget: Int { dayTargets?.targets.fatG ?? 0 }

    var remainingCalories: Int { calorieTarget - Int(totalCalories.rounded()) }

    var remainingMacros: RemainingMacros {
        RemainingMacros(
            calories: remainingCalories,
            proteinG: proteinTarget - Int(totalProtein.rounded()),
            carbsG: carbsTarget - Int(totalCarbs.rounded()),
            fatG: fatTarget - Int(totalFat.rounded())
        )
    }

    // MARK: - Water

    var waterTotalMl: Double { waterEntries.reduce(0) { $0 + $1.amountMl } }
    var waterTargetMl: Double { profile?.waterTargetMl ?? 3500 }
    var glassCount: Int { Int((waterTotalMl / Self.glassMl).rounded(.down)) }

    func addGlass(context: ModelContext) {
        context.insert(WaterEntry(date: logTimestamp, amountMl: Self.glassMl))
        save(context)
        load(from: context)
    }

    func removeGlass(context: ModelContext) {
        guard let latest = waterEntries.last else { return }
        context.delete(latest)
        save(context)
        load(from: context)
    }

    // MARK: - Entry mutations

    func delete(_ entry: FoodEntry, context: ModelContext) {
        context.delete(entry)
        save(context)
        load(from: context)
    }

    /// Duplicates every entry from the previous day into the selected day,
    /// preserving each entry's time of day.
    func copyPreviousDay(context: ModelContext) {
        let cal = Calendar.current
        guard let prevStart = cal.date(byAdding: .day, value: -1, to: selectedDate) else { return }
        let prevEnd = selectedDate

        let descriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate { $0.date >= prevStart && $0.date < prevEnd }
        )
        guard let previous = try? context.fetch(descriptor), !previous.isEmpty else { return }

        for entry in previous {
            let offset = entry.date.timeIntervalSince(prevStart)
            context.insert(FoodEntry(
                date: selectedDate.addingTimeInterval(offset),
                mealSlot: entry.mealSlot,
                foodName: entry.foodName,
                servingGrams: entry.servingGrams,
                calories: entry.calories,
                proteinG: entry.proteinG,
                carbsG: entry.carbsG,
                fatG: entry.fatG,
                fibreG: entry.fibreG,
                sugarG: entry.sugarG,
                sodiumMg: entry.sodiumMg
            ))
        }
        save(context)
        load(from: context)
    }

    private func save(_ context: ModelContext) {
        do {
            try context.save()
        } catch {
            assertionFailure("Failed to save diary change: \(error)")
        }
    }
}
