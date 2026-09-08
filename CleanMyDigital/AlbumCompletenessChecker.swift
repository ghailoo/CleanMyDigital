//
//  AlbumCompletenessChecker.swift
//  CleanMyDigital
//

import Foundation

/// Whether an album folder appears to have its full tracklist, based only
/// on what's already known from the files' own tags (no network).
enum AlbumCompletenessStatus: Sendable, Equatable {
    case completeLocally
    /// `missingPositions` is empty when a total was found but not every
    /// file had a parseable track position — the count is still reliable,
    /// but which specific tracks are missing isn't.
    case incompleteLocally(missingCount: Int, missingPositions: [Int])
    /// No file in the folder states a track total, so nothing can be said
    /// without an online lookup.
    case unknownLocally
}

/// The outcome of comparing a Discogs release's tracklist against an
/// album's scanned files — recorded on `LibraryScanner` (session-only, keyed
/// by album folder URL) once a candidate release's tracklist has been
/// compared, so `AlbumCompletenessSheetView` can show a confirmed result
/// instead of "Unknown locally" forever. See
/// `LibraryScanner.recordAlbumCompletenessResult(_:for:)`.
enum AlbumCompletenessOnlineResult: Sendable, Equatable {
    case confirmedComplete
    case missingTracks([String])
}

/// One album (or compilation) folder's files, grouped for a completeness
/// check — files under `ArtistName/AlbumName/` (or a compilation's own
/// folder) share a folder, so the folder itself is the natural grouping
/// key for "is this release whole?"
struct AlbumGroup: Identifiable, Sendable {
    let folderURL: URL
    /// Every file in a group shares one category — a single scan is always
    /// one category throughout (see `LibraryScanner.scan`) — so this is
    /// read once from the group's own files rather than tracked
    /// separately. `DiscogsAlbumQuery` and `AlbumMetadataLookupView` read
    /// this to tell a compilation apart from an album — Discogs credits a
    /// compilation release to "Various", never to `artist` below (see
    /// `DiscogsQuery`'s doc comment for the same rule at the per-track
    /// level).
    let category: LibraryCategory
    let artist: String?
    let albumTitle: String?
    /// First non-empty Year tag among the group's files — same
    /// first-non-empty derivation as `albumTitle`. Used, alongside
    /// `albumTitle`, to propose a folder name via `AlbumFolderRenamePlanner`.
    let year: String?
    /// Sorted by parsed track position where available, else by filename.
    let files: [AudioFile]
    /// The highest "total tracks" value parsed out of any file's
    /// trackNumber tag ("3/12" style), if any file states one.
    let expectedTotalFromTags: Int?
    /// Track position numbers (the part before "/") present among files
    /// that had a parseable position.
    let presentPositions: Set<Int>

    /// `category` defaults to `.albums` — the only case that existed
    /// before Compilations joined `AlbumCompletenessChecker.groups(for:)`
    /// — so call sites/tests built before that widening keep compiling
    /// unchanged.
    init(
        folderURL: URL, category: LibraryCategory = .albums, artist: String?, albumTitle: String?,
        year: String?, files: [AudioFile], expectedTotalFromTags: Int?, presentPositions: Set<Int>
    ) {
        self.folderURL = folderURL
        self.category = category
        self.artist = artist
        self.albumTitle = albumTitle
        self.year = year
        self.files = files
        self.expectedTotalFromTags = expectedTotalFromTags
        self.presentPositions = presentPositions
    }

    var id: URL { folderURL }

    var localStatus: AlbumCompletenessStatus {
        guard let total = expectedTotalFromTags, total > 0 else { return .unknownLocally }
        guard files.count < total else { return .completeLocally }
        let missingCount = total - files.count
        let missingPositions = presentPositions.count == files.count
            ? Set(1...total).subtracting(presentPositions).sorted()
            : []
        return .incompleteLocally(missingCount: missingCount, missingPositions: missingPositions)
    }
}

/// Groups scanned Albums- and Compilations-category files by their
/// containing folder and checks each group's track-number tags for a
/// stated total, so an obviously-incomplete release (fewer files than its
/// own tags claim) is flagged without ever hitting the network. Pure and
/// filesystem-free, like `CollectionPlanner`/`DuplicatePlanner`.
///
/// Compilations were added here so `ApplyFoundMatchesSheetView`'s
/// section-level "re-match this whole folder" control can reach them too —
/// a compilation is exactly as much "one release with a tracklist" as an
/// album is, just credited to "Various" rather than one artist (see
/// `AlbumGroup.category`/`DiscogsAlbumQuery`). `AlbumCompletenessSheetView`,
/// this function's other caller, is unaffected: its "Check Album
/// Completeness…" window is only ever opened while the category picker is
/// on Albums (see `ContentView`'s toolbar), and a scan is always one
/// category throughout, so `scanner.files` there never actually contains
/// Compilations files for this widened filter to newly match.
enum AlbumCompletenessChecker {
    static func groups(for files: [AudioFile]) -> [AlbumGroup] {
        var buckets: [URL: [AudioFile]] = [:]
        for file in files where file.category == .albums || file.category == .compilations {
            let folderURL = file.url.deletingLastPathComponent().standardizedFileURL
            buckets[folderURL, default: []].append(file)
        }

        return buckets.map { folderURL, groupFiles in
            var maxTotal: Int?
            var positions: Set<Int> = []
            for file in groupFiles {
                guard let trackNumber = file.trackNumber, !trackNumber.isEmpty else { continue }
                let (part, total) = TagWriteHelpers.parseTrackPosition(trackNumber)
                if part > 0 { positions.insert(part) }
                if let total, total > 0 { maxTotal = max(maxTotal ?? 0, total) }
            }

            let sortedFiles = groupFiles.sorted { lhs, rhs in
                let lhsPart = TagWriteHelpers.parseTrackPosition(lhs.trackNumber ?? "").part
                let rhsPart = TagWriteHelpers.parseTrackPosition(rhs.trackNumber ?? "").part
                if lhsPart > 0, rhsPart > 0, lhsPart != rhsPart { return lhsPart < rhsPart }
                return lhs.fileName.localizedStandardCompare(rhs.fileName) == .orderedAscending
            }

            return AlbumGroup(
                folderURL: folderURL,
                category: groupFiles[0].category,
                artist: groupFiles.first(where: { $0.expectedArtist?.isEmpty == false })?.expectedArtist,
                albumTitle: groupFiles.first(where: { $0.album?.isEmpty == false })?.album,
                year: groupFiles.first(where: { $0.year?.isEmpty == false })?.year,
                files: sortedFiles,
                expectedTotalFromTags: maxTotal,
                presentPositions: positions
            )
        }.sorted { lhs, rhs in
            let lhsKey = "\(lhs.artist ?? "")|\(lhs.albumTitle ?? lhs.folderURL.lastPathComponent)"
            let rhsKey = "\(rhs.artist ?? "")|\(rhs.albumTitle ?? rhs.folderURL.lastPathComponent)"
            return lhsKey.localizedStandardCompare(rhsKey) == .orderedAscending
        }
    }
}
