//
//  ActiveSessionView.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import SwiftUI
import SwiftData

struct ActiveSessionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: ActiveSessionViewModel
    @State private var showingExercisePicker = false
    @State private var showingDiscardConfirm = false
    @AppStorage("restTimerSeconds") private var restTimerSeconds = 90

    private let healthKitService = HealthKitService()

    init(sessionName: String) {
        _viewModel = State(initialValue: ActiveSessionViewModel(sessionName: sessionName))
    }

    var body: some View {
        ZStack {
            DesignSystem.Colors.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    .padding(.vertical, DesignSystem.Spacing.sm)

                ScrollView {
                    VStack(spacing: DesignSystem.Spacing.md) {
                        ForEach(viewModel.exercises) { exercise in
                            ExerciseSessionCard(
                                exercise: exercise,
                                viewModel: viewModel,
                                onSetCompleted: {
                                    viewModel.startRest(duration: TimeInterval(restTimerSeconds))
                                }
                            )
                        }

                        Button {
                            showingExercisePicker = true
                        } label: {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                Text("Add Exercise")
                                    .font(DesignSystem.Typography.headline)
                                Spacer()
                            }
                            .foregroundStyle(DesignSystem.Colors.accent)
                            .padding(DesignSystem.Spacing.md)
                            .background(DesignSystem.Colors.card)
                            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    .padding(.bottom, 120)
                }
                .scrollDismissesKeyboard(.interactively)
            }

            VStack {
                Spacer()
                if viewModel.restEndDate != nil {
                    RestTimerBar(viewModel: viewModel)
                        .padding(.horizontal, DesignSystem.Spacing.lg)
                        .padding(.bottom, DesignSystem.Spacing.md)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.35), value: viewModel.restEndDate != nil)
        }
        .sheet(isPresented: $showingExercisePicker) {
            ExercisePickerView { name, muscleGroups in
                viewModel.addExercise(name: name, muscleGroups: muscleGroups, context: modelContext)
            }
        }
        .sheet(item: $viewModel.summary, onDismiss: { dismiss() }) { summary in
            SessionSummaryView(summary: summary)
        }
        .confirmationDialog(
            "Discard this session?",
            isPresented: $showingDiscardConfirm,
            titleVisibility: .visible
        ) {
            Button("Discard Session", role: .destructive) { dismiss() }
            Button("Keep Training", role: .cancel) {}
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button {
                if viewModel.completedSetCount > 0 {
                    showingDiscardConfirm = true
                } else {
                    dismiss()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .frame(width: 44, height: 44)
                    .background(DesignSystem.Colors.card)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            Spacer()

            TimelineView(.periodic(from: .now, by: 1)) { _ in
                VStack(spacing: 0) {
                    Text(Self.timeString(viewModel.elapsedSeconds))
                        .font(.system(.headline, design: .monospaced))
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                    Text("\(Int(viewModel.totalVolumeKg.rounded())) kg volume")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
            }

            Spacer()

            Button {
                viewModel.finish(context: modelContext)
                let start = viewModel.startDate
                let service = healthKitService
                Task {
                    await service.saveStrengthWorkout(start: start, end: .now)
                }
            } label: {
                Text("Finish")
                    .font(DesignSystem.Typography.headline)
                    .foregroundStyle(viewModel.canFinish ? .white : DesignSystem.Colors.textSecondary)
                    .padding(.horizontal, DesignSystem.Spacing.md)
                    .frame(height: 44)
                    .background(viewModel.canFinish
                                ? DesignSystem.Colors.accent
                                : DesignSystem.Colors.card)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canFinish)
        }
    }

    static func timeString(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

// MARK: - Exercise card

struct ExerciseSessionCard: View {
    let exercise: ActiveSessionViewModel.DraftExercise
    let viewModel: ActiveSessionViewModel
    let onSetCompleted: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            HStack {
                Text(exercise.name)
                    .font(DesignSystem.Typography.headline)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Spacer()
                Menu {
                    Button(role: .destructive) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.removeExercise(exercise.id)
                        }
                    } label: {
                        Label("Remove Exercise", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .frame(width: 36, height: 36)
                }
            }

            HStack {
                Text("SET")
                    .frame(width: 34, alignment: .leading)
                Text("PREVIOUS")
                    .frame(width: 76, alignment: .leading)
                Text("KG")
                    .frame(maxWidth: .infinity, alignment: .center)
                Text("REPS")
                    .frame(maxWidth: .infinity, alignment: .center)
                Color.clear.frame(width: 40, height: 1)
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(DesignSystem.Colors.textSecondary)

            ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { index, set in
                SetRow(
                    setNumber: index + 1,
                    set: set,
                    previousText: index < exercise.previousSets.count
                        ? exercise.previousSets[index].text
                        : "—",
                    exerciseID: exercise.id,
                    viewModel: viewModel,
                    onCompleted: onSetCompleted
                )
            }

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.addSet(to: exercise.id)
                }
            } label: {
                HStack {
                    Image(systemName: "plus")
                    Text("Add Set")
                }
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DesignSystem.Spacing.sm)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
    }
}

// MARK: - Set row

private struct SetRow: View {
    let setNumber: Int
    let set: ActiveSessionViewModel.DraftSet
    let previousText: String
    let exerciseID: ActiveSessionViewModel.DraftExercise.ID
    let viewModel: ActiveSessionViewModel
    let onCompleted: () -> Void

    var body: some View {
        HStack {
            Text("\(setNumber)")
                .font(DesignSystem.Typography.headline)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .frame(width: 34, alignment: .leading)

            Text(previousText)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .frame(width: 76, alignment: .leading)
                .lineLimit(1)

            field(binding(\.weightText), placeholder: "0")
            field(binding(\.repsText), placeholder: "0")

            Button {
                let completed = withAnimation(.spring(duration: 0.3)) {
                    viewModel.toggleCompletion(setID: set.id, in: exerciseID)
                }
                if completed {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onCompleted()
                }
            } label: {
                Image(systemName: set.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(set.isCompleted
                                     ? DesignSystem.Colors.accent
                                     : DesignSystem.Colors.textSecondary.opacity(0.3))
                    .frame(width: 40, height: 40)
                    .scaleEffect(set.isCompleted ? 1.08 : 1)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, DesignSystem.Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                .fill(set.isCompleted ? DesignSystem.Colors.accent.opacity(0.08) : .clear)
        )
        .contextMenu {
            Button(role: .destructive) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.removeSet(set.id, from: exerciseID)
                }
            } label: {
                Label("Delete Set", systemImage: "trash")
            }
        }
    }

    private func field(_ binding: Binding<String>, placeholder: String) -> some View {
        TextField(placeholder, text: binding)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.center)
            .font(DesignSystem.Typography.headline)
            .foregroundStyle(DesignSystem.Colors.textPrimary)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(DesignSystem.Colors.background)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small))
            .disabled(set.isCompleted)
    }

    private func binding(_ keyPath: WritableKeyPath<ActiveSessionViewModel.DraftSet, String>) -> Binding<String> {
        Binding(
            get: {
                guard let e = viewModel.exercises.first(where: { $0.id == exerciseID }),
                      let s = e.sets.first(where: { $0.id == set.id })
                else { return "" }
                return s[keyPath: keyPath]
            },
            set: { newValue in
                guard let e = viewModel.exercises.firstIndex(where: { $0.id == exerciseID }),
                      let s = viewModel.exercises[e].sets.firstIndex(where: { $0.id == set.id })
                else { return }
                viewModel.exercises[e].sets[s][keyPath: keyPath] = newValue
            }
        )
    }
}

#Preview {
    ActiveSessionView(sessionName: "Push")
        .modelContainer(for: WorkoutSession.self, inMemory: true)
}
