//
//  AudioFile.swift
//  CleanMyDigital
//

import AppKit
import Foundation

/// A metadata field the scanner checks on every audio file.
enum MetadataField: String, CaseIterable, Identifiable {
    case title = "Title"
    case artist = "Artist"
    case album = "Album"
    case artwork = "Artwork"
    case year = "Year"
    case genre = "Genre"
    case trackNumber = "Track Number"

    var id: String { rawValue }
}

/// How a scanned folder is organized — determines which rules apply.
enum LibraryCategory: String, CaseIterable, Identifiable {
    case singles = "Singles"
    case albums = "Albums"
    case compilations = "Compilations"

    var id: String { rawValue }

    /// Only Albums are checked against their containing ArtistName/ folder —
    /// Singles don't require it, and Compilations aren't organized by artist.
    var checksArtistFolder: Bool { self == .albums }

    /// Singles are commonly filed one folder per artist, so several folders
    /// can be scanned as one library. Albums and Compilations read meaning
    /// from the scanned folder's own structure (artist folders, one folder
    /// per release), which several unrelated roots would muddle.
    var allowsMultipleFolders: Bool { self == .singles }
}

/// A single flagged problem on a scanned file: either a missing tag or an
/// Artist tag that doesn't match the folder the file is filed under.
struct AudioIssue: Identifiable, Hashable {
    let id: String
    let label: String
    let isArtistMismatch: Bool
}

/// The result of scanning one audio file.
struct AudioFile: Identifiable, Sendable {
    let url: URL
    let fileName: String
    let fileExtension: String
    let sizeBytes: Int64
    let duration: TimeInterval?
    /// The audio track's real encoded bitrate in kbps, read directly from
    /// the decoded audio stream via `AVAssetTrack.estimatedDataRate` — not
    /// estimated from whole-file size ÷ duration, which embedded artwork
    /// or tag padding can skew upward. Nil if unreadable or AVFoundation
    /// couldn't report a rate.
    let bitrateKbps: Int?

    let title: String?
    let artist: String?
    let album: String?
    /// A small, pre-downscaled thumbnail of the embedded cover art, if any.
    let artworkThumbnail: NSImage?
    let year: String?
    let genre: String?
    let trackNumber: String?

    let category: LibraryCategory
    /// The first-level folder name under the scanned root — the artist this
    /// file is expected to belong to. Nil for Compilations or root-level files.
    let expectedArtist: String?

    /// False when AVFoundation could not open the file at all.
    let isReadable: Bool

    var id: URL { url }

    var hasArtwork: Bool { artworkThumbnail != nil }

    /// Fields the scanner checks for this file's category — Singles don't
    /// require a Track Number, since maxi singles are often left untracked.
    private var applicableFields: [MetadataField] {
        category == .singles ? MetadataField.allCases.filter { $0 != .trackNumber } : MetadataField.allCases
    }

    var missingFields: [MetadataField] {
        guard isReadable else { return applicableFields }
        var missing: [MetadataField] = []
        if title?.isEmpty ?? true { missing.append(.title) }
        if artist?.isEmpty ?? true { missing.append(.artist) }
        if album?.isEmpty ?? true { missing.append(.album) }
        if !hasArtwork { missing.append(.artwork) }
        if year?.isEmpty ?? true { missing.append(.year) }
        if genre?.isEmpty ?? true { missing.append(.genre) }
        if category != .singles, trackNumber?.isEmpty ?? true { missing.append(.trackNumber) }
        return missing
    }

    /// True when the Artist tag is present but doesn't match the folder
    /// it's filed under. Only checked for Albums.
    ///
    /// Beyond an exact (case-insensitive) match, also accepts `artist`
    /// *containing* `expectedArtist` as a substring — e.g. tag
    /// "Anouar Brahem Trio" under an "Anouar Brahem" folder, a trio billing
    /// for one release correctly filed under the artist's overall folder.
    /// Deliberately one-directional: the reverse (`expectedArtist`
    /// containing `artist`) is NOT accepted, and must not be added later to
    /// "make this symmetric" — that's exactly the shape of the mis-rooted-
    /// scan case `looksLikeAlbumFolderName`/`possibleArtistFolderMismatch`
    /// exists to catch. A garbled `expectedArtist` like
    /// "1995 - C + C Music Factory" (a scan rooted at an album folder
    /// instead of its artist parent) *also* contains the real artist name
    /// "C + C Music Factory" as a substring — accepting that direction here
    /// would silently stop flagging the mismatch that heuristic relies on
    /// this check to surface.
    var hasArtistMismatch: Bool {
        guard category.checksArtistFolder,
              let expectedArtist, let artist, !artist.isEmpty
        else { return false }
        // A string trivially "contains" itself, so this also covers the
        // exact-match case without a separate comparison.
        return !artist.localizedCaseInsensitiveContains(expectedArtist)
    }

    /// Every problem found on this file: missing fields plus an artist
    /// mismatch, if any.
    var issues: [AudioIssue] {
        var result = missingFields.map {
            AudioIssue(id: $0.rawValue, label: $0.rawValue, isArtistMismatch: false)
        }
        if hasArtistMismatch {
            result.append(AudioIssue(id: "artistMismatch", label: "Artist Mismatch", isArtistMismatch: true))
        }
        return result
    }

    var hasIssues: Bool { !issues.isEmpty }

    /// Missing every field we check (or unreadable) — the worst offenders.
    var hasNoMetadata: Bool { missingFields.count == applicableFields.count }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }

    var formattedDuration: String {
        guard let duration, duration.isFinite, duration > 0 else { return "–" }
        let total = Int(duration.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    var formattedBitrate: String {
        guard let bitrateKbps else { return "–" }
        return "\(bitrateKbps.formatted()) kbps"
    }

    /// Sort key for the Bitrate column — missing values sort below every
    /// real bitrate instead of colliding at zero.
    var bitrateSortKey: Int { bitrateKbps ?? -1 }

    /// True when `name` looks like an album/release folder rather than an
    /// artist name — this library's album folders reliably encode a
    /// 4-digit year and/or multiple " - "-separated parts (e.g.
    /// "2Pac - 1998 - Greatest Hits"), which real artist names essentially
    /// never do. Used to flag a scan that was likely rooted one level too
    /// deep — an artist's own album folder scanned directly instead of its
    /// parent, which makes every file's `expectedArtist` come out as the
    /// album folder's name instead of the real artist.
    static func looksLikeAlbumFolderName(_ name: String) -> Bool {
        if name.range(of: #"(19|20)\d{2}"#, options: .regularExpression) != nil { return true }
        return name.components(separatedBy: " - ").count >= 3
    }

    /// A copy of this file at `newURL` — used after a successful rename, so
    /// the scanner can update its record in place without a full re-scan.
    func renamed(to newURL: URL, expectedArtist newExpectedArtist: String?? = nil) -> AudioFile {
        let expectedArtist = newExpectedArtist ?? expectedArtist
        return AudioFile(url: newURL, fileName: newURL.lastPathComponent, fileExtension: fileExtension,
                  sizeBytes: sizeBytes, duration: duration, bitrateKbps: bitrateKbps,
                  title: title, artist: artist, album: album,
                  artworkThumbnail: artworkThumbnail,
                  year: year, genre: genre, trackNumber: trackNumber,
                  category: category, expectedArtist: expectedArtist,
                  isReadable: isReadable)
    }
}
