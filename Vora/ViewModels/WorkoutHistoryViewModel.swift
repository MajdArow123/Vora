//
//  WorkoutHistoryViewModel.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import Foundation
import Observation
import OSLog
import SwiftData

enum HistoryItem: Identifiable {
    case lifting(WorkoutSession)
    case cardio(CardioEntry)

    var id: UUID {
        switch self {
        case .lifting(let session): session.id
        case .cardio(let entry): entry.id
        }
    }

    var date: Date {
        switch self {
        case .lifting(let session): session.date
        case .cardio(let entry): entry.date
        }
    }
}

/// The text for a delete confirmation, built up front so an alert never
/// reads the model while it is being deleted.
struct HistoryDeletionPrompt {
    let item: HistoryItem
    let title: String
    let message: String

    init(item: HistoryItem) {
        self.item = item
        let name: String
        let affected: String
        switch item {
        case .lifting(let session):
            title = "Delete Workout?"
            name = session.sessionName
            affected = "your PRs and charts"
        case .cardio(let entry):
            title = "Delete Cardio?"
            name = entry.type.displayName
            affected = "your charts"
        }
        let day = item.date.formatted(.dateTime.weekday(.abbreviated).day().month())
        message = "\(name) on \(day) will also come out of \(affected), and Vora will try to remove it from Apple Health. This can't be undone."
    }
}

@Observable
final class WorkoutHistoryViewModel {
    private static let logger = Logger(subsystem: "com.majdarow.Vora", category: "Workout")

    private(set) var items: [HistoryItem] = []

    private let deletionService: WorkoutDeletionService

    init(deletionService: WorkoutDeletionService = WorkoutDeletionService()) {
        self.deletionService = deletionService
    }

    func load(from context: ModelContext) {
        items = (fetchSessions(from: context).map(HistoryItem.lifting)
            + fetchCardio(from: context).map(HistoryItem.cardio))
            .sorted { $0.date > $1.date }
    }

    /// Drops the row before deleting so nothing reads the deleted model,
    /// and restores it if the delete fails. HealthKit cleanup runs
    /// afterwards in the returned task; only tests need to wait for it.
    @discardableResult
    func delete(
        _ item: HistoryItem,
        context: ModelContext,
        save: (ModelContext) throws -> Void = { try $0.save() }
    ) throws -> Task<Void, Never> {
        let previousItems = items
        items.removeAll { $0.id == item.id }

        let match: HealthWorkoutMatch?
        do {
            switch item {
            case .lifting(let session):
                match = try deletionService.delete(session, context: context, save: save)
            case .cardio(let entry):
                match = try deletionService.delete(entry, context: context, save: save)
            }
        } catch {
            items = previousItems
            Self.logger.error("Failed to delete workout: \(String(describing: error), privacy: .public)")
            throw error
        }

        let service = deletionService
        return Task {
            await service.removeFromHealth(match)
        }
    }

    private func fetchSessions(from context: ModelContext) -> [WorkoutSession] {
        do {
            return try context.fetch(FetchDescriptor<WorkoutSession>(
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            ))
        } catch {
            Self.logger.error("Failed to fetch sessions for history: \(String(describing: error), privacy: .public)")
            return []
        }
    }

    private func fetchCardio(from context: ModelContext) -> [CardioEntry] {
        do {
            return try context.fetch(FetchDescriptor<CardioEntry>(
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            ))
        } catch {
            Self.logger.error("Failed to fetch cardio for history: \(String(describing: error), privacy: .public)")
            return []
        }
    }
}
