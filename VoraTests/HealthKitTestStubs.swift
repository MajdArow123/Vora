//
//  HealthKitTestStubs.swift
//  VoraTests
//
//  Created by Majd Arow on 2026-11-02.
//

import Foundation
@testable import Vora

/// For tests that build a view model but don't care about HealthKit writes.
final class NoHealthWrites: HealthWorkoutWriting {
    func saveStrengthWorkout(start: Date, end: Date) async -> UUID? { nil }
    func saveCardioWorkout(type: CardioType, start: Date, end: Date, calories: Double) async -> UUID? { nil }
}
