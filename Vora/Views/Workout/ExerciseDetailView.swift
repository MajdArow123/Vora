//
//  ExerciseDetailView.swift
//  Vora
//
//  Created by Majd Arow on 2026-08-10.
//

import SwiftUI

/// Resolved display data for the exercise detail screen. Custom
/// exercises (not in the library) resolve to no definition and fall
/// back to an empty diagram with no technique section.
struct ExerciseDetailContent {
    let name: String
    let definition: ExerciseDefinition?

    init(exerciseName: String) {
        name = exerciseName
        definition = ExerciseLibrary.definition(named: exerciseName)
    }

    var hasMuscleData: Bool {
        !(definition?.primaryMuscles.isEmpty ?? true)
    }

    var primaryMuscles: Set<Muscle> { definition?.primaryMuscles ?? [] }
    var secondaryMuscles: Set<Muscle> { definition?.secondaryMuscles ?? [] }
    var techniqueCues: [String] { definition?.techniqueCues ?? [] }

    var equipment: [EquipmentType] {
        (definition?.equipment ?? []).sorted { $0.displayName < $1.displayName }
    }
}

/// Muscle diagram and technique cues for one exercise. Pushed from the
/// exercise picker and presented as a sheet from the active session.
struct ExerciseDetailView: View {
    let content: ExerciseDetailContent

    init(exerciseName: String) {
        content = ExerciseDetailContent(exerciseName: exerciseName)
    }

    var body: some View {
        ZStack {
            DesignSystem.Colors.background
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                    if !content.equipment.isEmpty {
                        equipmentTags
                    }
                    muscleCard
                    if !content.techniqueCues.isEmpty {
                        techniqueSection
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.lg)
                .padding(.vertical, DesignSystem.Spacing.md)
            }
        }
        .navigationTitle(content.name)
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Equipment

    private var equipmentTags: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DesignSystem.Spacing.xs) {
                ForEach(content.equipment) { item in
                    Text(item.displayName)
                        .font(DesignSystem.Typography.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(DesignSystem.Colors.accent)
                        .padding(.horizontal, DesignSystem.Spacing.sm)
                        .padding(.vertical, 4)
                        .background(DesignSystem.Colors.accent.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Equipment: " + content.equipment.map(\.displayName).joined(separator: ", ")
        )
    }

    // MARK: - Muscles

    private var muscleCard: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            Text("Muscles Worked")
                .font(DesignSystem.Typography.headline)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            BodyDiagramView(
                primaryMuscles: content.primaryMuscles,
                secondaryMuscles: content.secondaryMuscles
            )
            .frame(maxWidth: 260)
            .frame(maxWidth: .infinity)

            if content.hasMuscleData {
                legend
            } else {
                Text("No muscle data")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
    }

    private var legend: some View {
        HStack(spacing: DesignSystem.Spacing.lg) {
            legendItem(color: DesignSystem.Colors.accent, label: "Primary")
            legendItem(color: DesignSystem.Colors.accent.opacity(0.35), label: "Secondary")
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(legendAccessibilityText)
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: DesignSystem.Spacing.xs) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color)
                .frame(width: 12, height: 12)
            Text(label)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
        }
    }

    private var legendAccessibilityText: String {
        var parts = ["Primary: " + sortedNames(content.primaryMuscles)]
        if !content.secondaryMuscles.isEmpty {
            parts.append("Secondary: " + sortedNames(content.secondaryMuscles))
        }
        return parts.joined(separator: ". ")
    }

    private func sortedNames(_ muscles: Set<Muscle>) -> String {
        muscles.map(\.displayName).sorted().joined(separator: ", ")
    }

    // MARK: - Technique

    private var techniqueSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text("Technique")
                .font(DesignSystem.Typography.headline)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            ForEach(Array(content.techniqueCues.enumerated()), id: \.offset) { index, cue in
                HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.sm) {
                    Image(systemName: "\(index + 1).circle.fill")
                        .font(.body)
                        .foregroundStyle(DesignSystem.Colors.accent)
                        .accessibilityHidden(true)
                    Text(cue)
                        .font(DesignSystem.Typography.body)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(DesignSystem.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignSystem.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
    }
}

/// Sheet wrapper used mid-workout: adds its own navigation stack and a
/// close button so cues are reachable without leaving the session.
struct ExerciseDetailSheet: View {
    let exerciseName: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ExerciseDetailView(exerciseName: exerciseName)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Close") { dismiss() }
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                    }
                }
        }
    }
}

#Preview("Library exercise") {
    NavigationStack {
        ExerciseDetailView(exerciseName: "Barbell Bench Press")
    }
}

#Preview("Custom exercise") {
    NavigationStack {
        ExerciseDetailView(exerciseName: "Weighted Yeti Carry")
    }
}
