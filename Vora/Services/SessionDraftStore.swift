//
//  SessionDraftStore.swift
//  Vora
//
//  Created by Majd Arow on 2026-11-01.
//

import Foundation
import OSLog

/// Persists the active session draft as one JSON file in Application
/// Support. A draft that can't be read is logged and moved aside, never
/// fatal; one older than `maxAge` is cleared.
struct SessionDraftStore {
    static let fileName = "ActiveSessionDraft.json"
    static let maxAge: TimeInterval = 12 * 60 * 60

    private static let logger = Logger(subsystem: "com.majdarow.Vora", category: "SessionDraft")

    let directory: URL
    private let now: () -> Date
    private let fileManager = FileManager.default

    init(directory: URL = .applicationSupportDirectory, now: @escaping () -> Date = Date.init) {
        self.directory = directory
        self.now = now
    }

    var fileURL: URL {
        directory.appending(path: Self.fileName)
    }

    func save(_ draft: ActiveSessionDraft) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(draft)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    /// The saved draft if it exists, is readable and is under `maxAge`.
    func loadResumable() -> ActiveSessionDraft? {
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }

        let draft: ActiveSessionDraft
        do {
            let data = try Data(contentsOf: fileURL)
            draft = try JSONDecoder().decode(ActiveSessionDraft.self, from: data)
        } catch {
            Self.logger.error("Unreadable session draft: \(String(describing: error), privacy: .public)")
            setAside()
            return nil
        }

        guard ActiveSessionDraft.readableVersions.contains(draft.version) else {
            Self.logger.error("Session draft has unsupported version \(draft.version, privacy: .public)")
            setAside()
            return nil
        }
        guard now().timeIntervalSince(draft.savedAt) < Self.maxAge else {
            Self.logger.info("Session draft expired; clearing it")
            clear()
            return nil
        }
        guard !draft.exercises.isEmpty else {
            Self.logger.info("Session draft has no exercises; clearing it")
            clear()
            return nil
        }
        return draft
    }

    func clear() {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        do {
            try fileManager.removeItem(at: fileURL)
        } catch {
            Self.logger.error("Failed to clear session draft: \(String(describing: error), privacy: .public)")
        }
    }

    /// Moves an unreadable draft next to the original so it no longer
    /// blocks launch but is kept for inspection.
    private func setAside() {
        let stamp = Int(now().timeIntervalSince1970)
        let destination = directory.appending(path: "ActiveSessionDraft.corrupt-\(stamp)-\(UUID().uuidString.prefix(8)).json")
        do {
            try fileManager.moveItem(at: fileURL, to: destination)
            Self.logger.notice("Moved unreadable session draft to \(destination.lastPathComponent, privacy: .public)")
        } catch {
            Self.logger.error("Failed to set aside session draft: \(String(describing: error), privacy: .public)")
        }
    }
}
