//
//  LibraryScanner.swift
//  CleanMyDigital
//

import AppKit
import Foundation
import AVFoundation
import ImageIO
import Observation

@Observable
final class LibraryScanner {
    enum State: Equatable {
        case idle
        case enumerating
        case scanning
        case finished
    }

    private(set) var state: State = .idle
    private(set) var files: [AudioFile] = []
    private(set) var scannedCount = 0
    private(set) var totalCount = 0
    private(set) var scannedFolder: URL?
    private(set) var category: LibraryCategory?

    /// Batch "Find All Metadata" results, keyed by file URL. Session-only —
    /// cleared whenever a new scan starts.
    private(set) var lookupResults: [URL: LookupOutcome] = [:]
    private(set) var isLookingUp = false
    private(set) var lookupCompletedCount = 0
    private(set) var lookupTotalCount = 0

    private var lookupTask: Task<Void, Never>?

    /// File extensions AVFoundation can read metadata from.
    nonisolated static let supportedExtensions: Set<String> = [
        "mp3", "m4a", "m4b", "m4p", "aac", "flac", "wav", "wave",
        "aif", "aiff", "aifc", "caf", "mp4", "alac", "ac3", "eac3",
    ]

    /// Audio formats we recognize but AVFoundation cannot open —
    /// reported as unreadable so they still get flagged.
    nonisolated static let unsupportedAudioExtensions: Set<String> = [
        "ogg", "oga", "opus", "wma", "ape", "wv", "mpc", "dsf", "dff",
    ]

    var progress: Double {
        totalCount > 0 ? Double(scannedCount) / Double(totalCount) : 0
    }

    func scan(folder: URL, category: LibraryCategory) async {
        let didAccess = folder.startAccessingSecurityScopedResource()
        defer { if didAccess { folder.stopAccessingSecurityScopedResource() } }

        state = .enumerating
        files = []
        scannedCount = 0
        totalCount = 0
        scannedFolder = folder
        self.category = category

        lookupTask?.cancel()
        lookupTask = nil
        lookupResults = [:]
        isLookingUp = false
        lookupCompletedCount = 0
        lookupTotalCount = 0

        let urls = await Task.detached(priority: .userInitiated) {
            Self.audioFileURLs(in: folder)
        }.value

        totalCount = urls.count
        state = .scanning

        // Read metadata with bounded concurrency so huge libraries stay responsive.
        let maxConcurrent = 8
        var results: [AudioFile] = []
        results.reserveCapacity(urls.count)

        await withTaskGroup(of: AudioFile.self) { group in
            var iterator = urls.makeIterator()
            var inFlight = 0

            while inFlight < maxConcurrent, let url = iterator.next() {
                let expected = Self.expectedArtist(for: url, in: folder)
                group.addTask { await Self.inspect(url, expectedArtist: expected, category: category) }
                inFlight += 1
            }
            for await file in group {
                results.append(file)
                scannedCount += 1
                if let url = iterator.next() {
                    let expected = Self.expectedArtist(for: url, in: folder)
                    group.addTask { await Self.inspect(url, expectedArtist: expected, category: category) }
                }
            }
        }

        files = results.sorted {
            $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending
        }
        state = .finished
    }

    /// Writes `changes` to `file`'s tags, backing up the original first if
    /// requested, then re-reads the file and updates `files` in place so
    /// the table reflects the change immediately.
    ///
    /// `scan(folder:)` releases its security-scoped access to the folder as
    /// soon as the scan finishes, so writes re-acquire it for the duration
    /// of the operation — access extends to the whole subtree the folder
    /// covers, including this file.
    func applyTagChanges(_ changes: TagChanges, to file: AudioFile, backupFirst: Bool) async throws {
        guard let scannedFolder else {
            throw TagWriteError.underlying(CocoaError(.fileNoSuchFile))
        }

        let didAccess = scannedFolder.startAccessingSecurityScopedResource()
        defer { if didAccess { scannedFolder.stopAccessingSecurityScopedResource() } }

        if backupFirst {
            try BackupManager.backupIfNeeded(fileURL: file.url, root: scannedFolder)
        }

        try await TagWriterRouter.write(changes, to: file.url)

        let expected = Self.expectedArtist(for: file.url, in: scannedFolder)
        let updated = await Self.inspect(file.url, expectedArtist: expected, category: file.category)
        if let index = files.firstIndex(where: { $0.url == file.url }) {
            files[index] = updated
        }
        lookupResults.removeValue(forKey: file.url)
    }

    /// Looks up every flagged file against Discogs, then MusicBrainz, one at
    /// a time — both clients pace their own requests, so this just needs to
    /// stay sequential and stop promptly on cancellation.
    func findAllMetadata(discogsToken: String, musicBrainzContact: String) {
        guard !isLookingUp else { return }
        let targets = files.filter(\.hasIssues)
        guard !targets.isEmpty else { return }

        lookupCompletedCount = 0
        lookupTotalCount = targets.count
        isLookingUp = true

        lookupTask = Task {
            for file in targets {
                if Task.isCancelled { break }
                let outcome = await Self.lookupOutcome(
                    for: file, discogsToken: discogsToken, musicBrainzContact: musicBrainzContact)
                if Task.isCancelled { break }
                lookupResults[file.url] = outcome
                lookupCompletedCount += 1
            }
            isLookingUp = false
            lookupTask = nil
        }
    }

    /// Stops the batch lookup after the in-flight request finishes —
    /// whatever was already found stays in `lookupResults`.
    func cancelLookup() {
        lookupTask?.cancel()
    }

    /// Searches Discogs first; only falls through to MusicBrainz if Discogs
    /// errored or its top candidate wouldn't fill any of this file's
    /// missing fields.
    nonisolated private static func lookupOutcome(
        for file: AudioFile, discogsToken: String, musicBrainzContact: String
    ) async -> LookupOutcome {
        let missing = file.missingFields
        guard !missing.isEmpty else { return .noMatch }

        if !discogsToken.isEmpty {
            let query = DiscogsQuery(for: file)
            if let releases = try? await DiscogsClient.search(artist: query.artist, track: query.track, token: discogsToken),
               let top = releases.first {
                let fillable = top.fillableFields(missing: missing)
                if !fillable.isEmpty {
                    return .found(provider: .discogs, candidate: .discogs(top), fillableFields: fillable)
                }
            }
        }

        if !musicBrainzContact.isEmpty {
            let query = MusicBrainzQuery(for: file)
            if let recordings = try? await MusicBrainzClient.searchRecordings(
                artist: query.artist, recording: query.recording, contactEmail: musicBrainzContact),
               let top = recordings.first {
                let fillable = top.fillableFields(missing: missing)
                if !fillable.isEmpty {
                    return .found(provider: .musicBrainz, candidate: .musicBrainz(top), fillableFields: fillable)
                }
            }
        }

        return .noMatch
    }

    nonisolated private static func audioFileURLs(in folder: URL) -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var urls: [URL] = []
        for case let url as URL in enumerator {
            if url.lastPathComponent == BackupManager.backupFolderName {
                enumerator.skipDescendants()
                continue
            }
            let ext = url.pathExtension.lowercased()
            guard supportedExtensions.contains(ext) || unsupportedAudioExtensions.contains(ext),
                  (try? url.resourceValues(forKeys: Set(keys)).isRegularFile) == true
            else { continue }
            urls.append(url)
        }
        return urls
    }

    /// The first path component of `url` under `folder` — the "ArtistName"
    /// folder Singles & Albums are organized by. Nil if `url` sits directly
    /// in `folder` with no intervening subfolder.
    nonisolated private static func expectedArtist(for url: URL, in folder: URL) -> String? {
        let rootComponents = folder.standardizedFileURL.pathComponents
        let fileComponents = url.standardizedFileURL.pathComponents
        guard fileComponents.count > rootComponents.count + 1,
              Array(fileComponents.prefix(rootComponents.count)) == rootComponents
        else { return nil }
        return fileComponents[rootComponents.count]
    }

    nonisolated private static func inspect(
        _ url: URL, expectedArtist: String?, category: LibraryCategory
    ) async -> AudioFile {
        let ext = url.pathExtension.lowercased()
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0

        func unreadable() -> AudioFile {
            AudioFile(url: url, fileName: url.lastPathComponent, fileExtension: ext,
                      sizeBytes: size, duration: nil,
                      title: nil, artist: nil, album: nil,
                      artworkThumbnail: nil,
                      year: nil, genre: nil, trackNumber: nil,
                      category: category, expectedArtist: expectedArtist,
                      isReadable: false)
        }

        guard supportedExtensions.contains(ext) else { return unreadable() }

        let asset = AVURLAsset(url: url)
        do {
            // Merge common metadata with every format-specific block (ID3,
            // iTunes, …) so tags AVFoundation doesn't map to "common" still count.
            var items = try await asset.load(.commonMetadata)
            for format in try await asset.load(.availableMetadataFormats) {
                items += try await asset.loadMetadata(for: format)
            }

            let duration = try? await asset.load(.duration).seconds

            return AudioFile(
                url: url,
                fileName: url.lastPathComponent,
                fileExtension: ext,
                sizeBytes: size,
                duration: duration,
                title: await stringValue(in: items, common: .commonIdentifierTitle,
                                         keys: ["TIT2", "TT2", "©nam", "title", "TITLE"]),
                artist: await stringValue(in: items, common: .commonIdentifierArtist,
                                          keys: ["TPE1", "TP1", "©ART", "artist", "ARTIST"]),
                album: await stringValue(in: items, common: .commonIdentifierAlbumName,
                                         keys: ["TALB", "TAL", "©alb", "album", "ALBUM"]),
                artworkThumbnail: await artworkThumbnail(in: items),
                year: await stringValue(in: items, common: .commonIdentifierCreationDate,
                                        keys: ["TYER", "TDRC", "©day", "year", "YEAR"]),
                genre: await stringValue(in: items, common: nil,
                                         keys: ["TCON", "©gen", "gnre", "genre", "GENRE"]),
                trackNumber: await stringValue(in: items, common: nil,
                                               keys: ["TRCK", "trkn", "tracknumber", "TRACKNUMBER"]),
                category: category,
                expectedArtist: expectedArtist,
                isReadable: true
            )
        } catch {
            return unreadable()
        }
    }

    nonisolated private static func stringValue(
        in items: [AVMetadataItem],
        common identifier: AVMetadataIdentifier?,
        keys: [String]
    ) async -> String? {
        var candidates = identifier.map {
            AVMetadataItem.metadataItems(from: items, filteredByIdentifier: $0)
        } ?? []
        candidates += items.filter { item in
            guard let key = item.key else { return false }
            return keys.contains(String(describing: key))
        }
        for item in candidates {
            if let value = try? await item.load(.stringValue),
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }
        return nil
    }

    /// Table thumbnails render at 24pt; 64px covers up to 3x Retina scaling
    /// while keeping the decoded bitmap tiny across large libraries.
    nonisolated private static let thumbnailMaxPixelSize = 64

    nonisolated private static func artworkThumbnail(in items: [AVMetadataItem]) async -> NSImage? {
        var candidates = AVMetadataItem.metadataItems(
            from: items, filteredByIdentifier: .commonIdentifierArtwork)
        candidates += items.filter { item in
            guard let key = item.key else { return false }
            return ["APIC", "PIC", "covr"].contains(String(describing: key))
        }
        for item in candidates {
            if let data = try? await item.load(.dataValue), !data.isEmpty,
               let thumbnail = downscaledImage(from: data, maxPixelSize: thumbnailMaxPixelSize) {
                return thumbnail
            }
        }
        return nil
    }

    nonisolated private static func downscaledImage(from data: Data, maxPixelSize: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}
