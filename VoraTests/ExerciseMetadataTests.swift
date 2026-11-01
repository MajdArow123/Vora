//
//  ExerciseMetadataTests.swift
//  VoraTests
//
//  Created by Majd Arow on 2026-08-10.
//

import Foundation
import Testing
@testable import Vora

struct ExerciseMetadataTests {
    @Test func everyLibraryExerciseHasAtLeastOnePrimaryMuscle() {
        for exercise in ExerciseLibrary.all {
            #expect(!exercise.primaryMuscles.isEmpty,
                    "\(exercise.name) has no primary muscles")
        }
    }

    @Test func everyLibraryExerciseHasTwoToFourCues() {
        for exercise in ExerciseLibrary.all {
            #expect((2...4).contains(exercise.techniqueCues.count),
                    "\(exercise.name) has \(exercise.techniqueCues.count) cues")
        }
    }

    @Test func cuesAreNonEmptyText() {
        for exercise in ExerciseLibrary.all {
            for cue in exercise.techniqueCues {
                #expect(!cue.trimmingCharacters(in: .whitespaces).isEmpty,
                        "\(exercise.name) has a blank cue")
            }
        }
    }

    @Test func primaryAndSecondaryMusclesNeverOverlap() {
        for exercise in ExerciseLibrary.all {
            let overlap = exercise.primaryMuscles.intersection(exercise.secondaryMuscles)
            #expect(overlap.isEmpty,
                    "\(exercise.name) lists \(overlap.map(\.rawValue)) as both primary and secondary")
        }
    }

    @Test func everyMuscleIsMappedToADiagramRegion() {
        let mapped = BodyDiagramLayout.mappedMuscles
        for muscle in Muscle.allCases {
            #expect(mapped.contains(muscle),
                    "\(muscle.rawValue) has no diagram region")
        }
    }

    @Test func frontOnlyMusclesAppearOnlyOnFrontFigure() {
        let front = Set(BodyDiagramLayout.frontRegions.compactMap(\.muscle))
        let back = Set(BodyDiagramLayout.backRegions.compactMap(\.muscle))
        let frontOnly: Set<Muscle> = [.chest, .frontDelts, .sideDelts, .biceps,
                                      .forearms, .abs, .obliques, .quads]
        let backOnly: Set<Muscle> = [.rearDelts, .traps, .lats, .upperBack,
                                     .lowerBack, .triceps, .glutes, .hamstrings]
        #expect(front.intersection(backOnly).isEmpty)
        #expect(back.intersection(frontOnly).isEmpty)
        #expect(front.contains(.calves) && back.contains(.calves))
    }

    @Test func libraryExerciseContentResolvesMetadata() {
        let content = ExerciseDetailContent(exerciseName: "Barbell Bench Press")
        #expect(content.hasMuscleData)
        #expect(content.primaryMuscles == [.chest])
        #expect(content.secondaryMuscles == [.frontDelts, .triceps])
        #expect(!content.techniqueCues.isEmpty)
        #expect(!content.equipment.isEmpty)
    }

    @Test func customExerciseContentFallsBackToEmptyState() {
        let content = ExerciseDetailContent(exerciseName: "Weighted Yeti Carry")
        #expect(!content.hasMuscleData)
        #expect(content.primaryMuscles.isEmpty)
        #expect(content.secondaryMuscles.isEmpty)
        #expect(content.techniqueCues.isEmpty)
        #expect(content.equipment.isEmpty)
    }

    @Test func detailContentLookupIsCaseInsensitive() {
        let content = ExerciseDetailContent(exerciseName: "barbell bench press")
        #expect(content.hasMuscleData)
    }
}
