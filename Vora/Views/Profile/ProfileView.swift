//
//  ProfileView.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import SwiftUI
import SwiftData

struct ProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = ProfileViewModel()

    var body: some View {
        ZStack {
            DesignSystem.Colors.background
                .ignoresSafeArea()

            if let profile = viewModel.profile {
                ScrollView {
                    VStack(spacing: DesignSystem.Spacing.lg) {
                        header(for: profile)

                        card("Body") {
                            row("Height", viewModel.heightText ?? "—")
                            Divider()
                            row("Weight", viewModel.weightText ?? "—")
                        }

                        card("Goal") {
                            row("Goal", profile.goalType.displayName)
                        }

                        card("Daily Targets") {
                            row("Calories", "\(profile.dailyCalorieTarget) kcal")
                            Divider()
                            row("Protein", "\(profile.proteinTargetG) g")
                            Divider()
                            row("Carbs", "\(profile.carbsTargetG) g")
                            Divider()
                            row("Fat", "\(profile.fatTargetG) g")
                            Divider()
                            row("Water", "\(Int(profile.waterTargetMl)) ml")
                        }

                        card("Preferences") {
                            row("Units", profile.preferredUnits.displayName)
                        }
                    }
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    .padding(.vertical, DesignSystem.Spacing.lg)
                }
            } else {
                Text("Profile")
                    .font(DesignSystem.Typography.screenTitle)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
            }
        }
        .onAppear {
            viewModel.load(from: modelContext)
        }
    }

    private func header(for profile: UserProfile) -> some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            ZStack {
                Circle()
                    .fill(DesignSystem.Colors.accent.opacity(0.15))
                    .frame(width: 88, height: 88)
                Text(viewModel.initials)
                    .font(DesignSystem.Typography.title)
                    .foregroundStyle(DesignSystem.Colors.accent)
            }

            Text(profile.name)
                .font(DesignSystem.Typography.screenTitle)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            if let age = viewModel.age {
                Text("Age \(age)")
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.textPrimary.opacity(0.6))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func card(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text(title)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textPrimary.opacity(0.5))
                .textCase(.uppercase)

            VStack(spacing: DesignSystem.Spacing.sm) {
                content()
            }
            .padding(DesignSystem.Spacing.md)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.textPrimary.opacity(0.6))
            Spacer()
            Text(value)
                .font(DesignSystem.Typography.headline)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
        }
    }
}

#Preview {
    ProfileView()
        .modelContainer(for: UserProfile.self, inMemory: true)
}
