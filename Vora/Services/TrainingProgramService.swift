//
//  TrainingProgramService.swift
//  Vora
//
//  Created by Majd Arow on 2026-11-03.
//

import Foundation
import OSLog
import SwiftData

/// A cycle day as the screens need it, with no SwiftData object to hold on to.
struct CycleDayInfo: Identifiable, Equatable {
    let id: UUID
    let title: String
    /// "Day 2 · Pull", or "Rest" for a rest entry.
    let name: String
    let muscleGroups: [String]
    let isRest: Bool
    /// 1-based among training days; nil for rest entries.
    let number: Int?

    var slot: TemplateSlot { TemplateSlot(cycleDayID: id) }
}

/// Where the cycle stands right now.
struct CycleToday: Equatable {
    /// The next entry, which may be a rest entry.
    let current: CycleDayInfo
    /// The training day a session started now is for; nil in an all-rest cycle.
    let nextTraining: CycleDayInfo?
    let days: [CycleDayInfo]
    let restAllowance: Int

    var trainingDays: [CycleDayInfo] { days.filter { !$0.isRest } }
}

/// A position change waiting on the session's save, undone if that fails.
struct CycleAdvance {
    let program: TrainingProgram
    let prior: CycleEngine.Position

    func undo() {
        program.currentDayID = prior.currentID
        program.restDay = prior.restDay
    }
}

enum CycleEditError: Error, Equatable {
    case lastTrainingDay
    case dayNotFound
}

/// Reads and changes the schedule mode and the cycle. The rules themselves are
/// in CycleEngine; this applies them to the store.
enum TrainingProgramService {
    private static let logger = Logger(subsystem: "com.majdarow.Vora", category: "Workout")

    // MARK: - Reading

    static func program(context: ModelContext) throws -> TrainingProgram? {
        var descriptor = FetchDescriptor<TrainingProgram>()
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// The program when cycle mode is on; nil means weekly.
    static func activeCycle(context: ModelContext) throws -> TrainingProgram? {
        guard let program = try program(context: context), program.mode == .cycle else { return nil }
        return program
    }

    static func mode(context: ModelContext) throws -> ScheduleMode {
        try program(context: context)?.mode ?? .weekly
    }

    /// The cycle's state at `now`; nil in weekly mode. Read-only, so anything
    /// can ask without writing; `settle` is what stores a passed rest entry.
    static func today(
        context: ModelContext,
        now: Date = .now,
        calendar: Calendar = .current
    ) throws -> CycleToday? {
        guard let program = try activeCycle(context: context) else { return nil }
        let days = program.orderedDays
        let entries = days.map { entry($0) }
        let position = CycleEngine.settled(position(of: program), in: entries, today: now, calendar: calendar)
        let infos = days.map { info(for: $0, entries: entries) }
        guard let current = infos.first(where: { $0.id == position.currentID }) else { return nil }
        let nextTraining = CycleEngine.nextTraining(from: current.id, in: entries).flatMap { next in
            infos.first { $0.id == next.id }
        }
        return CycleToday(
            current: current,
            nextTraining: nextTraining,
            days: infos,
            restAllowance: CycleEngine.restAllowance(in: entries)
        )
    }

    /// Today's cycle state, logging a failed read as weekly so one bad query
    /// can't block a screen.
    static func todayOrNil(context: ModelContext, now: Date = .now, calendar: Calendar = .current) -> CycleToday? {
        do {
            return try today(context: context, now: now, calendar: calendar)
        } catch {
            logger.error("Failed to read the training cycle: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Stores the position once a rest entry's day has passed. Never blocks a
    /// screen: `today` works out the same answer if this can't save.
    static func settle(context: ModelContext, now: Date = .now, calendar: Calendar = .current) {
        do {
            guard let program = try activeCycle(context: context) else { return }
            let settled = CycleEngine.settled(
                position(of: program),
                in: program.orderedDays.map { entry($0) },
                today: now,
                calendar: calendar
            )
            guard settled != position(of: program) else { return }
            program.currentDayID = settled.currentID
            program.restDay = settled.restDay
            try context.save()
        } catch {
            logger.error("Failed to settle the training cycle: \(String(describing: error), privacy: .public)")
        }
    }

    /// The training streak under the current mode's rule. A failed read counts
    /// no rest days rather than blocking the screen.
    static func streak(
        sessionDates: [Date],
        context: ModelContext,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Int {
        if let cycle = todayOrNil(context: context, now: now, calendar: calendar) {
            return StreakCalculator.cycleStreak(
                sessionDates: sessionDates,
                restAllowance: cycle.restAllowance,
                today: now,
                calendar: calendar
            )
        }
        var restIndices: Set<Int> = []
        do {
            restIndices = Set(try context.fetch(FetchDescriptor<SplitDay>()).filter(\.isRest).map(\.dayIndex))
        } catch {
            logger.error("Failed to read split days for the streak: \(String(describing: error), privacy: .public)")
        }
        return StreakCalculator.adherenceStreak(
            sessionDates: sessionDates,
            restDayIndices: restIndices,
            today: now,
            calendar: calendar
        )
    }

    // MARK: - Switching modes

    /// Switching to cycle mode the first time builds the cycle from the weekly
    /// split, and later switches resume it where it was. Switching back only
    /// changes the mode: SplitDay rows and weekly templates are never touched.
    static func setMode(_ mode: ScheduleMode, context: ModelContext) throws {
        let existing = try program(context: context)
        guard mode == .cycle || existing != nil else { return }
        let program = existing ?? TrainingProgram()
        if existing == nil { context.insert(program) }
        program.mode = mode
        if mode == .cycle, program.days.isEmpty {
            try buildDays(in: program, context: context)
        }
        try context.save()
    }

    /// Replaces the cycle with a fresh copy of the weekly split.
    static func rebuildFromWeekly(context: ModelContext) throws {
        guard let program = try program(context: context) else { return }
        for day in program.days { context.delete(day) }
        program.days.removeAll()
        try buildDays(in: program, context: context)
        try context.save()
    }

    /// Each training day of the week becomes a cycle day, Monday first, with a
    /// copy of what that weekday would start today. Fresh exercise IDs, since
    /// the weekly template keeps its rows. A split with no training days starts
    /// with one empty day, as a cycle needs at least one.
    private static func buildDays(in program: TrainingProgram, context: ModelContext) throws {
        let split = try context.fetch(FetchDescriptor<UserProfile>()).first?.trainingSplit ?? .fullBody
        let rows = try context.fetch(FetchDescriptor<SplitDay>(sortBy: [SortDescriptor(\.dayIndex)]))
        let week: [(dayIndex: Int, title: String, muscleGroups: [String])]
        if rows.count == WorkoutTemplateService.dayIndices.count {
            week = rows.filter { !$0.isRest }.map { ($0.dayIndex, $0.title, $0.muscleGroups) }
        } else {
            week = split.weeklyTemplate.enumerated()
                .filter { !$0.element.isRest }
                .map { ($0.offset, $0.element.title, $0.element.muscleGroups) }
        }

        var days: [CycleDay] = []
        for (order, weekday) in week.enumerated() {
            let plan = try WorkoutTemplateService.plan(for: split, dayIndex: weekday.dayIndex, context: context)
            let day = makeDay(orderIndex: order, title: weekday.title, muscleGroups: weekday.muscleGroups)
            context.insert(day)
            program.days.append(day)
            WorkoutTemplateService.copy(plan, into: day.template)
            days.append(day)
        }
        if days.isEmpty {
            let day = makeDay(orderIndex: 0, title: "")
            context.insert(day)
            program.days.append(day)
            days.append(day)
        }
        program.currentDayID = days.first?.id
        program.restDay = nil
    }

    private static func makeDay(orderIndex: Int, title: String, muscleGroups: [String] = []) -> CycleDay {
        CycleDay(
            orderIndex: orderIndex,
            title: title,
            muscleGroups: muscleGroups,
            template: WorkoutTemplate(cycleName: title)
        )
    }

    // MARK: - Moving through the cycle

    /// "Skip to next day": advances one with no session logged.
    static func skip(context: ModelContext, now: Date = .now, calendar: Calendar = .current) throws {
        guard let program = try activeCycle(context: context) else { return }
        let entries = program.orderedDays.map { entry($0) }
        let settled = CycleEngine.settled(position(of: program), in: entries, today: now, calendar: calendar)
        guard let current = settled.currentID,
              let next = CycleEngine.advanced(from: current, in: entries, viaSession: false, today: now, calendar: calendar)
        else { return }
        program.currentDayID = next.currentID
        program.restDay = next.restDay
        try context.save()
    }

    /// Advances past a finished day, whichever day it was, without saving, so
    /// the move is saved together with the session. Nil when there's nothing
    /// to move: weekly mode, or the day has since been removed.
    static func recordFinish(
        dayID: UUID,
        context: ModelContext,
        now: Date = .now,
        calendar: Calendar = .current
    ) throws -> CycleAdvance? {
        guard let program = try activeCycle(context: context) else { return nil }
        let entries = program.orderedDays.map { entry($0) }
        guard let next = CycleEngine.advanced(from: dayID, in: entries, viaSession: true, today: now, calendar: calendar)
        else { return nil }
        let advance = CycleAdvance(program: program, prior: position(of: program))
        program.currentDayID = next.currentID
        program.restDay = next.restDay
        return advance
    }

    /// "Set as next day" in the editor.
    static func setNext(dayID: UUID, context: ModelContext, now: Date = .now, calendar: Calendar = .current) throws {
        guard let program = try program(context: context),
              let day = program.days.first(where: { $0.id == dayID })
        else { throw CycleEditError.dayNotFound }
        program.currentDayID = day.id
        program.restDay = day.isRest ? calendar.startOfDay(for: now) : nil
        try context.save()
    }

    // MARK: - Editing

    @discardableResult
    static func addDay(isRest: Bool, context: ModelContext) throws -> UUID {
        guard let program = try program(context: context) else { throw CycleEditError.dayNotFound }
        let order = (program.days.map(\.orderIndex).max() ?? -1) + 1
        let day = isRest
            ? CycleDay(orderIndex: order, title: "Rest", isRest: true)
            : makeDay(orderIndex: order, title: "")
        context.insert(day)
        program.days.append(day)
        try context.save()
        return day.id
    }

    /// A removed next day hands over to the one after it. The last training
    /// day can't go, since a cycle of only rest could never start a session.
    static func remove(dayID: UUID, context: ModelContext, now: Date = .now, calendar: Calendar = .current) throws {
        guard let program = try program(context: context),
              let day = program.days.first(where: { $0.id == dayID })
        else { throw CycleEditError.dayNotFound }
        guard canRemove(day, from: program) else { throw CycleEditError.lastTrainingDay }

        let entries = program.orderedDays.map { entry($0) }
        if program.currentDayID == dayID,
           let next = CycleEngine.entry(after: dayID, in: entries) {
            program.currentDayID = next.id
            program.restDay = next.isRest ? calendar.startOfDay(for: now) : nil
        }
        program.days.removeAll { $0.id == dayID }
        context.delete(day)
        renumber(program.orderedDays)
        try context.save()
    }

    static func canRemove(_ day: CycleDay, from program: TrainingProgram) -> Bool {
        day.isRest || program.days.count { !$0.isRest } > 1
    }

    /// Reorders the cycle; the next day stays the next day.
    static func reorder(dayIDs: [UUID], context: ModelContext) throws {
        guard let program = try program(context: context) else { throw CycleEditError.dayNotFound }
        let days = program.days
        renumber(dayIDs.compactMap { id in days.first { $0.id == id } })
        try context.save()
    }

    /// Renames a day and the template it owns, so the two can't disagree.
    static func rename(_ day: CycleDay, to title: String) {
        day.title = title
        day.template?.name = title
    }

    // MARK: - Helpers

    private static func renumber(_ days: [CycleDay]) {
        for (index, day) in days.enumerated() where day.orderIndex != index {
            day.orderIndex = index
        }
    }

    private static func position(of program: TrainingProgram) -> CycleEngine.Position {
        CycleEngine.Position(currentID: program.currentDayID, restDay: program.restDay)
    }

    private static func entry(_ day: CycleDay) -> CycleEngine.Entry {
        CycleEngine.Entry(id: day.id, isRest: day.isRest)
    }

    private static func info(for day: CycleDay, entries: [CycleEngine.Entry]) -> CycleDayInfo {
        let number = CycleEngine.dayNumber(of: day.id, in: entries)
        return CycleDayInfo(
            id: day.id,
            title: day.title,
            name: number.map { CycleEngine.displayName(number: $0, title: day.title) } ?? "Rest",
            muscleGroups: day.muscleGroups,
            isRest: day.isRest,
            number: number
        )
    }
}
