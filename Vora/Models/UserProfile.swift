//
//  UserProfile.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import Foundation
import SwiftData

@Model
final class UserProfile {
    var name: String
    var dateOfBirth: Date
    var heightCm: Double
    var biologicalSex: BiologicalSex = BiologicalSex.male
    var goalType: GoalType
    var activityLevel: ActivityLevel = ActivityLevel.moderatelyActive
    var trainingSplit: TrainingSplit = TrainingSplit.fullBody
    var dailyCalorieTarget: Int
    var proteinTargetG: Int
    var carbsTargetG: Int
    var fatTargetG: Int
    var waterTargetMl: Double
    var preferredUnits: UnitSystem

    init(
        name: String,
        dateOfBirth: Date,
        heightCm: Double,
        biologicalSex: BiologicalSex,
        goalType: GoalType,
        activityLevel: ActivityLevel,
        trainingSplit: TrainingSplit,
        dailyCalorieTarget: Int,
        proteinTargetG: Int,
        carbsTargetG: Int,
        fatTargetG: Int,
        waterTargetMl: Double = 3500,
        preferredUnits: UnitSystem = .metric
    ) {
        self.name = name
        self.dateOfBirth = dateOfBirth
        self.heightCm = heightCm
        self.biologicalSex = biologicalSex
        self.goalType = goalType
        self.activityLevel = activityLevel
        self.trainingSplit = trainingSplit
        self.dailyCalorieTarget = dailyCalorieTarget
        self.proteinTargetG = proteinTargetG
        self.carbsTargetG = carbsTargetG
        self.fatTargetG = fatTargetG
        self.waterTargetMl = waterTargetMl
        self.preferredUnits = preferredUnits
    }
}
