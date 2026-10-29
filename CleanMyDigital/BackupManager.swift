//
//  BackupManager.swift
//  CleanMyDigital
//

import Foundation

/// Copies a file's original bytes into a "_CleanMyDigital Backups" folder at
/// the scanned root before it's modified for the first time, mirroring the
/// file's path relative to that root. Since the backup folder lives inside
/// the folder the user granted access to, no extra sandbox permission is
/// needed to write it.
enum BackupManager {
    nonisolated static let backupFolderName = "_CleanMyDigital Backups"

    /// Backs up `fileURL` under `root` if it hasn't been backed up already
    /// this session. No-ops if a backup already exists at the mirrored path.
    static func backupIfNeeded(fileURL: URL, root: URL) throws {
        let destination = try backupDestination(for: fileURL, root: root)
        guard !FileManager.default.fileExists(atPath: destination.path) else { return }

        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: fileURL, to: destination)
    }

    static func backupDestination(for fileURL: URL, root: URL) throws -> URL {
        let rootComponents = root.standardizedFileURL.pathComponents
        let fileComponents = fileURL.standardizedFileURL.pathComponents
        guard fileComponents.count > rootComponents.count,
              Array(fileComponents.prefix(rootComponents.count)) == rootComponents
        else {
            throw TagWriteError.underlying(CocoaError(.fileNoSuchFile))
        }
        let relativeComponents = fileComponents[rootComponents.count...]
        var destination = root.appendingPathComponent(backupFolderName)
        for component in relativeComponents {
            destination.appendPathComponent(component)
        }
        return destination
    }
}
