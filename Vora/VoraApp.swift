//
//  VoraApp.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import SwiftUI
import SwiftData

@main
struct VoraApp: App {
    @AppStorage(AppearanceSetting.storageKey) private var appearance: AppearanceSetting = .system
    @Environment(\.scenePhase) private var scenePhase
    @State private var dataStore = AppDataStore()

    init() {
        // Meal suggestions moved to the ProTracker backend; remove any
        // Anthropic API key a pre-backend build left in UserDefaults.
        UserDefaults.standard.removeObject(forKey: "vora.anthropic.apiKey")
    }

    var body: some Scene {
        WindowGroup {
            Group {
                switch dataStore.state {
                case .loading:
                    DesignSystem.Colors.background
                        .ignoresSafeArea()
                case .ready(let container):
                    ContentView()
                        .modelContainer(container)
                        .onChange(of: scenePhase, initial: true) { _, phase in
                            guard phase == .active else { return }
                            NotificationService.shared.refreshAll(context: container.mainContext)
                        }
                case .failed(let details):
                    DataStoreErrorView(details: details, onRetry: dataStore.retry)
                }
            }
            .preferredColorScheme(appearance.colorScheme)
            .task { dataStore.load() }
        }
    }
}
