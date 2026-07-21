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
    var body: some View {
        TabView {
            HomeView()
                .toolbarBackground(.visible, for: .tabBar)
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }

            FoodView()
                .toolbarBackground(.visible, for: .tabBar)
                .tabItem {
                    Label("Food", systemImage: "fork.knife")
                }

            WorkoutView()
                .toolbarBackground(.visible, for: .tabBar)
                .tabItem {
                    Label("Train", systemImage: "dumbbell.fill")
                }

            ProgressView()
                .toolbarBackground(.visible, for: .tabBar)
                .tabItem {
                    Label("Progress", systemImage: "chart.line.uptrend.xyaxis")
                }

            ProfileView()
                .toolbarBackground(.visible, for: .tabBar)
                .tabItem {
                    Label("Profile", systemImage: "person.fill")
                }
        }
        .tint(DesignSystem.Colors.accent)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: UserProfile.self, inMemory: true)
}
