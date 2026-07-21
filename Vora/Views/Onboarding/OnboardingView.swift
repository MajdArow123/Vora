//
//  OnboardingView.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import SwiftUI
import SwiftData

struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = OnboardingViewModel()
    @State private var healthKitService = HealthKitService()

    /// Kept true by ContentView while the post-save HealthKit permission
    /// request runs, so the tab bar doesn't appear underneath the sheet.
    @Binding var isFinishingOnboarding: Bool

    var body: some View {
        ZStack {
            DesignSystem.Colors.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    .padding(.vertical, DesignSystem.Spacing.md)

                stepContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                PrimaryButton(title: ctaTitle, action: handleContinue)
                    .disabled(!viewModel.canContinue || isFinishingOnboarding)
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    .padding(.bottom, DesignSystem.Spacing.md)
            }
        }
    }

    @ViewBuilder
    private var header: some View {
        if viewModel.canGoBack {
            HStack(spacing: DesignSystem.Spacing.md) {
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        viewModel.goBack()
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.headline)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                        .frame(width: 36, height: 36)
                        .background(.white)
                        .clipShape(Circle())
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")

                StepProgressIndicator(
                    currentStep: viewModel.step.rawValue - 1,
                    totalSteps: OnboardingStep.allCases.count - 1
                )
            }
        }
    }

    private var stepContent: some View {
        Group {
            switch viewModel.step {
            case .welcome:
                WelcomeStepView()
            case .basics:
                BasicsStepView(viewModel: viewModel)
            case .goal:
                GoalStepView(viewModel: viewModel)
            case .targets:
                TargetsStepView(viewModel: viewModel)
            case .trainingSplit:
                TrainingSplitStepView(viewModel: viewModel)
            case .summary:
                SummaryStepView(viewModel: viewModel)
            }
        }
        .id(viewModel.step)
        .transition(.asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        ))
    }

    private var ctaTitle: String {
        switch viewModel.step {
        case .welcome: "Get Started"
        case .summary: "Start Using Vora"
        default: "Continue"
        }
    }

    private func handleContinue() {
        if viewModel.step == .summary {
            finishOnboarding()
        } else {
            withAnimation(.easeInOut(duration: 0.3)) {
                viewModel.advance()
            }
        }
    }

    private func finishOnboarding() {
        isFinishingOnboarding = true
        viewModel.completeOnboarding(in: modelContext)

        Task {
            await healthKitService.requestAuthorization()
            withAnimation(.easeInOut(duration: 0.35)) {
                isFinishingOnboarding = false
            }
        }
    }
}

#Preview {
    OnboardingView(isFinishingOnboarding: .constant(false))
        .modelContainer(for: UserProfile.self, inMemory: true)
}
