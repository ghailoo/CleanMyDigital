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
    var hasArtistMismatch: Bool {
        guard category.checksArtistFolder,
              let expectedArtist, let artist, !artist.isEmpty
        else { return false }
        return artist.caseInsensitiveCompare(expectedArtist) != .orderedSame
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

    /// A copy of this file at `newURL` — used after a successful rename, so
    /// the scanner can update its record in place without a full re-scan.
    func renamed(to newURL: URL) -> AudioFile {
        AudioFile(url: newURL, fileName: newURL.lastPathComponent, fileExtension: fileExtension,
                  sizeBytes: sizeBytes, duration: duration, bitrateKbps: bitrateKbps,
                  title: title, artist: artist, album: album,
                  artworkThumbnail: artworkThumbnail,
                  year: year, genre: genre, trackNumber: trackNumber,
                  category: category, expectedArtist: expectedArtist,
                  isReadable: isReadable)
    }
}
