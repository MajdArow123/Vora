//
//  WorkoutHistoryViewModel.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import Foundation
import Observation
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

@Observable
final class WorkoutHistoryViewModel {
    private(set) var items: [HistoryItem] = []

    func load(from context: ModelContext) {
        let sessions = (try? context.fetch(FetchDescriptor<WorkoutSession>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        ))) ?? []
        let cardio = (try? context.fetch(FetchDescriptor<CardioEntry>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        ))) ?? []

        items = (sessions.map(HistoryItem.lifting) + cardio.map(HistoryItem.cardio))
            .sorted { $0.date > $1.date }
    }
}
