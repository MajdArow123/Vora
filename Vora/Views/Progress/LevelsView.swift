//
//  LevelsView.swift
//  Vora
//
//  Created by Majd Arow on 2026-11-02.
//

import SwiftUI
import SwiftData

extension LevelsCalculator.Band {
    /// One hue, darker with more sets. Says how much, never whether that's
    /// good or bad.
    var color: Color {
        switch self {
        case .none: BodyDiagramLayout.neutralFill
        case .low: DesignSystem.Colors.accent.opacity(0.35)
        case .moderate: DesignSystem.Colors.accent.opacity(0.55)
        case .high: DesignSystem.Colors.accent.opacity(0.75)
        case .veryHigh: DesignSystem.Colors.accent
        }
    }
}

extension LevelsCalculator.Result {
    /// What VoiceOver reads for the body map.
    var bodyMapAccessibilityLabel: String {
        let trained = levels.filter { $0.setsPerWeek > 0 }
        guard !trained.isEmpty else { return "Body map with no muscles trained" }
        let parts = trained.map { "\($0.muscle.displayName) \(LevelsCalculator.setsText($0.setsPerWeek))" }
        return "Body map of sets per week. " + parts.joined(separator: ", ")
    }
}

struct LevelsView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var viewModel: LevelsViewModel
    @State private var selectedMuscle: Muscle?

    var body: some View {
        ZStack {
            DesignSystem.Colors.background
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: DesignSystem.Spacing.md) {
                    Picker("Range", selection: $viewModel.selectedRange) {
                        ForEach(LevelsCalculator.Range.allCases) { range in
                            Text(range.displayName).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)

                    if viewModel.loadFailed {
                        emptyState(icon: "exclamationmark.triangle", message: "Couldn't load your training. Try again later.")
                    } else if viewModel.result.hasTraining {
                        bodyMapCard
                        muscleListCard
                        if let summary = viewModel.result.excludedSummary {
                            excludedCard(summary: summary)
                        }
                    } else {
                        emptyState(icon: "figure.strengthtraining.traditional", message: "No training in \(viewModel.selectedRange.phrase).")
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.md)
                .padding(.bottom, DesignSystem.Spacing.xl)
            }
        }
        .navigationTitle("Levels")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedMuscle) { muscle in
            if let level = viewModel.result.level(for: muscle) {
                LevelsMuscleDetailView(level: level, range: viewModel.selectedRange)
            }
        }
        .onAppear { viewModel.load(from: modelContext) }
    }

    // MARK: - Body map

    private var bodyMapCard: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            BodyDiagramView(
                fill: { muscle in
                    viewModel.result.level(for: muscle)?.band.color ?? BodyDiagramLayout.neutralFill
                },
                accessibilityLabel: viewModel.result.bodyMapAccessibilityLabel,
                onSelect: { selectedMuscle = $0 }
            )
            .frame(maxHeight: 300)

            LevelsLegend()

            if viewModel.result.weeksAveraged < Double(viewModel.selectedRange.weeks) {
                Text("Averaged over \(LevelsCalculator.setsText(viewModel.result.weeksAveraged)) weeks, since your first session.")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large))
    }

    // MARK: - Muscle list

    private var muscleListCard: some View {
        let levels = viewModel.result.levels
        let scaleMax = max(LevelsMuscleRow.minimumScaleMax, levels.first?.setsPerWeek ?? 0)
        return VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Text("Sets per week")
                .font(DesignSystem.Typography.headline)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            ForEach(levels) { level in
                Button {
                    selectedMuscle = level.muscle
                } label: {
                    LevelsMuscleRow(level: level, scaleMax: scaleMax)
                }
                .buttonStyle(.plain)
            }

            Text(LevelsGuideline.footnote)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
    }

    // MARK: - Not counted

    private func excludedCard(summary: String) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text("Not counted")
                .font(DesignSystem.Typography.headline)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
            Text(summary)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(viewModel.result.excluded) { exercise in
                HStack {
                    Text(exercise.displayName)
                        .font(DesignSystem.Typography.body)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                    Spacer()
                    Text(LevelsCalculator.setCountText(exercise.completedSets))
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
    }

    // MARK: - Empty state

    private func emptyState(icon: String, message: String) -> some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: icon)
                .font(.title)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .accessibilityHidden(true)
            Text(message)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large))
    }
}

/// What each body map color means.
private struct LevelsLegend: View {
    var body: some View {
        VStack(spacing: DesignSystem.Spacing.xs) {
            Text("Sets per week")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
            HStack(spacing: DesignSystem.Spacing.md) {
                ForEach(LevelsCalculator.Band.allCases) { band in
                    HStack(spacing: DesignSystem.Spacing.xs) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(band.color)
                            .frame(width: 12, height: 12)
                        Text(band.legendLabel)
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                            .fixedSize()
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Legend: darker means more sets per week, from 0 up to 20 or more")
    }
}

private struct LevelsMuscleRow: View {
    /// Bars share a scale that always fits the guideline band.
    static let minimumScaleMax = 25.0

    let level: LevelsCalculator.MuscleLevel
    let scaleMax: Double

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            HStack {
                Text(level.muscle.displayName)
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Spacer()
                Text(LevelsCalculator.setsText(level.setsPerWeek))
                    .font(DesignSystem.Typography.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .accessibilityHidden(true)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(BodyDiagramLayout.neutralFill)
                    Capsule()
                        .fill(level.band.color)
                        .frame(width: geometry.size.width * min(1, level.setsPerWeek / scaleMax))
                    if let band = LevelsGuideline.band(for: level.muscle) {
                        LevelsGuidelineBand(band: band, scaleMax: scaleMax, width: geometry.size.width)
                    }
                }
            }
            .frame(height: 8)
            .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(level.muscle.displayName), \(LevelsCalculator.setsText(level.setsPerWeek)) sets per week")
        .accessibilityHint("Shows contributing exercises")
    }
}

/// The optional guideline band; see `LevelsGuideline` for how to remove it.
private struct LevelsGuidelineBand: View {
    let band: ClosedRange<Double>
    let scaleMax: Double
    let width: CGFloat

    var body: some View {
        Rectangle()
            .fill(DesignSystem.Colors.textPrimary.opacity(0.18))
            .frame(width: width * (band.upperBound - band.lowerBound) / scaleMax)
            .offset(x: width * band.lowerBound / scaleMax)
    }
}

/// The Strength section's way into Levels.
struct LevelsCard: View {
    let viewModel: LevelsViewModel

    var body: some View {
        NavigationLink {
            LevelsView(viewModel: viewModel)
        } label: {
            HStack(spacing: DesignSystem.Spacing.md) {
                BodyDiagramView(
                    fill: { muscle in
                        viewModel.result.level(for: muscle)?.band.color ?? BodyDiagramLayout.neutralFill
                    },
                    accessibilityLabel: viewModel.result.bodyMapAccessibilityLabel
                )
                .frame(height: 120)
                .frame(maxWidth: 130)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    Text("Levels")
                        .font(DesignSystem.Typography.headline)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                    Text(summary)
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .accessibilityHidden(true)
            }
            .padding(DesignSystem.Spacing.md)
            .background(DesignSystem.Colors.card)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows weekly sets per muscle")
    }

    private var summary: String {
        let phrase = viewModel.selectedRange.phrase
        guard viewModel.result.hasTraining else { return "No training in \(phrase)." }
        guard let top = viewModel.result.levels.first, top.setsPerWeek > 0 else {
            return "Weekly sets per muscle, \(phrase)."
        }
        return "Most trained: \(top.muscle.displayName), \(LevelsCalculator.setsText(top.setsPerWeek)) sets/week over \(phrase)."
    }
}

#Preview {
    NavigationStack {
        LevelsView(viewModel: LevelsViewModel())
    }
    .modelContainer(for: UserProfile.self, inMemory: true)
}
