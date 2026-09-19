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

        // Checks for a genuinely non-empty existing value, not just the
        // atom's presence — some M4As carry an empty or whitespace-only
        // Year/Genre atom (present, but with nothing readable in it), which
        // the scanner already treats as missing. Checking presence alone
        // would let that empty atom block ever writing a real value.
        //
        // Uses the async `load(.stringValue)`/`load(.dataValue)` API
        // rather than the synchronous `.stringValue`/`.dataValue`/`.value`
        // properties — those are deprecated for items obtained via
        // `asset.load(.metadata)` and (confirmed empirically) unreliably
        // return nil for them, which made this check silently never see
        // any existing value at all.
        func hasExisting(_ identifier: AVMetadataIdentifier) async -> Bool {
            for item in AVMetadataItem.metadataItems(from: existingItems, filteredByIdentifier: identifier) {
                // A text item counts only if it holds real text — a blank one's
                // raw bytes (e.g. a single space) are not a value. Checking
                // `.dataValue` for text items too made blank Year/Genre atoms
                // read as present, so they were never filled.
                if let string = try? await item.load(.stringValue) {
                    if !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
                    continue
                }
                if let data = try? await item.load(.dataValue), !data.isEmpty {
                    return true
                }
            }
            return false
        }

        func stringItem(_ identifier: AVMetadataIdentifier, _ value: String) -> AVMetadataItem {
            let item = AVMutableMetadataItem()
            item.identifier = identifier
            item.value = value as NSString
            item.extendedLanguageTag = "und"
            return item
        }

        let hasTitle = await hasExisting(.iTunesMetadataSongName)
        let hasArtist = await hasExisting(.iTunesMetadataArtist)
        let hasAlbum = await hasExisting(.iTunesMetadataAlbum)
        let hasYear = await hasExisting(.iTunesMetadataReleaseDate)
        let hasGenre = await hasExisting(.iTunesMetadataUserGenre)
        let hasTrackNumber = await hasExisting(.iTunesMetadataTrackNumber)
        let hasArtwork = await hasExisting(.commonIdentifierArtwork)

        var newItems: [AVMetadataItem] = []

        if let title = changes.title, !hasTitle || changes.replaces(.title) {
            newItems.append(stringItem(.iTunesMetadataSongName, title))
        }
        if let artist = changes.artist, !hasArtist || changes.replaces(.artist) {
            newItems.append(stringItem(.iTunesMetadataArtist, artist))
        }
        if let album = changes.album, !hasAlbum || changes.replaces(.album) {
            newItems.append(stringItem(.iTunesMetadataAlbum, album))
        }
        if let year = changes.year, !hasYear || changes.replaces(.year) {
            newItems.append(stringItem(.iTunesMetadataReleaseDate, year))
        }
        if let genre = changes.genre, !hasGenre || changes.replaces(.genre) {
            newItems.append(stringItem(.iTunesMetadataUserGenre, genre))
        }
        if let trackNumber = changes.trackNumber, !hasTrackNumber || changes.replaces(.trackNumber) {
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
        if let artworkJPEG = changes.artworkJPEG, !hasArtwork {
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

        // Drop existing items for every identifier being written — they're
        // blank (or a replaced Album) by construction — so the file never
        // carries two, with readers picking the stale blank one first.
        let writtenIdentifiers = Set(newItems.compactMap(\.identifier))
        let keptItems = existingItems.filter { item in
            guard let identifier = item.identifier else { return true }
            return !writtenIdentifiers.contains(identifier)
        }
        exportSession.metadata = keptItems + newItems

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
