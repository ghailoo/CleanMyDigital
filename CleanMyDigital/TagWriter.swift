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
    var artworkJPEG: Data?

    var isEmpty: Bool {
        title == nil && artist == nil && album == nil && year == nil
            && genre == nil && trackNumber == nil && artworkJPEG == nil
    }
}

enum TagWriteError: LocalizedError {
    case unsupportedFormat(String)
    case noChanges
    case malformedFile(String)
    case underlying(Error)

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
    /// FLAC, MP3, M4A, and WAV are the formats CleanMyDigital can write to
    /// today. AIFF and everything else stay read-only.
    private static let writableExtensions: Set<String> = ["flac", "mp3", "m4a", "wav", "wave"]

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
        default:
            throw TagWriteError.unsupportedFormat(url.pathExtension)
        }
    }
}
