//
//  ContentView.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Query private var profiles: [UserProfile]
    @State private var isFinishingOnboarding = false

    private var showOnboarding: Bool {
        profiles.isEmpty || isFinishingOnboarding
    }

    var body: some View {
        Group {
            if showOnboarding {
                OnboardingView(isFinishingOnboarding: $isFinishingOnboarding)
                    .transition(.opacity)
            } else {
                MainTabView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: showOnboarding)
    }
}

private struct MainTabView: View {
    @State private var selection = MainTabView.initialTab()

    /// Debug launch argument `--tab N` preselects a tab so screenshot
    /// automation can capture each screen without UI scripting.
    private static func initialTab() -> Int {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let flag = args.firstIndex(of: "--tab"),
           args.indices.contains(flag + 1),
           let tab = Int(args[flag + 1]), (0..<5).contains(tab) {
            return tab
        }
        #endif
        return 0
    }

    var body: some View {
        TabView(selection: $selection) {
            HomeView()
                .toolbarBackground(.visible, for: .tabBar)
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(0)

            FoodView()
                .toolbarBackground(.visible, for: .tabBar)
                .tabItem {
                    Label("Food", systemImage: "fork.knife")
                }
                .tag(1)

            WorkoutView()
                .toolbarBackground(.visible, for: .tabBar)
                .tabItem {
                    Label("Train", systemImage: "dumbbell.fill")
                }
                .tag(2)

            ProgressView()
                .toolbarBackground(.visible, for: .tabBar)
                .tabItem {
                    Label("Progress", systemImage: "chart.line.uptrend.xyaxis")
                }
                .tag(3)

            ProfileView()
                .toolbarBackground(.visible, for: .tabBar)
                .tabItem {
                    Label("Profile", systemImage: "person.fill")
                }
                .tag(4)
        }
        .tint(DesignSystem.Colors.accent)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: UserProfile.self, inMemory: true)
}
