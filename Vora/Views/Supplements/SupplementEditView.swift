//
//  SupplementEditView.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-26.
//

import SwiftUI
import SwiftData

/// Add / edit form for one supplement. Passing nil creates a new one and
/// shows the quick-add suggestions.
struct SupplementEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let supplement: Supplement?

    @State private var name: String
    @State private var dose: String
    @State private var timing: SupplementTiming
    @State private var reminderEnabled: Bool
    @State private var reminderMinutes: Int
    /// Once the user picks a time themselves, changing the timing no
    /// longer re-seeds it.
    @State private var userAdjustedTime: Bool

    private static let quickAdds: [(name: String, dose: String)] = [
        ("Creatine", "5g"),
        ("Whey Protein", "1 scoop"),
        ("Vitamin D", "2000IU"),
        ("Omega-3", "1g"),
        ("Magnesium", "400mg"),
        ("Zinc", "25mg"),
        ("Pre-workout", "1 scoop"),
        ("Caffeine", "200mg"),
    ]

    private let chipColumns = [GridItem(.adaptive(minimum: 104), spacing: 8)]

    init(supplement: Supplement?) {
        self.supplement = supplement
        _name = State(initialValue: supplement?.name ?? "")
        _dose = State(initialValue: supplement?.dose ?? "")
        _timing = State(initialValue: supplement?.timing ?? .anytime)
        _reminderEnabled = State(initialValue: supplement?.reminderEnabled ?? false)
        _reminderMinutes = State(initialValue: supplement?.reminderMinutes ?? SupplementTiming.anytime.defaultReminderMinutes)
        _userAdjustedTime = State(initialValue: supplement != nil)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.Colors.background
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                        if supplement == nil {
                            quickAddSection
                        }

                        fieldsCard

                        timingSection

                        reminderCard

                        PrimaryButton(title: "Save") {
                            save()
                            dismiss()
                        }
                        .disabled(!canSave)
                    }
                    .padding(DesignSystem.Spacing.lg)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(supplement == nil ? "Add Supplement" : "Edit Supplement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
            }
        }
    }

    // MARK: - Quick add

    private var quickAddSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text("Quick add")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .textCase(.uppercase)

            LazyVGrid(columns: chipColumns, alignment: .leading, spacing: 8) {
                ForEach(Self.quickAdds, id: \.name) { suggestion in
                    let isSelected = name == suggestion.name && dose == suggestion.dose
                    Button {
                        name = suggestion.name
                        dose = suggestion.dose
                    } label: {
                        VStack(spacing: 2) {
                            Text(suggestion.name)
                                .font(DesignSystem.Typography.caption)
                                .fontWeight(.semibold)
                            Text(suggestion.dose)
                                .font(DesignSystem.Typography.caption)
                                .opacity(0.7)
                        }
                        .foregroundStyle(isSelected ? .white : DesignSystem.Colors.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DesignSystem.Spacing.sm)
                        .background(isSelected ? DesignSystem.Colors.accent : DesignSystem.Colors.card)
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(suggestion.name), \(suggestion.dose)")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
    }

    // MARK: - Fields

    private var fieldsCard: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            HStack(spacing: DesignSystem.Spacing.sm) {
                Text("Name")
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Spacer()
                TextField("e.g. Creatine", text: $name)
                    .multilineTextAlignment(.trailing)
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                    .accessibilityLabel("Supplement name")
            }
            .frame(minHeight: 32)

            Divider()

            HStack(spacing: DesignSystem.Spacing.sm) {
                Text("Dose")
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Spacer()
                TextField("e.g. 5g, 1 capsule, 10ml", text: $dose)
                    .multilineTextAlignment(.trailing)
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                    .accessibilityLabel("Dose")
            }
            .frame(minHeight: 32)
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
    }

    // MARK: - Timing

    private var timingSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text("Timing")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .textCase(.uppercase)

            ForEach(SupplementTiming.allCases) { option in
                timingCard(option)
            }
        }
    }

    private func timingCard(_ option: SupplementTiming) -> some View {
        let isSelected = timing == option
        return Button {
            timing = option
            if !userAdjustedTime {
                reminderMinutes = option.defaultReminderMinutes
            }
        } label: {
            HStack(spacing: DesignSystem.Spacing.md) {
                Image(systemName: option.iconName)
                    .font(.title3)
                    .foregroundStyle(DesignSystem.Colors.accent)
                    .frame(width: 32)
                    .accessibilityHidden(true)

                Text(option.displayName)
                    .font(DesignSystem.Typography.headline)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected
                                     ? DesignSystem.Colors.accent
                                     : DesignSystem.Colors.textPrimary.opacity(0.2))
                    .accessibilityHidden(true)
            }
            .padding(DesignSystem.Spacing.md)
            .background(DesignSystem.Colors.card)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                    .strokeBorder(isSelected ? DesignSystem.Colors.accent : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Reminder

    private var reminderCard: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            Toggle(isOn: $reminderEnabled) {
                Text("Daily reminder")
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
            }
            .tint(DesignSystem.Colors.accent)
            .frame(minHeight: 44)

            if reminderEnabled {
                HStack {
                    Text("Time")
                        .font(DesignSystem.Typography.body)
                        .foregroundStyle(DesignSystem.Colors.textPrimary.opacity(0.6))
                    Spacer()
                    DatePicker(
                        "Reminder time",
                        selection: timeBinding,
                        displayedComponents: .hourAndMinute
                    )
                    .labelsHidden()
                }
                .frame(minHeight: 44)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: reminderEnabled)
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
    }

    private var timeBinding: Binding<Date> {
        Binding {
            Calendar.current.date(
                bySettingHour: reminderMinutes / 60,
                minute: reminderMinutes % 60,
                second: 0,
                of: .now
            ) ?? .now
        } set: { newValue in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            reminderMinutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            userAdjustedTime = true
        }
    }

    // MARK: - Saving

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedDose = dose.trimmingCharacters(in: .whitespaces)

        if let supplement {
            supplement.name = trimmedName
            supplement.dose = trimmedDose
            supplement.timing = timing
            supplement.reminderEnabled = reminderEnabled
            supplement.reminderMinutes = reminderMinutes
        } else {
            let maxOrder = ((try? modelContext.fetch(FetchDescriptor<Supplement>())) ?? [])
                .map(\.orderIndex)
                .max() ?? -1
            modelContext.insert(Supplement(
                name: trimmedName,
                dose: trimmedDose,
                timing: timing,
                reminderEnabled: reminderEnabled,
                reminderMinutes: reminderMinutes,
                orderIndex: maxOrder + 1
            ))
        }
        try? modelContext.save()
        NotificationService.shared.refreshAll(context: modelContext)
    }
}

#Preview("Add") {
    SupplementEditView(supplement: nil)
        .modelContainer(for: [Supplement.self, SupplementLog.self], inMemory: true)
}
