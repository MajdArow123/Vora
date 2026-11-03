//
//  SetType.swift
//  Vora
//
//  Created by Majd Arow on 2026-11-02.
//

import Foundation

/// What kind of set was performed. Every rule for who counts what lives here,
/// so PRs, progression, Levels and volume can't drift apart; docs/SET_TYPES.md
/// explains why. Raw values are persisted and never change.
nonisolated enum SetType: String, CaseIterable, Codable, Identifiable {
    case normal
    case warmUp
    case drop
    case failure
    case myoRep

    var id: String { rawValue }

    /// Warm-ups prepare for the work; they aren't the work.
    var countsTowardVolume: Bool { self != .warmUp }

    /// Set counts shown to the user and the Levels count follow volume.
    var countsAsTrainingSet: Bool { countsTowardVolume }

    /// Straight sets only. Drop and myo-rep sets follow incomplete rest, and a
    /// myo-rep row may hold a whole cluster's reps, which would fake a record.
    var countsTowardRecords: Bool { self == .normal || self == .failure }

    /// Straight sets only, for the same reason: they say what you can do
    /// fresh. Failure sets count, with RIR 0 implied.
    var isWorkingSet: Bool { self == .normal || self == .failure }

    /// Reps in reserve a set of this type implies when none was logged.
    var impliedRIR: Int? { self == .failure ? 0 : nil }

    /// What was logged, else what the type implies. A logged value always wins.
    func effectiveRIR(logged: Int?) -> Int? {
        logged ?? impliedRIR
    }

    var displayName: String {
        switch self {
        case .normal: "Normal"
        case .warmUp: "Warm-up"
        case .drop: "Drop set"
        case .failure: "To failure"
        case .myoRep: "Myo-reps"
        }
    }

    /// Stands in for the set number; nil for normal sets, which show theirs.
    var badge: String? {
        switch self {
        case .normal: nil
        case .warmUp: "W"
        case .drop: "D"
        case .failure: "F"
        case .myoRep: "M"
        }
    }

    /// nil or an unknown raw value means normal.
    init(stored rawValue: String?) {
        self = rawValue.flatMap(SetType.init(rawValue:)) ?? .normal
    }
}

/// The side of a unilateral set. Raw values are persisted and never change.
nonisolated enum SetSide: String, CaseIterable, Codable, Identifiable {
    case left
    case right

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .left: "Left"
        case .right: "Right"
        }
    }

    var badge: String {
        switch self {
        case .left: "L"
        case .right: "R"
        }
    }
}

nonisolated enum SetCounting {
    /// How many training sets some completed sets make. Warm-ups don't count,
    /// and a left and a right row together are one set, so logging sides
    /// doesn't double the count. A lone side still counts as one.
    static func trainingSetCount(_ sets: [(type: SetType, side: SetSide?)]) -> Int {
        let counted = sets.filter(\.type.countsAsTrainingSet)
        let left = counted.count { $0.side == .left }
        let right = counted.count { $0.side == .right }
        return counted.count { $0.side == nil } + max(left, right)
    }

    /// Labels for a list of set types, in order: normal sets are numbered
    /// among themselves, every other type shows its badge.
    static func labels(_ types: [SetType]) -> [String] {
        var normal = 0
        return types.map { type in
            if let badge = type.badge { return badge }
            normal += 1
            return "\(normal)"
        }
    }

    /// Links the exercise at `index` with the one after it. If either is
    /// already in a superset, the other joins it, and two supersets merge.
    static func linkingWithNext(_ groups: [Int?], at index: Int) -> [Int?] {
        guard groups.indices.contains(index), groups.indices.contains(index + 1) else { return groups }
        let current = groups[index]
        let next = groups[index + 1]
        let group = current ?? next ?? (groups.compactMap { $0 }.max() ?? 0) + 1
        var linked = groups
        for member in groups.indices where member == index || member == index + 1
            || (groups[member] != nil && (groups[member] == current || groups[member] == next)) {
            linked[member] = group
        }
        return normalizedSupersetGroups(linked)
    }

    /// Takes one exercise out of its superset. Leaving from the middle splits
    /// it, and any exercise left alone loses its link.
    static func unlinking(_ groups: [Int?], at index: Int) -> [Int?] {
        guard groups.indices.contains(index) else { return groups }
        var unlinked = groups
        unlinked[index] = nil
        return normalizedSupersetGroups(unlinked)
    }

    /// Dense group numbers in exercise order. A group must be consecutive and
    /// have at least two exercises: a later run of the same number becomes its
    /// own group, and a lone exercise loses its link.
    static func normalizedSupersetGroups(_ groups: [Int?]) -> [Int?] {
        var result = [Int?](repeating: nil, count: groups.count)
        var next = 1
        var index = 0
        while index < groups.count {
            guard let group = groups[index] else {
                index += 1
                continue
            }
            var end = index + 1
            while end < groups.count, groups[end] == group { end += 1 }
            if end - index >= 2 {
                for member in index..<end { result[member] = next }
                next += 1
            }
            index = end
        }
        return result
    }
}
