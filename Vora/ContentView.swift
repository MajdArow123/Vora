//
//  ContentView.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import SwiftUI

struct ContentView: View {
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
}
