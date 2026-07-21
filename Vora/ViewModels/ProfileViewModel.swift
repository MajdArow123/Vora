//
//  ProfileViewModel.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import Foundation
import Observation
import SwiftData

@Observable
final class ProfileViewModel {
    private(set) var profile: UserProfile?
    private(set) var latestWeight: WeightEntry?

    func load(from context: ModelContext) {
        profile = try? context.fetch(FetchDescriptor<UserProfile>()).first

        var weightDescriptor = FetchDescriptor<WeightEntry>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        weightDescriptor.fetchLimit = 1
        latestWeight = try? context.fetch(weightDescriptor).first
    }

    var age: Int? {
        guard let profile else { return nil }
        return Calendar.current.dateComponents([.year], from: profile.dateOfBirth, to: .now).year
    }

    var heightText: String? {
        guard let profile else { return nil }
        return UnitConversion.heightText(cm: profile.heightCm, units: profile.preferredUnits)
    }

    var weightText: String? {
        guard let profile, let latestWeight else { return nil }
        return UnitConversion.weightText(kg: latestWeight.weightKg, units: profile.preferredUnits)
    }

    var initials: String {
        guard let profile else { return "" }
        return profile.name
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first.map(String.init) }
            .joined()
            .uppercased()
    }
}
