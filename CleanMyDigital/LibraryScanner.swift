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

    func scan(folder: URL) async {
        let didAccess = folder.startAccessingSecurityScopedResource()
        defer { if didAccess { folder.stopAccessingSecurityScopedResource() } }

        state = .enumerating
        files = []
        scannedCount = 0
        totalCount = 0
        scannedFolder = folder

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
                group.addTask { await Self.inspect(url) }
                inFlight += 1
            }
            for await file in group {
                results.append(file)
                scannedCount += 1
                if let url = iterator.next() {
                    group.addTask { await Self.inspect(url) }
                }
            }
        }

        files = results.sorted {
            $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending
        }
        state = .finished
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
            let ext = url.pathExtension.lowercased()
            guard supportedExtensions.contains(ext) || unsupportedAudioExtensions.contains(ext),
                  (try? url.resourceValues(forKeys: Set(keys)).isRegularFile) == true
            else { continue }
            urls.append(url)
        }
        return urls
    }

    nonisolated private static func inspect(_ url: URL) async -> AudioFile {
        let ext = url.pathExtension.lowercased()
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0

        func unreadable() -> AudioFile {
            AudioFile(url: url, fileName: url.lastPathComponent, fileExtension: ext,
                      sizeBytes: size, duration: nil,
                      title: nil, artist: nil, album: nil,
                      artworkThumbnail: nil,
                      year: nil, genre: nil, trackNumber: nil,
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
