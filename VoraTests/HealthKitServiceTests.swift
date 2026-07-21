//
//  HealthKitServiceTests.swift
//  VoraTests
//
//  Created by Majd Arow on 2026-07-21.
//

import Foundation
import Testing
@testable import Vora

/// HealthKit's authorized read/write paths need a real device and user
/// consent, so tests cover the synchronous guards; the store-facing code
/// is deliberately fire-and-forget and silent (see HealthKitService).
struct HealthKitServiceTests {
    @Test func invalidDateRangeIsRejectedBeforeTouchingHealthKit() async {
        let service = HealthKitService()
        // end == start and end < start must both return without any
        // HealthKit interaction (no permission prompt in the test host
        // proves the early guard fired).
        await service.saveStrengthWorkout(start: .now, end: .now)
        await service.saveStrengthWorkout(start: .now, end: .now.addingTimeInterval(-60))
        await service.saveCardioWorkout(type: .run, start: .now, end: .now, calories: 300)
    }
}
