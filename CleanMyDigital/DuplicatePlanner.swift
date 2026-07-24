//
//  DuplicatePlanner.swift
//  CleanMyDigital
//

import Foundation

/// A set of files sharing the same Artist + Title, sorted best quality
/// first. `keeper` is the recommended file to keep; every other file in
/// `files` is a candidate to move out of the way.
struct DuplicateGroup: Identifiable, Sendable {
    let key: String
    let files: [AudioFile]

    var id: String { key }
    var keeper: AudioFile { files[0] }
    var extras: [AudioFile] { Array(files.dropFirst()) }
}

/// One proposed move: an extra copy in a duplicate group, relocated into a
/// review subfolder (mirroring its original relative path under the
/// scanned root, the same way `BackupManager` mirrors paths) so nothing is
/// ever silently overwritten or deleted.
struct DuplicateMoveProposal: Identifiable, Sendable {
    let file: AudioFile
    let proposedRelativePath: String

    var id: URL { file.url }
}

/// Groups scanned files into duplicate sets (same Artist + Title, matched
/// case/whitespace-insensitively) and ranks each group's files by real
/// measured quality rather than any tag or filename. Pure and
/// filesystem-free, like `RenamePlanner`/`CollectionPlanner`.
enum DuplicatePlanner {
    static let reviewFolderName = "_CleanMyDigital Duplicates"

    /// Groups every file that shares an Artist + Title with at least one
    /// other file. Files missing either tag are skipped — there's nothing
    /// reliable to match them on.
    static func groups(for files: [AudioFile], cutoffHz: [URL: Double]) -> [DuplicateGroup] {
        var buckets: [String: [AudioFile]] = [:]
        for file in files {
            // Already parked for review by a previous run — don't flag it
            // against its own keeper again.
            guard !file.url.pathComponents.contains(reviewFolderName) else { continue }
            guard let key = matchKey(for: file) else { continue }
            buckets[key, default: []].append(file)
        }

        return buckets.compactMap { key, groupFiles -> DuplicateGroup? in
            guard groupFiles.count > 1 else { return nil }
            let sorted = groupFiles.sorted { isHigherQuality($0, than: $1, cutoffHz: cutoffHz) }
            return DuplicateGroup(key: key, files: sorted)
        }.sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
    }

    /// Builds move proposals for every extra (non-keeper) file across
    /// `groups`, mirroring each file's path relative to `root` under the
    /// review folder.
    static func plan(for groups: [DuplicateGroup], root: URL) -> [DuplicateMoveProposal] {
        groups.flatMap { group in
            group.extras.compactMap { file -> DuplicateMoveProposal? in
                guard let relativePath = relativePath(of: file.url, from: root) else { return nil }
                return DuplicateMoveProposal(
                    file: file, proposedRelativePath: "\(reviewFolderName)/\(relativePath)")
            }
        }
    }

    private static func matchKey(for file: AudioFile) -> String? {
        guard let artist = normalized(file.artist), let title = normalized(file.title) else { return nil }
        return "\(artist)|\(title)"
    }

    private static func normalized(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed.lowercased()
    }

    /// True if `a` should rank above `b`. Compares real spectral cutoff
    /// (actual audio bandwidth) only when *both* files have been measured
    /// — a high-bitrate file with a low measured cutoff is a transcoded
    /// fake, so cutoff should win when it's known for both. If either
    /// file hasn't been analyzed (spectral analysis is opt-in), an
    /// unmeasured file isn't penalized against a measured-but-flagged one
    /// — falls back to comparing bitrate instead.
    private static func isHigherQuality(_ a: AudioFile, than b: AudioFile, cutoffHz: [URL: Double]) -> Bool {
        if let cutoffA = cutoffHz[a.url], let cutoffB = cutoffHz[b.url], cutoffA != cutoffB {
            return cutoffA > cutoffB
        }
        return (a.bitrateKbps ?? -1) > (b.bitrateKbps ?? -1)
    }

    private static func relativePath(of url: URL, from root: URL) -> String? {
        let rootComponents = root.standardizedFileURL.pathComponents
        let fileComponents = url.standardizedFileURL.pathComponents
        guard fileComponents.count > rootComponents.count,
              Array(fileComponents.prefix(rootComponents.count)) == rootComponents
        else { return nil }
        return fileComponents[rootComponents.count...].joined(separator: "/")
    }
}
