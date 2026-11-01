//
//  StoreExporter.swift
//  Vora
//
//  Created by Majd Arow on 2026-11-01.
//

import Foundation

enum StoreExportError: LocalizedError {
    case storeMissing
    case archiveFailed(Error)

    var errorDescription: String? {
        switch self {
        case .storeMissing: "There's no saved data on this device to export."
        case .archiveFailed: "Couldn't create the export file. Please try again."
        }
    }
}

/// Packages the raw SwiftData store files into a zip the user can save
/// or share when the store cannot be opened. Only ever reads the
/// original files.
enum StoreExporter {
    /// SQLite sidecar files that hold not-yet-checkpointed writes.
    static let sidecarSuffixes = ["-wal", "-shm"]

    /// Builds `Vora-Data-<yyyy-MM-dd>.zip` in a fresh temporary folder.
    static func makeArchive(
        storeURL: URL,
        now: Date = .now,
        fileManager: FileManager = .default
    ) throws -> URL {
        let workDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("VoraExport-\(UUID().uuidString)", isDirectory: true)
        let day = now.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day())
        let baseName = "Vora-Data-\(day)"
        let stagingDirectory = workDirectory.appendingPathComponent(baseName, isDirectory: true)

        do {
            try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
            try stageFiles(storeURL: storeURL, into: stagingDirectory, fileManager: fileManager)
        } catch let error as StoreExportError {
            throw error
        } catch {
            throw StoreExportError.archiveFailed(error)
        }

        let archiveURL = workDirectory.appendingPathComponent("\(baseName).zip")
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(
            readingItemAt: stagingDirectory,
            options: .forUploading,
            error: &coordinationError
        ) { zippedURL in
            // The coordinator's zip only exists for the duration of this block.
            do {
                try fileManager.copyItem(at: zippedURL, to: archiveURL)
            } catch {
                copyError = error
            }
        }

        if let failure = coordinationError ?? copyError {
            throw StoreExportError.archiveFailed(failure)
        }
        return archiveURL
    }

    /// Copies the store and whichever sidecars exist into `directory`.
    /// Returns the copied file URLs, store first.
    @discardableResult
    static func stageFiles(
        storeURL: URL,
        into directory: URL,
        fileManager: FileManager = .default
    ) throws -> [URL] {
        guard fileManager.fileExists(atPath: storeURL.path) else {
            throw StoreExportError.storeMissing
        }

        let sidecars = sidecarSuffixes
            .map { URL(fileURLWithPath: storeURL.path + $0) }
            .filter { fileManager.fileExists(atPath: $0.path) }

        return try ([storeURL] + sidecars).map { source in
            let destination = directory.appendingPathComponent(source.lastPathComponent)
            try fileManager.copyItem(at: source, to: destination)
            return destination
        }
    }
}
