//
//  WorkoutSessionDetailView.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-24.
//

import SwiftUI
import SwiftData

struct WorkoutSessionDetailView: View {
    @Environment(\.modelContext) private var modelContext
    let session: WorkoutSession

    @State private var cardioEntries: [CardioEntry] = []

    var body: some View {
        ZStack {
            DesignSystem.Colors.background
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: DesignSystem.Spacing.md) {
                    Text(session.date.formatted(.dateTime.weekday(.wide).day().month().year()))
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    statsRow

                    ForEach(sortedExercises) { exercise in
                        exerciseCard(exercise)
                    }

                    ForEach(cardioEntries) { entry in
                        cardioCard(entry)
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.lg)
                .padding(.vertical, DesignSystem.Spacing.md)
            }
        }
        .navigationTitle(session.sessionName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadCardio()
        }
    }

    // MARK: - Stats

    private var statsRow: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            stat(value: Self.durationString(session.durationSeconds), label: "Duration")
            stat(value: "\(Int(session.totalVolumeKg.rounded())) kg", label: "Volume")
            stat(value: "\(completedSetCount)", label: "Sets Done")
        }
    }

    private func stat(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(DesignSystem.Typography.headline)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Exercise card

    private func exerciseCard(_ exercise: ExerciseLog) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text(exercise.exerciseName)
                .font(DesignSystem.Typography.headline)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            if !exercise.muscleGroups.isEmpty {
                muscleChips(exercise.muscleGroups)
            }

            HStack {
                Text("SET")
                    .frame(width: 34, alignment: .leading)
                Text("KG")
                    .frame(maxWidth: .infinity, alignment: .center)
                Text("REPS")
                    .frame(maxWidth: .infinity, alignment: .center)
                Color.clear.frame(width: 40, height: 1)
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(DesignSystem.Colors.textSecondary)

            ForEach(exercise.sets.sorted { $0.setNumber < $1.setNumber }) { set in
                setRow(set)
            }
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
    }

    private func setRow(_ set: SetEntry) -> some View {
        HStack {
            Text("\(set.setNumber)")
                .font(DesignSystem.Typography.headline)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .frame(width: 34, alignment: .leading)

            Text(ActiveSessionViewModel.weightString(set.weightKg))
                .font(DesignSystem.Typography.headline)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .center)

            Text("\(set.reps)")
                .font(DesignSystem.Typography.headline)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .center)

            Image(systemName: set.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(set.isCompleted
                                 ? DesignSystem.Colors.accent
                                 : DesignSystem.Colors.textSecondary.opacity(0.3))
                .frame(width: 40, height: 40)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, DesignSystem.Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                .fill(set.isCompleted ? DesignSystem.Colors.accent.opacity(0.08) : .clear)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Set \(set.setNumber), \(ActiveSessionViewModel.weightString(set.weightKg)) kilograms, \(set.reps) reps\(set.isCompleted ? ", completed" : "")"
        )
    }

    private func muscleChips(_ groups: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DesignSystem.Spacing.xs) {
                ForEach(groups, id: \.self) { group in
                    Text(MuscleGroup(rawValue: group)?.displayName ?? group.capitalized)
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.accent)
                        .padding(.horizontal, DesignSystem.Spacing.sm)
                        .padding(.vertical, 4)
                        .background(DesignSystem.Colors.accent.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
        }
    }

    // MARK: - Cardio

    private func cardioCard(_ entry: CardioEntry) -> some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            Image(systemName: entry.type.iconName)
                .foregroundStyle(DesignSystem.Colors.macroCarbs)
                .frame(width: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.type.displayName)
                    .font(DesignSystem.Typography.headline)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Text(entry.statsLine)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }

            Spacer()

            Text("\(Int(entry.estimatedCalories.rounded())) kcal")
                .font(DesignSystem.Typography.headline)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Helpers

    private var sortedExercises: [ExerciseLog] {
        session.exercises.sorted { $0.orderIndex < $1.orderIndex }
    }

    private var completedSetCount: Int {
        session.exercises.reduce(0) { total, exercise in
            total + exercise.sets.filter(\.isCompleted).count
        }
    }

    /// `h:mm` for an hour or more, otherwise `mm:ss`.
    static func durationString(_ seconds: Int) -> String {
        seconds >= 3600
            ? String(format: "%d:%02d", seconds / 3600, (seconds % 3600) / 60)
            : String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private func loadCardio() {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: session.date)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return }
        let descriptor = FetchDescriptor<CardioEntry>(
            predicate: #Predicate { $0.date >= dayStart && $0.date < dayEnd },
            sortBy: [SortDescriptor(\.date)]
        )
        cardioEntries = (try? modelContext.fetch(descriptor)) ?? []
    }
}

#Preview {
    NavigationStack {
        WorkoutSessionDetailView(session: WorkoutSession(
            date: .now,
            sessionName: "Push",
            durationSeconds: 3480,
            totalVolumeKg: 6420,
            exercises: [
                ExerciseLog(
                    exerciseName: "Bench Press",
                    muscleGroups: [MuscleGroup.chest.rawValue],
                    orderIndex: 0,
                    sets: [
                        SetEntry(setNumber: 1, weightKg: 80, reps: 8, isCompleted: true),
                        SetEntry(setNumber: 2, weightKg: 82.5, reps: 6, isCompleted: true),
                        SetEntry(setNumber: 3, weightKg: 85, reps: 5)
                    ]
                )
            ]
        ))
    }
    .modelContainer(for: [WorkoutSession.self, CardioEntry.self], inMemory: true)
}
