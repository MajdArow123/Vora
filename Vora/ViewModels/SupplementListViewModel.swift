//
//  SupplementListViewModel.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-26.
//

import Foundation
import Observation
import SwiftData
// SwiftUI provides move(fromOffsets:toOffset:) for List reordering.
import SwiftUI

@Observable
final class SupplementListViewModel {
    /// Active supplements in the user's order.
    private(set) var supplements: [Supplement] = []

    func load(from context: ModelContext) {
        let descriptor = FetchDescriptor<Supplement>(
            predicate: #Predicate { $0.isActive },
            sortBy: [SortDescriptor(\.orderIndex)]
        )
        supplements = (try? context.fetch(descriptor)) ?? []
    }

    func move(from source: IndexSet, to destination: Int, context: ModelContext) {
        var reordered = supplements
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, supplement) in reordered.enumerated() {
            supplement.orderIndex = index
        }
        try? context.save()
        load(from: context)
    }

    /// Soft delete: history stays, reminders are cancelled on the next
    /// notification refresh.
    func deactivate(_ supplement: Supplement, context: ModelContext) {
        supplement.isActive = false
        try? context.save()
        load(from: context)
        NotificationService.shared.refreshAll(context: context)
    }
}
