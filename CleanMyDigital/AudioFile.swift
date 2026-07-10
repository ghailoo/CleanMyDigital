//
//  AudioFile.swift
//  CleanMyDigital
//

import Foundation

/// A metadata field the scanner checks on every audio file.
enum MetadataField: String, CaseIterable, Identifiable {
    case title = "Title"
    case artist = "Artist"
    case album = "Album"
    case artwork = "Artwork"

    var id: String { rawValue }
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
    let hasArtwork: Bool

    /// False when AVFoundation could not open the file at all.
    let isReadable: Bool

    var id: URL { url }

    var missingFields: [MetadataField] {
        guard isReadable else { return MetadataField.allCases }
        var missing: [MetadataField] = []
        if title?.isEmpty ?? true { missing.append(.title) }
        if artist?.isEmpty ?? true { missing.append(.artist) }
        if album?.isEmpty ?? true { missing.append(.album) }
        if !hasArtwork { missing.append(.artwork) }
        return missing
    }

    var hasIssues: Bool { !missingFields.isEmpty }

    /// Missing every field we check (or unreadable) — the worst offenders.
    var hasNoMetadata: Bool { missingFields.count == MetadataField.allCases.count }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }

    var formattedDuration: String {
        guard let duration, duration.isFinite, duration > 0 else { return "–" }
        let total = Int(duration.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
