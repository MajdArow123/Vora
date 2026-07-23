//
//  AppearanceSettingTests.swift
//  VoraTests
//
//  Created by Majd Arow on 2026-07-22.
//

import Foundation
import SwiftUI
import Testing
@testable import Vora

struct AppearanceSettingTests {
    @Test(arguments: AppearanceSetting.allCases)
    func storedValueRoundTrips(setting: AppearanceSetting) {
        let suite = "vora.tests.appearance"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        defaults.set(setting.rawValue, forKey: AppearanceSetting.storageKey)
        let restored = defaults.string(forKey: AppearanceSetting.storageKey)
            .flatMap(AppearanceSetting.init(rawValue:))

        #expect(restored == setting)
    }

    @Test func unknownStoredValueDoesNotDecode() {
        // @AppStorage falls back to its declared default (.system) when
        // the raw value fails to decode.
        #expect(AppearanceSetting(rawValue: "sepia") == nil)
    }

    @Test func colorSchemeMappingFollowsSpec() {
        #expect(AppearanceSetting.system.colorScheme == nil)
        #expect(AppearanceSetting.light.colorScheme == .light)
        #expect(AppearanceSetting.dark.colorScheme == .dark)
    }

    @Test func iconsFollowSpec() {
        #expect(AppearanceSetting.system.iconName == "circle.lefthalf.filled")
        #expect(AppearanceSetting.light.iconName == "sun.max.fill")
        #expect(AppearanceSetting.dark.iconName == "moon.fill")
    }
}
