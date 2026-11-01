//
//  ExerciseMechanicsTests.swift
//  VoraTests
//
//  Created by Majd Arow on 2026-11-01.
//

import Foundation
import Testing
@testable import Vora

struct ExerciseMechanicsTests {
    /// Pinned so a changed classification (which changes default rest) is
    /// a deliberate edit.
    private static let compoundIDs: Set<String> = [
        "barbell-bench-press", "incline-barbell-press", "dumbbell-bench-press",
        "incline-dumbbell-press", "machine-chest-press", "push-up", "dip",
        "deadlift", "barbell-row", "t-bar-row", "dumbbell-row", "pull-up",
        "chin-up", "lat-pulldown", "seated-cable-row", "machine-row",
        "overhead-press", "dumbbell-shoulder-press", "arnold-press",
        "machine-shoulder-press", "close-grip-bench-press", "bench-dip",
        "back-squat", "front-squat", "bulgarian-split-squat", "walking-lunge",
        "goblet-squat", "leg-press", "hack-squat", "romanian-deadlift",
        "good-morning", "hip-thrust", "kettlebell-swing",
    ]

    @Test func compoundClassificationIsPinned() {
        let compounds = Set(ExerciseLibrary.all.filter { $0.mechanics == .compound }.map(\.id))
        #expect(compounds == Self.compoundIDs)
    }

    @Test func defaultRestFollowsMechanics() {
        for exercise in ExerciseLibrary.all {
            let expected = exercise.mechanics == .compound
                ? ExerciseLibrary.compoundRestSeconds
                : ExerciseLibrary.isolationRestSeconds
            #expect(ExerciseLibrary.defaultRestSeconds(exerciseId: exercise.id) == expected, "\(exercise.id)")
        }
        #expect(ExerciseLibrary.compoundRestSeconds == 120)
        #expect(ExerciseLibrary.isolationRestSeconds == 90)
    }

    @Test func customAndUnknownExercisesGetIsolationRest() {
        #expect(ExerciseLibrary.defaultRestSeconds(exerciseId: nil) == 90)
        #expect(ExerciseLibrary.defaultRestSeconds(exerciseId: "not-in-library") == 90)
    }

    // MARK: - Legacy-only entries

    @Test func onlyGenericLegCurlIsLegacyOnly() {
        #expect(ExerciseLibrary.all.filter(\.isLegacyOnly).map(\.id) == ["leg-curl"])
    }

    @Test func legacyOnlyExercisesAreHiddenFromThePicker() {
        let all = ExerciseLibrary.filtered(query: "", muscleGroup: nil, equipment: nil)
        #expect(!all.contains { $0.id == "leg-curl" })
        #expect(all.count == ExerciseLibrary.all.count - 1)

        let curls = ExerciseLibrary.filtered(query: "leg curl", muscleGroup: .hamstrings, equipment: nil)
        #expect(curls.map(\.id) == ["lying-leg-curl", "seated-leg-curl"])
    }

    @Test func legacyOnlyExercisesStillResolveForHistory() {
        #expect(ExerciseLibrary.definition(id: "leg-curl")?.name == "Leg Curl")
        #expect(ExerciseLibrary.definition(named: "leg curl")?.id == "leg-curl")
        #expect(ExerciseLibrary.legacyDefinition(lowercasedName: "leg curl")?.id == "leg-curl")
        #expect(ExerciseIdentity.key(exerciseId: nil, name: "Leg Curl") == "leg-curl")
    }
}
