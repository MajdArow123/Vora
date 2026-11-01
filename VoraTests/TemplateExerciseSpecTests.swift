//
//  TemplateExerciseSpecTests.swift
//  VoraTests
//
//  Created by Majd Arow on 2026-11-01.
//

import Foundation
import SwiftData
import Testing
@testable import Vora

struct TemplateExerciseSpecTests {
    // MARK: - Defaults

    @Test func libraryExerciseDefaults() {
        let bench = TemplateExerciseSpec(exerciseId: "barbell-bench-press")
        #expect(bench.targetSets == 3)
        #expect(bench.repRange == 8...12)
        #expect(bench.targetRIR == 2)
        #expect(bench.restSeconds == 120)
        #expect(TemplateExerciseSpec(exerciseId: "lateral-raise").restSeconds == 90)
    }

    @Test func customExerciseDefaultsToIsolationRest() {
        let sled = TemplateExerciseSpec(exerciseId: nil, customName: "Sled Push")
        #expect(sled.restSeconds == 90)
        #expect(sled.displayName == "Sled Push")
    }

    @Test func libraryExercisesNeverKeepACustomName() {
        let spec = TemplateExerciseSpec(exerciseId: "dip", customName: "My Dip")
        #expect(spec.customName == nil)
        #expect(spec.displayName == "Dip")
    }

    @Test @MainActor func modelDefaultsMatchSpecDefaults() {
        let row = TemplateExercise(exerciseId: "back-squat", orderIndex: 0)
        let spec = TemplateExerciseSpec(row)
        #expect(spec == TemplateExerciseSpec(id: row.id, exerciseId: "back-squat"))
        #expect(row.displayName == "Back Squat")
    }

    // MARK: - Picked names

    @Test func pickedLibraryNameBecomesAnID() {
        let spec = TemplateExerciseSpec(pickedName: "barbell bench press")
        #expect(spec.exerciseId == "barbell-bench-press")
        #expect(spec.customName == nil)
    }

    @Test func pickedUnknownNameBecomesCustom() {
        let spec = TemplateExerciseSpec(pickedName: "  Sled Push ")
        #expect(spec.exerciseId == nil)
        #expect(spec.customName == "Sled Push")
    }

    @Test func identityKeyMatchesAcrossLibraryAndLegacyCustomNames() {
        let library = TemplateExerciseSpec(exerciseId: "barbell-bench-press")
        let legacy = TemplateExerciseSpec(exerciseId: nil, customName: "Bench Press")
        let custom = TemplateExerciseSpec(exerciseId: nil, customName: "Sled Push")
        #expect(library.identityKey == legacy.identityKey)
        #expect(custom.identityKey == ExerciseIdentity.customPrefix + "sled push")
    }

    @Test func unknownIDFallsBackToTheIDForDisplay() {
        #expect(TemplateExerciseSpec.displayName(exerciseId: "retired-move", customName: nil) == "retired-move")
    }

    // MARK: - Clamping

    @Test func clampingForcesEveryTargetIntoLimits() {
        let low = TemplateExerciseSpec(
            exerciseId: "dip", targetSets: 0, repRangeMin: -3, repRangeMax: 0, targetRIR: -1, restSeconds: 0
        ).clamped()
        #expect(low.targetSets == 1)
        #expect(low.repRange == 1...1)
        #expect(low.targetRIR == 0)
        #expect(low.restSeconds == 30)

        let high = TemplateExerciseSpec(
            exerciseId: "dip", targetSets: 11, repRangeMin: 60, repRangeMax: 70, targetRIR: 6, restSeconds: 601
        ).clamped()
        #expect(high.targetSets == 10)
        #expect(high.repRange == 50...50)
        #expect(high.targetRIR == 5)
        #expect(high.restSeconds == 600)
    }

    @Test func clampingOrdersTheRepRangeAndSnapsRest() {
        let spec = TemplateExerciseSpec(
            exerciseId: "dip", repRangeMin: 12, repRangeMax: 8, targetRIR: nil, restSeconds: 128
        ).clamped()
        #expect(spec.repRange == 12...12)
        #expect(spec.targetRIR == nil)
        #expect(spec.restSeconds == 135)
    }

    @Test func clampingLeavesValidSpecsUnchanged() {
        let spec = TemplateExerciseSpec(exerciseId: "dip", targetSets: 4, repRangeMin: 6, repRangeMax: 10, restSeconds: 180)
        #expect(spec.clamped() == spec)
    }
}
