//
//  WorkoutSessionDetailView.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-24.
//

import OSLog
import SwiftUI
import SwiftData

struct WorkoutSessionDetailView: View {
    private static let logger = Logger(subsystem: "com.majdarow.Vora", category: "Workout")

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let session: WorkoutSession
    /// Deletes through History so its row goes before the model does.
    let onDelete: (HistoryItem) throws -> Void
    @Query private var profiles: [UserProfile]

    @State private var cardioEntries: [CardioEntry] = []
    @State private var pendingDeletion: HistoryDeletionPrompt?
    @State private var showingDeleteError = false
    /// Once set, nothing below may read `session`: it no longer exists.
    @State private var didDelete = false

    var body: some View {
        ZStack {
            DesignSystem.Colors.background
                .ignoresSafeArea()

            if !didDelete {
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
        }
        .navigationTitle(didDelete ? "" : session.sessionName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !didDelete {
                    Button(role: .destructive) {
                        pendingDeletion = HistoryDeletionPrompt(item: .lifting(session))
                    } label: {
                        Label("Delete Workout", systemImage: "trash")
                    }
                    .tint(DesignSystem.Colors.negative)
                }
            }
        }
        .onAppear {
            loadCardio()
        }
        .alert(
            pendingDeletion?.title ?? "",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            presenting: pendingDeletion
        ) { prompt in
            Button("Delete", role: .destructive) {
                confirmDeletion(prompt)
            }
            Button("Cancel", role: .cancel) {}
        } message: { prompt in
            Text(prompt.message)
        }
        .alert("Couldn't Delete", isPresented: $showingDeleteError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Nothing was removed. Please try again.")
        }
    }

    // MARK: - Delete

    private func confirmDeletion(_ prompt: HistoryDeletionPrompt) {
        pendingDeletion = nil
        switch prompt.item {
        case .lifting:
            didDelete = true
            do {
                try onDelete(prompt.item)
                dismiss()
            } catch {
                didDelete = false
                showingDeleteError = true
            }
        case .cardio(let entry):
            let previousEntries = cardioEntries
            cardioEntries.removeAll { $0.id == entry.id }
            do {
                try onDelete(prompt.item)
            } catch {
                cardioEntries = previousEntries
                showingDeleteError = true
            }
        }
    }

    // MARK: - Stats

    private var units: UnitSystem {
        profiles.first?.preferredUnits ?? .metric
    }

    private var statsRow: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            stat(value: Self.durationString(session.durationSeconds), label: "Duration")
            stat(value: UnitConversion.volumeText(kg: session.totalVolumeKg, units: units), label: "Volume")
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
            Text(exercise.displayName)
                .font(DesignSystem.Typography.headline)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            if !exercise.muscleGroups.isEmpty {
                muscleChips(exercise.muscleGroups)
            }

            HStack {
                Text("SET")
                    .frame(width: 34, alignment: .leading)
                Text(UnitConversion.weightUnitSymbol(units).uppercased())
                    .frame(maxWidth: .infinity, alignment: .center)
                Text("REPS")
                    .frame(maxWidth: .infinity, alignment: .center)
                Text("RIR")
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

            Text(UnitConversion.weightNumberText(kg: set.weightKg, units: units))
                .font(DesignSystem.Typography.headline)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .center)

            Text("\(set.reps)")
                .font(DesignSystem.Typography.headline)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .center)

            Text(set.rir.map { RIRScale.text($0) } ?? "–")
                .font(DesignSystem.Typography.headline)
                .foregroundStyle(set.rir == nil
                                 ? DesignSystem.Colors.textSecondary
                                 : DesignSystem.Colors.textPrimary)
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
            "Set \(set.setNumber), \(UnitConversion.weightNumberText(kg: set.weightKg, units: units)) \(UnitConversion.spokenWeightUnit(units)), \(set.reps) reps\(set.rir.map { ", \(RIRScale.spokenText($0))" } ?? "")\(set.isCompleted ? ", completed" : "")"
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
            .accessibilityElement(children: .combine)

            Button(role: .destructive) {
                pendingDeletion = HistoryDeletionPrompt(item: .cardio(entry))
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(DesignSystem.Colors.negative)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete \(entry.type.displayName)")
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
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
        guard !didDelete else { return }
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: session.date)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return }
        let descriptor = FetchDescriptor<CardioEntry>(
            predicate: #Predicate { $0.date >= dayStart && $0.date < dayEnd },
            sortBy: [SortDescriptor(\.date)]
        )
        do {
            cardioEntries = try modelContext.fetch(descriptor)
        } catch {
            Self.logger.error("Failed to load cardio for session: \(String(describing: error), privacy: .public)")
            cardioEntries = []
        }
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
        ), onDelete: { _ in })
    }
    .modelContainer(for: [WorkoutSession.self, CardioEntry.self], inMemory: true)
}
