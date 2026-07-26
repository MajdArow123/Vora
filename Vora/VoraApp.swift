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

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            UserProfile.self,
            FoodEntry.self,
            CustomFood.self,
            WorkoutSession.self,
            ExerciseLog.self,
            SetEntry.self,
            WeightEntry.self,
            BodyMeasurement.self,
            WaterEntry.self,
            CardioEntry.self,
            SplitDay.self,
            SavedMeal.self,
            SavedMealItem.self,
            Recipe.self,
            RecipeIngredient.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            #if DEBUG
            DemoSeeder.seedIfRequested(container: container)
            #endif
            return container
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(appearance.colorScheme)
                .onChange(of: scenePhase, initial: true) { _, phase in
                    guard phase == .active else { return }
                    NotificationService.shared.refreshAll(context: sharedModelContainer.mainContext)
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
