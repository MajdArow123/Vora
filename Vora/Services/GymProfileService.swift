//
//  GymProfileService.swift
//  Vora
//
//  Created by Majd Arow on 2026-08-10.
//

import Foundation
import SwiftData

/// Owns the gym-profile invariants: at least one profile always exists,
/// and exactly one is active. All mutations that could break those
/// invariants go through here.
enum GymProfileService {
    /// Seeds a full-equipment commercial profile on first launch (or for
    /// existing users updating into this feature) and repairs the
    /// exactly-one-active invariant if the store ever drifts.
    static func ensureDefaultProfile(context: ModelContext) {
        let profiles = fetchAll(context: context)

        guard !profiles.isEmpty else {
            let profile = GymProfile(name: "My Gym", preset: .commercial, isActive: true)
            context.insert(profile)
            save(context)
            return
        }

        let active = profiles.filter(\.isActive)
        if active.isEmpty {
            profiles[0].isActive = true
            save(context)
        } else if active.count > 1 {
            for profile in active.dropFirst() {
                profile.isActive = false
            }
            save(context)
        }
    }

    static func activeProfile(context: ModelContext) -> GymProfile? {
        fetchAll(context: context).first(where: \.isActive)
    }

    static func activate(_ profile: GymProfile, context: ModelContext) {
        for other in fetchAll(context: context) {
            other.isActive = (other.persistentModelID == profile.persistentModelID)
        }
        save(context)
    }

    /// Deletes a profile unless it is the last one. Deleting the active
    /// profile promotes the oldest remaining profile so exactly one stays
    /// active. Returns false when the delete was refused.
    @discardableResult
    static func delete(_ profile: GymProfile, context: ModelContext) -> Bool {
        let profiles = fetchAll(context: context)
        guard profiles.count > 1 else { return false }

        let wasActive = profile.isActive
        context.delete(profile)

        if wasActive {
            let remaining = profiles.filter {
                $0.persistentModelID != profile.persistentModelID
            }
            remaining.first?.isActive = true
        }
        save(context)
        return true
    }

    private static func fetchAll(context: ModelContext) -> [GymProfile] {
        let descriptor = FetchDescriptor<GymProfile>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        do {
            return try context.fetch(descriptor)
        } catch {
            assertionFailure("Failed to fetch gym profiles: \(error)")
            return []
        }
    }

    private static func save(_ context: ModelContext) {
        do {
            try context.save()
        } catch {
            assertionFailure("Failed to save gym profiles: \(error)")
        }
    }
}
