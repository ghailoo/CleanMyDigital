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

    /// Singles & Albums are organized as ArtistName/… — Compilations aren't.
    var checksArtistFolder: Bool { self != .compilations }
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
    /// it's filed under. Only checked for Singles & Albums.
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
}
