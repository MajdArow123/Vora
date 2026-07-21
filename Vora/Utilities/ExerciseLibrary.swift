//
//  ExerciseLibrary.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import Foundation

enum ExerciseLibrary {
    static let all: [ExerciseDefinition] = [
        // Chest
        .init(name: "Barbell Bench Press", muscleGroup: .chest, equipment: .barbell),
        .init(name: "Incline Barbell Press", muscleGroup: .chest, equipment: .barbell),
        .init(name: "Dumbbell Bench Press", muscleGroup: .chest, equipment: .dumbbell),
        .init(name: "Incline Dumbbell Press", muscleGroup: .chest, equipment: .dumbbell),
        .init(name: "Dumbbell Fly", muscleGroup: .chest, equipment: .dumbbell),
        .init(name: "Cable Crossover", muscleGroup: .chest, equipment: .cable),
        .init(name: "Machine Chest Press", muscleGroup: .chest, equipment: .machine),
        .init(name: "Push-Up", muscleGroup: .chest, equipment: .bodyweight),
        .init(name: "Dip", muscleGroup: .chest, equipment: .bodyweight),
        // Back
        .init(name: "Deadlift", muscleGroup: .back, equipment: .barbell),
        .init(name: "Barbell Row", muscleGroup: .back, equipment: .barbell),
        .init(name: "T-Bar Row", muscleGroup: .back, equipment: .barbell),
        .init(name: "Dumbbell Row", muscleGroup: .back, equipment: .dumbbell),
        .init(name: "Pull-Up", muscleGroup: .back, equipment: .bodyweight),
        .init(name: "Chin-Up", muscleGroup: .back, equipment: .bodyweight),
        .init(name: "Lat Pulldown", muscleGroup: .back, equipment: .cable),
        .init(name: "Seated Cable Row", muscleGroup: .back, equipment: .cable),
        .init(name: "Face Pull", muscleGroup: .back, equipment: .cable),
        .init(name: "Machine Row", muscleGroup: .back, equipment: .machine),
        // Shoulders
        .init(name: "Overhead Press", muscleGroup: .shoulders, equipment: .barbell),
        .init(name: "Dumbbell Shoulder Press", muscleGroup: .shoulders, equipment: .dumbbell),
        .init(name: "Arnold Press", muscleGroup: .shoulders, equipment: .dumbbell),
        .init(name: "Lateral Raise", muscleGroup: .shoulders, equipment: .dumbbell),
        .init(name: "Front Raise", muscleGroup: .shoulders, equipment: .dumbbell),
        .init(name: "Rear Delt Fly", muscleGroup: .shoulders, equipment: .dumbbell),
        .init(name: "Cable Lateral Raise", muscleGroup: .shoulders, equipment: .cable),
        .init(name: "Machine Shoulder Press", muscleGroup: .shoulders, equipment: .machine),
        // Biceps
        .init(name: "Barbell Curl", muscleGroup: .biceps, equipment: .barbell),
        .init(name: "Preacher Curl", muscleGroup: .biceps, equipment: .barbell),
        .init(name: "Dumbbell Curl", muscleGroup: .biceps, equipment: .dumbbell),
        .init(name: "Hammer Curl", muscleGroup: .biceps, equipment: .dumbbell),
        .init(name: "Incline Dumbbell Curl", muscleGroup: .biceps, equipment: .dumbbell),
        .init(name: "Cable Curl", muscleGroup: .biceps, equipment: .cable),
        // Triceps
        .init(name: "Close-Grip Bench Press", muscleGroup: .triceps, equipment: .barbell),
        .init(name: "Skull Crusher", muscleGroup: .triceps, equipment: .barbell),
        .init(name: "Overhead Triceps Extension", muscleGroup: .triceps, equipment: .dumbbell),
        .init(name: "Triceps Kickback", muscleGroup: .triceps, equipment: .dumbbell),
        .init(name: "Triceps Pushdown", muscleGroup: .triceps, equipment: .cable),
        .init(name: "Bench Dip", muscleGroup: .triceps, equipment: .bodyweight),
        // Quads
        .init(name: "Back Squat", muscleGroup: .quads, equipment: .barbell),
        .init(name: "Front Squat", muscleGroup: .quads, equipment: .barbell),
        .init(name: "Bulgarian Split Squat", muscleGroup: .quads, equipment: .dumbbell),
        .init(name: "Walking Lunge", muscleGroup: .quads, equipment: .dumbbell),
        .init(name: "Goblet Squat", muscleGroup: .quads, equipment: .kettlebell),
        .init(name: "Leg Press", muscleGroup: .quads, equipment: .machine),
        .init(name: "Leg Extension", muscleGroup: .quads, equipment: .machine),
        .init(name: "Hack Squat", muscleGroup: .quads, equipment: .machine),
        // Hamstrings
        .init(name: "Romanian Deadlift", muscleGroup: .hamstrings, equipment: .barbell),
        .init(name: "Good Morning", muscleGroup: .hamstrings, equipment: .barbell),
        .init(name: "Lying Leg Curl", muscleGroup: .hamstrings, equipment: .machine),
        .init(name: "Seated Leg Curl", muscleGroup: .hamstrings, equipment: .machine),
        .init(name: "Nordic Curl", muscleGroup: .hamstrings, equipment: .bodyweight),
        // Glutes
        .init(name: "Hip Thrust", muscleGroup: .glutes, equipment: .barbell),
        .init(name: "Glute Bridge", muscleGroup: .glutes, equipment: .bodyweight),
        .init(name: "Cable Kickback", muscleGroup: .glutes, equipment: .cable),
        .init(name: "Kettlebell Swing", muscleGroup: .glutes, equipment: .kettlebell),
        // Calves
        .init(name: "Standing Calf Raise", muscleGroup: .calves, equipment: .machine),
        .init(name: "Seated Calf Raise", muscleGroup: .calves, equipment: .machine),
        .init(name: "Single-Leg Calf Raise", muscleGroup: .calves, equipment: .bodyweight),
        // Core
        .init(name: "Plank", muscleGroup: .core, equipment: .bodyweight),
        .init(name: "Crunch", muscleGroup: .core, equipment: .bodyweight),
        .init(name: "Hanging Leg Raise", muscleGroup: .core, equipment: .bodyweight),
        .init(name: "Ab Wheel Rollout", muscleGroup: .core, equipment: .bodyweight),
        .init(name: "Cable Crunch", muscleGroup: .core, equipment: .cable),
        .init(name: "Russian Twist", muscleGroup: .core, equipment: .bodyweight),
    ]

    static func filtered(
        query: String,
        muscleGroup: MuscleGroup?,
        equipment: Equipment?
    ) -> [ExerciseDefinition] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        return all.filter { exercise in
            (trimmed.isEmpty || exercise.name.localizedCaseInsensitiveContains(trimmed))
                && (muscleGroup == nil || exercise.muscleGroup == muscleGroup)
                && (equipment == nil || exercise.equipment == equipment)
        }
    }
}
