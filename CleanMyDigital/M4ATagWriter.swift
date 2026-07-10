//
//  M4ATagWriter.swift
//  CleanMyDigital
//

import AVFoundation
import CoreMedia
import Foundation

/// Writes tags into an M4A by re-exporting it with `AVAssetExportSession`
/// using the passthrough preset (no re-encoding — the audio is copied as-is)
/// and a merged metadata item list.
enum M4ATagWriter {
    static func write(_ changes: TagChanges, to url: URL) async throws {
        let asset = AVURLAsset(url: url)
        let existingItems: [AVMetadataItem]
        do {
            existingItems = try await asset.load(.metadata)
        } catch {
            throw TagWriteError.underlying(error)
        }

        func hasExisting(_ identifier: AVMetadataIdentifier) -> Bool {
            !AVMetadataItem.metadataItems(from: existingItems, filteredByIdentifier: identifier).isEmpty
        }

        func stringItem(_ identifier: AVMetadataIdentifier, _ value: String) -> AVMetadataItem {
            let item = AVMutableMetadataItem()
            item.identifier = identifier
            item.value = value as NSString
            item.extendedLanguageTag = "und"
            return item
        }

        var newItems: [AVMetadataItem] = []

        if let title = changes.title, !hasExisting(.iTunesMetadataSongName) {
            newItems.append(stringItem(.iTunesMetadataSongName, title))
        }
        if let artist = changes.artist, !hasExisting(.iTunesMetadataArtist) {
            newItems.append(stringItem(.iTunesMetadataArtist, artist))
        }
        if let album = changes.album, !hasExisting(.iTunesMetadataAlbum) {
            newItems.append(stringItem(.iTunesMetadataAlbum, album))
        }
        if let year = changes.year, !hasExisting(.iTunesMetadataReleaseDate) {
            newItems.append(stringItem(.iTunesMetadataReleaseDate, year))
        }
        if let genre = changes.genre, !hasExisting(.iTunesMetadataUserGenre) {
            newItems.append(stringItem(.iTunesMetadataUserGenre, genre))
        }
        if let trackNumber = changes.trackNumber, !hasExisting(.iTunesMetadataTrackNumber) {
            let (part, total) = TagWriteHelpers.parseTrackPosition(trackNumber)
            // The `trkn` iTunes atom is packed binary: 2 bytes padding,
            // 2 bytes track number, 2 bytes total tracks, 2 bytes padding.
            var bytes = [UInt8](repeating: 0, count: 8)
            bytes[2] = UInt8((part >> 8) & 0xFF)
            bytes[3] = UInt8(part & 0xFF)
            if let total {
                bytes[4] = UInt8((total >> 8) & 0xFF)
                bytes[5] = UInt8(total & 0xFF)
            }
            let item = AVMutableMetadataItem()
            item.identifier = .iTunesMetadataTrackNumber
            item.value = Data(bytes) as NSData
            newItems.append(item)
        }
        if let artworkJPEG = changes.artworkJPEG, !hasExisting(.commonIdentifierArtwork) {
            let item = AVMutableMetadataItem()
            item.identifier = .iTunesMetadataCoverArt
            item.dataType = kCMMetadataBaseDataType_JPEG as String
            item.value = artworkJPEG as NSData
            newItems.append(item)
        }

        guard !newItems.isEmpty else { throw TagWriteError.noChanges }

        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw TagWriteError.underlying(CocoaError(.fileWriteUnknown))
        }

        let tempURL = url.deletingLastPathComponent()
            .appendingPathComponent(".cleanmydigital-\(UUID().uuidString)")
            .appendingPathExtension("m4a")

        exportSession.metadata = existingItems + newItems

        do {
            try await exportSession.export(to: tempURL, as: .m4a)
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            throw TagWriteError.underlying(error)
        }

        do {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tempURL)
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            throw TagWriteError.underlying(error)
        }
    }
}
