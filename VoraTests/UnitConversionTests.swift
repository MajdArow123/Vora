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
    // MARK: - Body weight

    @Test func bodyWeightTextUsesOneDecimalInTheUsersUnit() {
        #expect(UnitConversion.bodyWeightText(kg: 80.44, units: .metric) == "80.4 kg")
        #expect(UnitConversion.bodyWeightText(kg: 80, units: .imperial) == "176.4 lb")
    }

    @Test func bodyWeightChangeTextIsSignedAndConverted() {
        #expect(UnitConversion.bodyWeightChangeText(kg: -0.4, units: .metric) == "-0.4 kg")
        #expect(UnitConversion.bodyWeightChangeText(kg: 1, units: .imperial) == "+2.2 lb")
    }

    @Test func bodyWeightChangeThatRoundsAwayHasNoSign() {
        #expect(UnitConversion.bodyWeightChangeNumberText(kg: -0.01, units: .metric) == "0.0")
        #expect(UnitConversion.bodyWeightChangeNumberText(kg: 0.01, units: .imperial) == "0.0")
    }

    @Test(arguments: [45.0, 80.4, 77.77777, 123.456])
    func untouchedBodyWeightFieldKeepsItsExactKg(kg: Double) {
        #expect(WeightField(kg: kg, units: .metric).bodyWeightKg == kg)
        #expect(WeightField(kg: kg, units: .imperial).bodyWeightKg == kg)
    }

    @Test func poundsRoundTripThroughTheFieldWithoutDrift() throws {
        var field = WeightField(kg: nil, units: .imperial)
        field.text = "177.3"
        let kg = try #require(field.bodyWeightKg)
        #expect(UnitConversion.weightNumberText(kg: kg, units: .imperial) == "177.3")
        #expect(WeightField(kg: kg, units: .imperial).text == "177.3")
    }

    @Test func bodyWeightRangeAppliesAfterConversion() {
        var field = WeightField(kg: nil, units: .imperial)
        field.text = "300" // 136 kg in pounds, fine.
        #expect(field.bodyWeightKg != nil)
        field.text = "30" // 13.6 kg, too low even though 30 kg would pass.
        #expect(field.bodyWeightKg == nil)
        field.text = "900" // 408 kg, too high even though it reads as a number under 1000.
        #expect(field.bodyWeightKg == nil)
    }

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

    // MARK: - Lifted weight

    @Test(arguments: [
        (82.5, "82.5"), (102.25, "102.25"), (225.0, "225"), (100.0, "100"),
        (1.25, "1.25"), (0.125, "0.13"), (0.0, "0"), (1000.0, "1000"),
    ])
    func weightNumberTextTrimsToTwoDecimals(kg: Double, expected: String) {
        #expect(UnitConversion.weightNumberText(kg: kg, units: .metric) == expected)
    }

    @Test(arguments: [45.0, 135.0, 185.5, 225.0, 315.0, 102.25])
    func poundsInputRoundTripsWithoutDrift(pounds: Double) throws {
        let kg = try #require(UnitConversion.parseWeight(String(pounds), units: .imperial))
        #expect(abs(UnitConversion.displayWeight(kg: kg, units: .imperial) - pounds) < 1e-9)
        #expect(UnitConversion.weightNumberText(kg: kg, units: .imperial)
                == pounds.formatted(.number.precision(.fractionLength(0...2)).grouping(.never).locale(Locale(identifier: "en_US_POSIX"))))
    }

    @Test func twoTwentyFivePoundsShowsAsTwoTwentyFive() throws {
        let kg = try #require(UnitConversion.parseWeight("225", units: .imperial))
        #expect(UnitConversion.liftWeightText(kg: kg, units: .imperial) == "225 lb")
        #expect(UnitConversion.liftWeightText(kg: kg, units: .metric) == "102.06 kg")
    }

    @Test func kilogramMicroplateStepsStayExact() {
        for step in 0...40 {
            let kg = 20 + Double(step) * 1.25
            #expect(UnitConversion.parseWeight(UnitConversion.weightNumberText(kg: kg, units: .metric), units: .metric) == kg)
        }
    }

    @Test func parseWeightAcceptsCommaAndDotDecimals() {
        #expect(UnitConversion.parseWeight("82,5", units: .metric) == 82.5)
        #expect(UnitConversion.parseWeight("82.5", units: .metric) == 82.5)
        #expect(UnitConversion.parseWeight(" 60 ", units: .metric) == 60)
    }

    @Test func parseWeightRejectsBlankAndNonNumericInput() {
        #expect(UnitConversion.parseWeight("", units: .metric) == nil)
        #expect(UnitConversion.parseWeight("abc", units: .imperial) == nil)
        #expect(UnitConversion.parseWeight("inf", units: .metric) == nil)
    }

    @Test func weightLabelsFollowUnits() {
        #expect(UnitConversion.weightUnitSymbol(.metric) == "kg")
        #expect(UnitConversion.weightUnitSymbol(.imperial) == "lb")
        #expect(UnitConversion.spokenWeightUnit(.imperial) == "pounds")
        #expect(UnitConversion.volumeText(kg: 1000, units: .metric) == "1000 kg")
        #expect(UnitConversion.volumeText(kg: 1000, units: .imperial) == "2205 lb")
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
