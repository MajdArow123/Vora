//
//  GymInventoryBackfill.swift
//  Vora
//
//  Created by Majd Arow on 2026-11-02.
//

import Foundation
import SwiftData

/// Writes preset defaults into gyms with no stored inventory, using the
/// user's units. Runs after the store opens and again when onboarding
/// completes; idempotent, so running it on every launch is cheap once done.
enum GymInventoryBackfill {
    /// Returns how many gyms were filled. Before onboarding there is no user
    /// profile and so no units: gyms stay unfilled and nothing counts.
    @discardableResult
    static func run(in context: ModelContext) throws -> Int {
        var profileDescriptor = FetchDescriptor<UserProfile>()
        profileDescriptor.fetchLimit = 1
        guard let units = try context.fetch(profileDescriptor).first?.preferredUnits else { return 0 }

        var filled = 0
        for gym in try context.fetch(FetchDescriptor<GymProfile>()) where gym.fillInventoryIfNeeded(units: units) {
            filled += 1
        }
        if filled > 0 {
            try context.save()
        }
        return filled
    }
}
