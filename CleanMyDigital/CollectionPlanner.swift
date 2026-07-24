//
//  CollectionPlanner.swift
//  CleanMyDigital
//

import Foundation

/// One proposed move: `file` currently sitting directly in its folder, to
/// be moved into a subfolder named after its release.
struct CollectionProposal: Identifiable, Sendable {
    let file: AudioFile
    let releaseFolderName: String
    /// Displayed relative path after the move — "<releaseFolderName>/<fileName>".
    let proposedRelativePath: String

    var id: URL { file.url }
}

/// Derives a plan for grouping Singles into per-release subfolders — every
/// mix of the same track ends up together under a folder named after the
/// release, instead of sitting loose alongside every other track. Pure and
/// filesystem-free, like `RenamePlanner`.
enum CollectionPlanner {
    /// Builds proposals for every Singles file not already sitting directly
    /// inside a folder matching its release name. Albums/Compilations are
    /// skipped — they're already organized by folder structure.
    static func plan(for files: [AudioFile]) -> [CollectionProposal] {
        files.compactMap { file in
            guard file.category == .singles,
                  let releaseFolderName = releaseFolderName(for: file),
                  file.url.deletingLastPathComponent().lastPathComponent != releaseFolderName
            else { return nil }
            return CollectionProposal(
                file: file, releaseFolderName: releaseFolderName,
                proposedRelativePath: "\(releaseFolderName)/\(file.fileName)")
        }
    }

    /// The release name to group under: the Title tag with any trailing
    /// mix/version parenthetical stripped (e.g. "Ahora Es (Club Mix)" →
    /// "Ahora Es"), or the whole Title when it has no such suffix. Nil if
    /// there's no Title tag to derive a name from, or it sanitizes to empty.
    private static func releaseFolderName(for file: AudioFile) -> String? {
        guard let title = file.title, !title.isEmpty else { return nil }
        let base = MetadataQuery.strippingTrailingParenthetical(from: title) ?? title
        guard let name = RenamePlanner.sanitized(base), !name.isEmpty else { return nil }
        return name
    }
}
