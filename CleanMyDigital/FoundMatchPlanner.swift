//
//  FoundMatchPlanner.swift
//  CleanMyDigital
//

import Foundation

/// One folder's worth of rows for `ApplyFoundMatchesSheetView` — every file
/// in that folder with a `.found` batch-lookup outcome, plus (for Albums
/// and Compilations) the `AlbumGroup` needed to open
/// `AlbumMetadataLookupView` for a whole-folder correction.
struct FoundMatchGroup: Identifiable, Sendable {
    let folderURL: URL
    /// In `targets`' incoming order (the same order they appear in the
    /// results table) — a folder's files already come out path-sorted
    /// from `LibraryScanner.files`, so this isn't re-sorted here.
    let files: [AudioFile]
    /// Non-nil only when a group-level "re-match this whole folder"
    /// control makes sense: Albums and Compilations are each "one release
    /// with a tracklist", so `AlbumMetadataLookupView` can search once and
    /// apply to every file in the folder. Nil for Singles, where each file
    /// is its own release and only the per-file correction path applies —
    /// this falls out naturally from `albumGroups` (built from
    /// `AlbumCompletenessChecker.groups(for:)`, which only ever produces
    /// Albums/Compilations groups) rather than being checked separately.
    let albumGroup: AlbumGroup?

    var id: URL { folderURL }
}

/// Groups a batch lookup's found-match files by containing folder — pure
/// and filesystem-free, like `DuplicatePlanner`/`CollectionPlanner`.
enum FoundMatchPlanner {
    static func groups(targets: [AudioFile], albumGroups: [AlbumGroup]) -> [FoundMatchGroup] {
        var order: [URL] = []
        var buckets: [URL: [AudioFile]] = [:]
        for file in targets {
            let folderURL = file.url.deletingLastPathComponent().standardizedFileURL
            if buckets[folderURL] == nil { order.append(folderURL) }
            buckets[folderURL, default: []].append(file)
        }

        let albumGroupsByFolder = Dictionary(uniqueKeysWithValues: albumGroups.map { ($0.folderURL, $0) })
        return order.map { folderURL in
            FoundMatchGroup(
                folderURL: folderURL,
                files: buckets[folderURL] ?? [],
                albumGroup: albumGroupsByFolder[folderURL])
        }
    }
}
