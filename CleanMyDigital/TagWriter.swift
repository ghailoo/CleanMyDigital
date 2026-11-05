//
//  TagWriter.swift
//  CleanMyDigital
//

import Foundation

/// Tag values to write to a file. Every property here must already have
/// been confirmed missing on the target `AudioFile` — writers additionally
/// double-check against the file's own existing tag before writing anything,
/// but callers must never populate a field the file already has.
struct TagChanges: Sendable {
    var title: String?
    var artist: String?
    var album: String?
    var year: String?
    var genre: String?
    var trackNumber: String?
    var grouping: String?
    var artworkJPEG: Data?
    /// The exceptions to "only fill empty fields": these fields replace an
    /// existing value. Only ever set by an explicit user action — a manual
    /// edit in the track inspector, or "Remove format suffixes" (Album).
    var replacing: Set<MetadataField> = []

    /// A text field's new value, if it's being written and non-empty.
    func value(for field: MetadataField) -> String? {
        let value: String? = switch field {
        case .title: title
        case .artist: artist
        case .album: album
        case .year: year
        case .genre: genre
        case .trackNumber: trackNumber
        case .grouping: grouping
        default: nil
        }
        return value?.isEmpty == false ? value : nil
    }

    /// Whether `field` should overwrite an existing value.
    func replaces(_ field: MetadataField) -> Bool {
        replacing.contains(field) && value(for: field) != nil
    }

    var isEmpty: Bool {
        title == nil && artist == nil && album == nil && year == nil
            && genre == nil && trackNumber == nil && grouping == nil && artworkJPEG == nil
    }
}

enum TagWriteError: LocalizedError {
    case unsupportedFormat(String)
    case noChanges
    case malformedFile(String)
    case underlying(Error)
    /// The pre-write backup (see `BackupManager`) couldn't be saved —
    /// distinguished from `.underlying` so callers can tell "your backup
    /// didn't save" apart from "your tag write failed" instead of both
    /// reading as the same generic message. Doesn't block the write itself
    /// (see `LibraryScanner.applyTagChanges`), so this is returned as a
    /// value there rather than thrown — kept as a `TagWriteError` case
    /// purely to reuse this type's message formatting.
    case backupFailed(Error)
    /// `startAccessingSecurityScopedResource()` on the scanned folder
    /// returned false — the security-scoped bookmark that grants access to
    /// it has gone stale (e.g. after a long session against a network
    /// volume, possibly across a sleep/reconnect) or was otherwise never
    /// (re-)granted. Proceeding into a file operation anyway fails
    /// downstream with a confusing generic "no such file" error even
    /// though the file is visibly right there in the results table; this
    /// surfaces the real cause instead, before any operation is attempted.
    case folderAccessUnavailable

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let ext):
            return "CleanMyDigital can't write tags to .\(ext) files yet."
        case .noChanges:
            return "There's nothing to write — every matched field is already present."
        case .malformedFile(let reason):
            return "This file's tags couldn't be parsed: \(reason)"
        case .underlying(let error):
            return error.localizedDescription
        case .backupFailed(let error):
            return "Backup failed: \(error.localizedDescription)"
        case .folderAccessUnavailable:
            return "Couldn't access the scanned folder anymore. Try Rescan, or choose the folder again."
        }
    }
}

enum TagWriteHelpers {
    /// Writes to a temp file in the same directory, then atomically swaps
    /// it in — so a crash or write failure never leaves a half-written file
    /// in place of the original.
    static func atomicReplace(_ data: Data, at url: URL) throws {
        let tempURL = url.deletingLastPathComponent()
            .appendingPathComponent(".cleanmydigital-\(UUID().uuidString)")
            .appendingPathExtension(url.pathExtension)
        do {
            try data.write(to: tempURL, options: .atomic)
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tempURL)
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            throw TagWriteError.underlying(error)
        }
    }

    /// Parses a "3" or "3/12" track-number tag into a position and an
    /// optional total track count.
    static func parseTrackPosition(_ value: String) -> (part: Int, total: Int?) {
        let components = value.split(separator: "/", maxSplits: 1)
        let part = components.first.flatMap { Int($0.trimmingCharacters(in: .whitespaces)) } ?? 0
        let total = components.count > 1 ? Int(components[1].trimmingCharacters(in: .whitespaces)) : nil
        return (part, total)
    }
}

/// Dispatches tag writes to the per-format writer, if any.
enum TagWriterRouter {
    /// FLAC, MP3, M4A, WAV, AIFF, DSF, and WavPack are the formats
    /// CleanMyDigital can write to today. Everything else stays read-only.
    private nonisolated static let writableExtensions: Set<String> = [
        "flac", "mp3", "m4a", "wav", "wave", "aif", "aiff", "aifc", "dsf", "wv", "ape",
    ]

    nonisolated static func canWrite(fileExtension: String) -> Bool {
        writableExtensions.contains(fileExtension.lowercased())
    }

    nonisolated static func write(_ changes: TagChanges, to url: URL) async throws {
        guard !changes.isEmpty else { throw TagWriteError.noChanges }
        switch url.pathExtension.lowercased() {
        case "flac":
            try FLACTagWriter.write(changes, to: url)
        case "mp3":
            try MP3TagWriter.write(changes, to: url)
        case "m4a":
            try await M4ATagWriter.write(changes, to: url)
        case "wav", "wave":
            try WAVTagWriter.write(changes, to: url)
        case "aif", "aiff", "aifc":
            try AIFFTagWriter.write(changes, to: url)
        case "dsf":
            try DSFTagWriter.write(changes, to: url)
        case "ape":
            try APETagWriter.write(changes, to: url)
        case "wv":
            try WavPackTagWriter.write(changes, to: url)
        default:
            throw TagWriteError.unsupportedFormat(url.pathExtension)
        }
    }
}
