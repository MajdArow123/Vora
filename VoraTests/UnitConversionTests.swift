//
//  UnitConversionTests.swift
//  VoraTests
//
//  Created by Majd Arow on 2026-07-21.
//

import Foundation
import Testing
@testable import Vora

struct UnitConversionTests {
    // MARK: - Weight

    @Test func kilogramsToPounds() {
        #expect(abs(UnitConversion.pounds(fromKg: 100) - 220.462) < 0.0001)
        #expect(abs(UnitConversion.pounds(fromKg: 1) - 2.20462) < 0.0001)
        #expect(UnitConversion.pounds(fromKg: 0) == 0)
    }

    @Test func poundsToKilograms() {
        #expect(abs(UnitConversion.kg(fromPounds: 220.462) - 100) < 0.0001)
        #expect(abs(UnitConversion.kg(fromPounds: 2.20462) - 1) < 0.0001)
    }

    @Test(arguments: [0.5, 62.3, 80.0, 152.75])
    func weightRoundTripIsLossless(kg: Double) {
        let roundTripped = UnitConversion.kg(fromPounds: UnitConversion.pounds(fromKg: kg))
        #expect(abs(roundTripped - kg) < 1e-9)
    }

    // MARK: - Height

    @Test func cmToFeetAndInches() {
        // 180 cm = 70.87 in -> rounds to 71 -> 5 ft 11 in.
        let tall = UnitConversion.feetAndInches(fromCm: 180)
        #expect(tall.feet == 5)
        #expect(tall.inches == 11)

        // Exactly 6 ft.
        let exact = UnitConversion.feetAndInches(fromCm: 182.88)
        #expect(exact.feet == 6)
        #expect(exact.inches == 0)
    }

    @Test func feetAndInchesToCm() {
        #expect(abs(UnitConversion.cm(fromFeet: 6, inches: 0) - 182.88) < 0.0001)
        #expect(abs(UnitConversion.cm(fromFeet: 5, inches: 7) - 170.18) < 0.0001)
        #expect(UnitConversion.cm(fromFeet: 0, inches: 0) == 0)
    }

    /// Feet/inches -> cm -> feet/inches must be the identity for every
    /// realistic height, since cm is stored as an exact inch multiple.
    @Test func imperialHeightRoundTripIsIdentity() {
        for feet in 4...7 {
            for inches in 0...11 {
                let cm = UnitConversion.cm(fromFeet: feet, inches: inches)
                let back = UnitConversion.feetAndInches(fromCm: cm)
                #expect(back.feet == feet, "\(feet) ft \(inches) in")
                #expect(back.inches == inches, "\(feet) ft \(inches) in")
            }
        }
    }

    // MARK: - Formatting

    @Test func heightTextMetricRoundsToWholeCentimetres() {
        #expect(UnitConversion.heightText(cm: 179.6, units: .metric) == "180 cm")
        #expect(UnitConversion.heightText(cm: 179.4, units: .metric) == "179 cm")
    }

    @Test func heightTextImperialUsesFeetAndInches() {
        #expect(UnitConversion.heightText(cm: 180, units: .imperial) == "5 ft 11 in")
        #expect(UnitConversion.heightText(cm: 182.88, units: .imperial) == "6 ft 0 in")
    }

    @Test func weightTextMetricRoundsToWholeKilograms() {
        #expect(UnitConversion.weightText(kg: 80.4, units: .metric) == "80 kg")
        #expect(UnitConversion.weightText(kg: 80.5, units: .metric) == "81 kg")
    }

    @Test func weightTextImperialRoundsToWholePounds() {
        // 80 kg = 176.37 lb.
        #expect(UnitConversion.weightText(kg: 80, units: .imperial) == "176 lb")
        // 100 kg = 220.46 lb.
        #expect(UnitConversion.weightText(kg: 100, units: .imperial) == "220 lb")
    }
}
