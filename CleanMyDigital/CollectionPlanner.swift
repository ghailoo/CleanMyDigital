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
    /// "Artist - Title", with the mix/version suffix removed so every version
    /// of one track lands in the same folder. A file with only one version
    /// still gets its own folder — the point is one folder per release.
    ///
    /// Falls back to the filename for either part (via the same cleanup the
    /// Discogs search uses, so "feat." credits and scene tags don't leak into
    /// folder names): an untagged Title used to skip the file silently, which
    /// is exactly the pile of loose files this window exists to tidy up.
    static func releaseFolderName(for file: AudioFile) -> String? {
        let rawTitle = file.title?.isEmpty == false
            ? file.title!
            : MetadataQuery.cleanedTrackTitle(from: file.fileName, artist: artistName(for: file) ?? "", category: .singles)
        guard let title = RenamePlanner.sanitized(strippingMixSuffix(from: rawTitle)), !title.isEmpty else {
            return nil
        }
        guard let artist = RenamePlanner.sanitized(artistName(for: file)), !artist.isEmpty else {
            return title
        }
        return "\(artist) - \(title)"
    }

    private static func artistName(for file: AudioFile) -> String? {
        if let artist = file.artist, !artist.isEmpty {
            return MetadataQuery.strippingFeaturedArtist(from: artist)
        }
        return MetadataQuery.artistParsedFromFileName(file.fileName)
    }

    /// Strips every trailing "(Club Mix)" / "[Wyclef Remix]" group — a title
    /// can carry both ("My Love Is Your Love (Radio Edit) [Wyclef Remix]").
    private static func strippingMixSuffix(from title: String) -> String {
        var result = title.trimmingCharacters(in: .whitespacesAndNewlines)
        while let range = result.range(of: #"\s*[\(\[][^()\[\]]*[\)\]]\s*$"#, options: .regularExpression) {
            let stripped = result.replacingCharacters(in: range, with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if stripped.isEmpty { return result }
            result = stripped
        }
        return result
    }
}
