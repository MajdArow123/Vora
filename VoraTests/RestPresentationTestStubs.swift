//
//  RestPresentationTestStubs.swift
//  VoraTests
//
//  Created by Majd Arow on 2026-11-03.
//

import Foundation
import UserNotifications
@testable import Vora

/// Records what the view model asks of the Live Activity.
final class RecordingRestActivity: RestActivityControlling {
    enum Call: Equatable {
        case show(RestActivityAttributes.ContentState)
        case end
        case endAllBeforeTermination
    }

    private(set) var calls: [Call] = []

    var shown: [RestActivityAttributes.ContentState] {
        calls.compactMap {
            if case let .show(state) = $0 { return state }
            return nil
        }
    }

    func show(_ state: RestActivityAttributes.ContentState) { calls.append(.show(state)) }
    func end() { calls.append(.end) }
    func endAllBeforeTermination() { calls.append(.endAllBeforeTermination) }
}

/// Records what the view model asks of the rest-over alert.
final class RecordingRestAlert: RestAlertScheduling {
    enum Call: Equatable {
        case schedule(Date, String)
        case cancel
    }

    private(set) var calls: [Call] = []

    func schedule(at endDate: Date, body: String) { calls.append(.schedule(endDate, body)) }
    func cancel() { calls.append(.cancel) }
}

/// A notification center that keeps its requests in memory.
final class StubNotificationCenter: UserNotificationCentering {
    var status: UNAuthorizationStatus
    var addError: Error?
    /// Runs while an add is in flight.
    var onAdd: (() -> Void)?
    private(set) var pending: [String: UNNotificationRequest] = [:]
    private(set) var addCount = 0
    private(set) var deliveredRemovals = 0

    init(status: UNAuthorizationStatus = .authorized) {
        self.status = status
    }

    func authorizationStatus() async -> UNAuthorizationStatus { status }

    func add(_ request: UNNotificationRequest) async throws {
        addCount += 1
        onAdd?()
        if let addError { throw addError }
        pending[request.identifier] = request
    }

    func removePendingRequests(withIdentifiers identifiers: [String]) {
        identifiers.forEach { pending[$0] = nil }
    }

    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
        deliveredRemovals += 1
    }
}
