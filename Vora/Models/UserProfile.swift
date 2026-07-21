//
//  UserProfile.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import Foundation
import SwiftData

enum GoalType: String, Codable, CaseIterable {
    case fatLoss
    case maintain
    case muscleGain
}

enum UnitSystem: String, Codable, CaseIterable {
    case metric
    case imperial
}

extension GoalType {
    var displayName: String {
        switch self {
        case .fatLoss: "Fat Loss"
        case .maintain: "Maintain"
        case .muscleGain: "Muscle Gain"
        }
    }
}

extension UnitSystem {
    var displayName: String {
        switch self {
        case .metric: "Metric"
        case .imperial: "Imperial"
        }
    }
}

@Model
final class UserProfile {
    var name: String
    var dateOfBirth: Date
    var heightCm: Double
    var goalType: GoalType
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
        goalType: GoalType,
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
        self.goalType = goalType
        self.dailyCalorieTarget = dailyCalorieTarget
        self.proteinTargetG = proteinTargetG
        self.carbsTargetG = carbsTargetG
        self.fatTargetG = fatTargetG
        self.waterTargetMl = waterTargetMl
        self.preferredUnits = preferredUnits
    }
}
