//
//  TestFileCleanup.swift
//  VoraTests
//
//  Created by Majd Arow on 2026-11-01.
//

import Foundation
import Testing

/// Removes a temporary file or directory a test created. A missing item is
/// fine; a failed removal is recorded as a test issue instead of being
/// silently ignored.
nonisolated func removeTestItem(at url: URL) {
    guard FileManager.default.fileExists(atPath: url.path) else { return }
    do {
        try FileManager.default.removeItem(at: url)
    } catch {
        Issue.record("Failed to remove \(url.lastPathComponent): \(error)")
    }
}

/// A UserDefaults suite unique to one test, emptied on creation.
nonisolated func makeTestDefaults(_ label: String = #function) throws -> UserDefaults {
    let suite = "VoraTests-\(label)-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defaults.removePersistentDomain(forName: suite)
    return defaults
}
