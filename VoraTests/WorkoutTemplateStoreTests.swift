//
//  WorkoutTemplateStoreTests.swift
//  VoraTests
//
//  Created by Majd Arow on 2026-07-24.
//

import Foundation
import Testing
@testable import Vora

struct WorkoutTemplateStoreTests {
    private func makeDefaults() -> UserDefaults {
        let suite = "WorkoutTemplateStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    // MARK: - Defaults

    @Test func upperLowerHasDistinctAAndBDays() {
        let upperA = WorkoutTemplateStore.defaultTemplate(for: .upperLower, dayIndex: 0)
        let upperB = WorkoutTemplateStore.defaultTemplate(for: .upperLower, dayIndex: 3)
        #expect(upperA.first == "Barbell Bench Press")
        #expect(upperB.first == "Pull-Up")
        #expect(upperA != upperB)
    }

    @Test func pplRepeatsTemplatesAcrossTheWeek() {
        #expect(WorkoutTemplateStore.defaultTemplate(for: .ppl, dayIndex: 0)
                == WorkoutTemplateStore.defaultTemplate(for: .ppl, dayIndex: 3))
        #expect(WorkoutTemplateStore.defaultTemplate(for: .ppl, dayIndex: 2)
                == WorkoutTemplateStore.defaultTemplate(for: .ppl, dayIndex: 5))
    }

    @Test func fullBodyAlternatesAAndB() {
        let dayA = WorkoutTemplateStore.defaultTemplate(for: .fullBody, dayIndex: 0)
        let dayB = WorkoutTemplateStore.defaultTemplate(for: .fullBody, dayIndex: 2)
        #expect(dayA == WorkoutTemplateStore.defaultTemplate(for: .fullBody, dayIndex: 4))
        #expect(dayB.first == "Deadlift")
        #expect(dayA != dayB)
    }

    @Test func restDaysAndCustomSplitHaveNoDefaults() {
        #expect(WorkoutTemplateStore.defaultTemplate(for: .upperLower, dayIndex: 2).isEmpty)
        #expect(WorkoutTemplateStore.defaultTemplate(for: .ppl, dayIndex: 6).isEmpty)
        for day in 0..<7 {
            #expect(WorkoutTemplateStore.defaultTemplate(for: .custom, dayIndex: day).isEmpty)
        }
    }

    @Test func everyDefaultExerciseExistsInLibrary() {
        for split in TrainingSplit.allCases {
            for day in 0..<7 {
                for name in WorkoutTemplateStore.defaultTemplate(for: split, dayIndex: day) {
                    #expect(ExerciseLibrary.definition(named: name) != nil,
                            "\(name) missing from ExerciseLibrary")
                }
            }
        }
    }

    // MARK: - Overrides

    @Test func savedTemplateOverridesDefault() {
        let defaults = makeDefaults()
        let custom = ["Front Squat", "Walking Lunge"]
        WorkoutTemplateStore.saveTemplate(custom, for: .ppl, dayIndex: 2, defaults: defaults)
        #expect(WorkoutTemplateStore.template(for: .ppl, dayIndex: 2, defaults: defaults) == custom)
        #expect(WorkoutTemplateStore.isCustomized(for: .ppl, dayIndex: 2, defaults: defaults))
    }

    @Test func resetRestoresDefault() {
        let defaults = makeDefaults()
        WorkoutTemplateStore.saveTemplate(["Plank"], for: .ppl, dayIndex: 0, defaults: defaults)
        WorkoutTemplateStore.resetTemplate(for: .ppl, dayIndex: 0, defaults: defaults)
        #expect(WorkoutTemplateStore.template(for: .ppl, dayIndex: 0, defaults: defaults)
                == WorkoutTemplateStore.defaultTemplate(for: .ppl, dayIndex: 0))
        #expect(!WorkoutTemplateStore.isCustomized(for: .ppl, dayIndex: 0, defaults: defaults))
    }

    @Test func overridesAreIsolatedPerSplitAndDay() {
        let defaults = makeDefaults()
        WorkoutTemplateStore.saveTemplate(["Plank"], for: .ppl, dayIndex: 0, defaults: defaults)
        #expect(WorkoutTemplateStore.template(for: .ppl, dayIndex: 3, defaults: defaults)
                == WorkoutTemplateStore.defaultTemplate(for: .ppl, dayIndex: 3))
        #expect(WorkoutTemplateStore.template(for: .upperLower, dayIndex: 0, defaults: defaults)
                == WorkoutTemplateStore.defaultTemplate(for: .upperLower, dayIndex: 0))
    }

    @Test func emptyTemplateIsAValidOverride() {
        let defaults = makeDefaults()
        WorkoutTemplateStore.saveTemplate([], for: .fullBody, dayIndex: 0, defaults: defaults)
        #expect(WorkoutTemplateStore.template(for: .fullBody, dayIndex: 0, defaults: defaults).isEmpty)
        #expect(WorkoutTemplateStore.isCustomized(for: .fullBody, dayIndex: 0, defaults: defaults))
    }
}
