//
//  ProfileEnums.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import Foundation

enum GoalType: String, Codable, CaseIterable {
    case fatLoss
    case maintain
    case muscleGain

    var displayName: String {
        switch self {
        case .fatLoss: "Fat Loss"
        case .maintain: "Maintain"
        case .muscleGain: "Muscle Gain"
        }
    }
}

enum UnitSystem: String, Codable, CaseIterable {
    case metric
    case imperial

    var displayName: String {
        switch self {
        case .metric: "Metric"
        case .imperial: "Imperial"
        }
    }
}

enum BiologicalSex: String, Codable, CaseIterable {
    case male
    case female

    var displayName: String {
        switch self {
        case .male: "Male"
        case .female: "Female"
        }
    }

    /// Mifflin-St Jeor sex constant.
    var mifflinConstant: Double {
        switch self {
        case .male: 5
        case .female: -161
        }
    }
}

enum ActivityLevel: String, Codable, CaseIterable {
    case sedentary
    case lightlyActive
    case moderatelyActive
    case veryActive
    case athlete

    var displayName: String {
        switch self {
        case .sedentary: "Sedentary"
        case .lightlyActive: "Lightly Active"
        case .moderatelyActive: "Moderately Active"
        case .veryActive: "Very Active"
        case .athlete: "Athlete"
        }
    }

    var detail: String {
        switch self {
        case .sedentary: "Little or no exercise"
        case .lightlyActive: "1–3 workouts a week"
        case .moderatelyActive: "3–5 workouts a week"
        case .veryActive: "6–7 workouts a week"
        case .athlete: "Physical job or twice-daily training"
        }
    }

    var multiplier: Double {
        switch self {
        case .sedentary: 1.2
        case .lightlyActive: 1.375
        case .moderatelyActive: 1.55
        case .veryActive: 1.725
        case .athlete: 1.9
        }
    }
}

enum TrainingSplit: String, Codable, CaseIterable {
    case upperLower
    case ppl
    case fullBody
    case custom

    var displayName: String {
        switch self {
        case .upperLower: "Upper / Lower"
        case .ppl: "Push Pull Legs"
        case .fullBody: "Full Body"
        case .custom: "Custom"
        }
    }

    var detail: String {
        switch self {
        case .upperLower: "Alternate upper- and lower-body days"
        case .ppl: "Push, pull, and leg days in rotation"
        case .fullBody: "Train the whole body each session"
        case .custom: "Build your own structure"
        }
    }
}
