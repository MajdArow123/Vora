//
//  TemplateEditorView.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-24.
//

import SwiftUI

/// Edits the default exercise list for one split day. Changes apply to
/// future sessions only; Close abandons edits, Save persists them via
/// WorkoutTemplateStore.
struct TemplateEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let split: TrainingSplit
    let dayIndex: Int
    let dayTitle: String

    @State private var names: [String]
    @State private var showingExercisePicker = false

    init(split: TrainingSplit, dayIndex: Int, dayTitle: String) {
        self.split = split
        self.dayIndex = dayIndex
        self.dayTitle = dayTitle
        _names = State(initialValue: WorkoutTemplateStore.template(for: split, dayIndex: dayIndex))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.Colors.background
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    List {
                        if names.isEmpty {
                            Text("No exercises yet. Add some below.")
                                .font(DesignSystem.Typography.caption)
                                .foregroundStyle(DesignSystem.Colors.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, DesignSystem.Spacing.sm)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }

                        ForEach(names, id: \.self) { name in
                            exerciseRow(name)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(rowInsets)
                        }
                        .onDelete { names.remove(atOffsets: $0) }
                        .onMove { names.move(fromOffsets: $0, toOffset: $1) }

                        Button {
                            showingExercisePicker = true
                        } label: {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                    .accessibilityHidden(true)
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
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(rowInsets)

                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                names = WorkoutTemplateStore.defaultTemplate(for: split, dayIndex: dayIndex)
                            }
                        } label: {
                            Text("Reset to Default")
                                .font(DesignSystem.Typography.caption)
                                .foregroundStyle(DesignSystem.Colors.textSecondary)
                                .frame(maxWidth: .infinity)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(rowInsets)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .environment(\.editMode, .constant(.active))

                    PrimaryButton(title: "Save Template") {
                        WorkoutTemplateStore.saveTemplate(names, for: split, dayIndex: dayIndex)
                        dismiss()
                    }
                    .padding(DesignSystem.Spacing.lg)
                }
            }
            .navigationTitle("\(dayTitle) Template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
            }
        }
        .sheet(isPresented: $showingExercisePicker) {
            ExercisePickerView { name, _ in
                if !names.contains(name) {
                    names.append(name)
                }
            }
        }
    }

    private var rowInsets: EdgeInsets {
        EdgeInsets(
            top: DesignSystem.Spacing.xs,
            leading: DesignSystem.Spacing.lg,
            bottom: DesignSystem.Spacing.xs,
            trailing: DesignSystem.Spacing.lg
        )
    }

    private func exerciseRow(_ name: String) -> some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            Text(name)
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
            Spacer()
            if let group = ExerciseLibrary.definition(named: name)?.muscleGroup {
                Text(group.displayName)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.accent)
                    .padding(.horizontal, DesignSystem.Spacing.sm)
                    .padding(.vertical, 4)
                    .background(DesignSystem.Colors.accent.opacity(0.12))
                    .clipShape(Capsule())
            }
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
    }
}

#Preview {
    TemplateEditorView(split: .ppl, dayIndex: 0, dayTitle: "Push")
}
