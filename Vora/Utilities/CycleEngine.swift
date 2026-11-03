//
//  CycleEngine.swift
//  Vora
//
//  Created by Majd Arow on 2026-11-03.
//

import Foundation

/// The rules of a training cycle, on plain values: what's next, what advancing
/// does, and when a rest entry has passed. docs/TRAINING_CYCLES.md explains them.
nonisolated enum CycleEngine {
    struct Entry: Equatable {
        let id: UUID
        let isRest: Bool
    }

    struct Position: Equatable {
        var currentID: UUID?
        /// Start of the calendar day a current rest entry applies to.
        var restDay: Date?
    }

    /// Below this, a cycle with rest entries still allows ordinary rest days.
    static let minimumRestAllowance = 2

    /// The entry for `id`, or the first when it's nil or no longer exists.
    static func current(in entries: [Entry], id: UUID?) -> Entry? {
        entries.first { $0.id == id } ?? entries.first
    }

    /// The entry after `id`, wrapping at the end; nil if `id` isn't in the cycle.
    static func entry(after id: UUID, in entries: [Entry]) -> Entry? {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return nil }
        return entries[(index + 1) % entries.count]
    }

    /// The first training entry at or after `id`, wrapping; nil in an all-rest cycle.
    static func nextTraining(from id: UUID?, in entries: [Entry]) -> Entry? {
        guard let start = current(in: entries, id: id),
              let index = entries.firstIndex(of: start)
        else { return nil }
        return (0..<entries.count)
            .map { entries[(index + $0) % entries.count] }
            .first { !$0.isRest }
    }

    /// The position after `id` is done or skipped. A rest entry reached by
    /// finishing a session applies tomorrow, since today was a training day;
    /// reached by skipping, it applies today.
    static func advanced(
        from id: UUID,
        in entries: [Entry],
        viaSession: Bool,
        today: Date,
        calendar: Calendar
    ) -> Position? {
        guard let next = entry(after: id, in: entries) else { return nil }
        guard next.isRest else { return Position(currentID: next.id, restDay: nil) }
        let todayStart = calendar.startOfDay(for: today)
        let restDay = viaSession ? calendar.date(byAdding: .day, value: 1, to: todayStart) : todayStart
        return Position(currentID: next.id, restDay: restDay ?? todayStart)
    }

    /// Moves past rest entries whose day has gone, one per elapsed day, and
    /// stops at the first training day. Running it again changes nothing.
    static func settled(
        _ position: Position,
        in entries: [Entry],
        today: Date,
        calendar: Calendar
    ) -> Position {
        guard var entry = current(in: entries, id: position.currentID) else {
            return Position(currentID: nil, restDay: nil)
        }
        let todayStart = calendar.startOfDay(for: today)
        guard entry.isRest else { return Position(currentID: entry.id, restDay: nil) }
        var restDay = position.restDay.map { calendar.startOfDay(for: $0) } ?? todayStart

        for _ in entries where entry.isRest && restDay < todayStart {
            guard let next = Self.entry(after: entry.id, in: entries) else { break }
            entry = next
            guard entry.isRest else { return Position(currentID: entry.id, restDay: nil) }
            restDay = calendar.date(byAdding: .day, value: 1, to: restDay) ?? todayStart
        }
        return Position(currentID: entry.id, restDay: restDay)
    }

    /// The most consecutive rest entries, counting around the wrap.
    static func longestRestRun(in entries: [Entry]) -> Int {
        guard entries.contains(where: { !$0.isRest }) else { return entries.count }
        var longest = 0
        var run = 0
        for entry in entries + entries {
            run = entry.isRest ? run + 1 : 0
            longest = max(longest, run)
        }
        return longest
    }

    /// How many untrained days in a row keep a cycle streak alive. Following
    /// the cycle's own rest entries can never break it.
    static func restAllowance(in entries: [Entry]) -> Int {
        max(minimumRestAllowance, longestRestRun(in: entries))
    }

    /// 1-based number among training entries; nil for rest entries.
    static func dayNumber(of id: UUID, in entries: [Entry]) -> Int? {
        var number = 0
        for entry in entries where !entry.isRest {
            number += 1
            if entry.id == id { return number }
        }
        return nil
    }

    /// "Day 2 · Pull", or "Day 2" with a blank title.
    static func displayName(number: Int, title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Day \(number)" : "Day \(number) · \(trimmed)"
    }
}
