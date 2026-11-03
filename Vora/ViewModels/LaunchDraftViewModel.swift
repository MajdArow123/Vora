//
//  LaunchDraftViewModel.swift
//  Vora
//
//  Created by Majd Arow on 2026-11-03.
//

import Foundation
import Observation
import SwiftData

/// The "Resume workout?" offer at launch, for a draft left by a killed session.
@Observable
final class LaunchDraftViewModel {
    /// The draft on offer; nil once it's answered.
    var draft: ActiveSessionDraft?

    private var didCheck = false
    private let store: SessionDraftStore
    private let alert: any RestAlertScheduling
    private let now: () -> Date

    init(
        store: SessionDraftStore = SessionDraftStore(),
        alert: any RestAlertScheduling = NoRestAlert(),
        now: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.alert = alert
        self.now = now
    }

    /// Offers a draft once per launch.
    func check() {
        guard !didCheck else { return }
        didCheck = true
        draft = store.loadResumable()
    }

    /// Removes the draft and reloads Home, which loaded while the draft still
    /// counted as today's session: with calorie cycling in cycle mode it would
    /// otherwise keep showing the training-day target.
    func discard(home: HomeViewModel, context: ModelContext) {
        store.clear()
        alert.cancel()
        draft = nil
        home.load(from: context, now: now())
    }
}
