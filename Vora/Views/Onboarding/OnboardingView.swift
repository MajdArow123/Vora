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
                    .disabled(!viewModel.canContinue)
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
                }
                .buttonStyle(.plain)

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
        withAnimation(.easeInOut(duration: 0.3)) {
            if viewModel.step == .summary {
                viewModel.completeOnboarding(in: modelContext)
            } else {
                viewModel.advance()
            }
        }
    }
}

#Preview {
    OnboardingView()
        .modelContainer(for: UserProfile.self, inMemory: true)
}
