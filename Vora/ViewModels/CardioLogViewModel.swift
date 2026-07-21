//
//  CardioLogViewModel.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import Foundation
import Observation
import SwiftData

@Observable
final class CardioLogViewModel {
    var type: CardioType = .run
    var durationMinutes = 30
    private var bodyWeightKg: Double = 75

    private let healthKitService = HealthKitService()

    func load(from context: ModelContext) {
        var descriptor = FetchDescriptor<WeightEntry>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        if let latest = try? context.fetch(descriptor).first {
            bodyWeightKg = latest.weightKg
        }
    }

    /// kcal = MET × body weight (kg) × duration (hours).
    var estimatedCalories: Double {
        type.met * bodyWeightKg * Double(durationMinutes) / 60
    }

    func save(in context: ModelContext) {
        let end = Date.now
        let seconds = durationMinutes * 60
        let start = end.addingTimeInterval(-Double(seconds))
        let calories = estimatedCalories

        context.insert(CardioEntry(
            date: end,
            type: type,
            durationSeconds: seconds,
            estimatedCalories: calories
        ))
        do {
            try context.save()
        } catch {
            assertionFailure("Failed to save cardio entry: \(error)")
        }

        let service = healthKitService
        let cardioType = type
        Task {
            await service.saveCardioWorkout(type: cardioType, start: start, end: end, calories: calories)
        }
    }
}
