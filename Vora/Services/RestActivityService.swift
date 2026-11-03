//
//  RestActivityService.swift
//  Vora
//
//  Created by Majd Arow on 2026-11-03.
//

import ActivityKit
import Foundation
import os

/// Shows the rest timer outside the app. Injected so tests never start a
/// real Live Activity.
protocol RestActivityControlling {
    /// Starts the activity, or updates the one already running.
    func show(_ state: RestActivityAttributes.ContentState)
    func end()
    /// Ends every activity before the process goes away, waiting briefly
    /// because nothing runs after `willTerminate` returns.
    func endAllBeforeTermination()
}

/// The view model's default, so only `ActiveSessionView` can reach ActivityKit.
struct NoRestActivity: RestActivityControlling {
    func show(_ state: RestActivityAttributes.ContentState) {}
    func end() {}
    func endAllBeforeTermination() {}
}

/// Keeps at most one Vora activity alive. Calls run one at a time in order,
/// because `update` and `end` are async: a skip right after a start must not
/// overtake it and leave the activity running.
final class RestActivityController: RestActivityControlling {
    private static let logger = Logger(subsystem: "com.majdarow.Vora", category: "RestActivity")
    private static let terminationWait: DispatchTimeInterval = .seconds(1)

    private var current: Activity<RestActivityAttributes>?
    private var lastCall: Task<Void, Never>?

    func show(_ state: RestActivityAttributes.ContentState) {
        enqueue { [self] in
            // The stale date flips the views to "Rest over" if the app is
            // suspended at the end time and can't end the activity itself.
            let content = ActivityContent(state: state, staleDate: state.endDate)
            await Self.endAll(except: current)
            if let current, current.activityState == .active || current.activityState == .stale {
                await current.update(content)
                return
            }
            guard ActivityAuthorizationInfo().areActivitiesEnabled else {
                Self.logger.info("Live Activities are turned off; showing the rest timer in the app only")
                current = nil
                return
            }
            do {
                current = try Activity.request(attributes: RestActivityAttributes(), content: content, pushType: nil)
            } catch {
                current = nil
                Self.logger.error("Couldn't start the rest activity: \(String(describing: error), privacy: .public)")
            }
        }
    }

    func end() {
        enqueue { [self] in
            current = nil
            await Self.endAll(except: nil)
        }
    }

    func endAllBeforeTermination() {
        let finished = DispatchSemaphore(value: 0)
        Task.detached {
            await Self.endAll(except: nil)
            finished.signal()
        }
        if finished.wait(timeout: .now() + Self.terminationWait) == .timedOut {
            Self.logger.error("Timed out ending the rest activity before termination")
        }
    }

    /// Ends activities left by a previous process. At launch no session owns
    /// one yet; a resumed session creates its own if its rest is still running.
    static func endLeftovers() {
        Task {
            await endAll(except: nil)
        }
    }

    private func enqueue(_ work: @escaping () async -> Void) {
        let previous = lastCall
        lastCall = Task {
            await previous?.value
            await work()
        }
    }

    private nonisolated static func endAll(except kept: Activity<RestActivityAttributes>?) async {
        for activity in Activity<RestActivityAttributes>.activities where activity.id != kept?.id {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
