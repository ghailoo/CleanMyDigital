//
//  APEv2TagBuilder.swift
//  CleanMyDigital
//

import Foundation

/// Builds the list of `APEv2Tag.Item`s for a `TagChanges` value, preserving
/// every item an existing tag already has and adding only the fields it's
/// missing — the APEv2 equivalent of `ID3TagBuilder`'s merge rule for the
/// ID3-tagged formats. Kept separate from `WavPackTagWriter` (and from
/// `APEv2Tag` itself, which knows nothing about `TagChanges`) so a native
/// Monkey's Audio (.ape) writer could reuse this unchanged later — see
/// `APEv2Tag.swift`'s doc comment.
///
/// Field names follow WavPack's own officially-recommended APEv2 key list
/// (WavPack5FileFormat.pdf §4.0): "Title", "Artist", "Album", "Year",
/// "Genre", "Track", "Cover Art (Front)".
enum APEv2TagBuilder {
    static let titleKey = "Title"
    static let artistKey = "Artist"
    static let albumKey = "Album"
    static let yearKey = "Year"
    static let genreKey = "Genre"
    static let trackKey = "Track"
    static let groupingKey = "Grouping"
    static let coverArtFrontKey = "Cover Art (Front)"

    /// Field keys are conventionally case-insensitive (foobar2000, Mp3tag,
    /// etc. all read/write "TITLE"/"Title"/"title" interchangeably), so
    /// presence checks compare that way rather than requiring an exact
    /// match to this app's own capitalization.
    static func build(changes: TagChanges, existing: [APEv2Tag.Item]) -> [APEv2Tag.Item] {
        var items = existing

        func hasKey(_ key: String) -> Bool {
            items.contains { $0.key.caseInsensitiveCompare(key) == .orderedSame }
        }
        /// A text field counts as present only when it holds something — a
        /// blank "Year" item is what a ripper leaves behind, not a value,
        /// and treating it as one meant it could never be filled.
        func hasTextValue(_ key: String) -> Bool {
            items.contains {
                $0.key.caseInsensitiveCompare(key) == .orderedSame
                    && !($0.textValue ?? "").trimmingCharacters(in: .whitespaces).isEmpty
            }
        }
        func addTextIfMissing(_ key: String, _ value: String?) {
            guard let value, !value.isEmpty, !hasTextValue(key) else { return }
            // Drop a blank one first, or the tag ends up carrying both.
            items.removeAll { $0.key.caseInsensitiveCompare(key) == .orderedSame && !$0.isBinary }
            items.append(APEv2Tag.Item(key: key, isBinary: false, valueBytes: Array(value.utf8)))
        }

        let keys: [(MetadataField, String)] = [
            (.title, titleKey), (.artist, artistKey), (.album, albumKey),
            (.year, yearKey), (.genre, genreKey), (.trackNumber, trackKey),
            (.grouping, groupingKey),
        ]
        for (field, key) in keys where changes.replaces(field) {
            items.removeAll { $0.key.caseInsensitiveCompare(key) == .orderedSame }
        }
        addTextIfMissing(titleKey, changes.title)
        addTextIfMissing(artistKey, changes.artist)
        addTextIfMissing(albumKey, changes.album)
        addTextIfMissing(yearKey, changes.year)
        addTextIfMissing(genreKey, changes.genre)
        addTextIfMissing(trackKey, changes.trackNumber)
        addTextIfMissing(groupingKey, changes.grouping)

        if let artworkJPEG = changes.artworkJPEG, !hasKey(coverArtFrontKey) {
            items.append(.coverArt(key: coverArtFrontKey, filename: "cover.jpg", data: artworkJPEG))
        }

        return items
    }

    /// Fills the shared native-metadata shape from APEv2 items — used by
    /// every APEv2-tagged format (WavPack, Monkey's Audio).
    static func fill(_ metadata: inout NativeAudioMetadata, from items: [APEv2Tag.Item]) {
        metadata.title = APEv2TagBuilder.textValue(APEv2TagBuilder.titleKey, in: items)
        metadata.artist = APEv2TagBuilder.textValue(APEv2TagBuilder.artistKey, in: items)
        metadata.album = APEv2TagBuilder.textValue(APEv2TagBuilder.albumKey, in: items)
        metadata.year = APEv2TagBuilder.textValue(APEv2TagBuilder.yearKey, in: items)
        metadata.genre = APEv2TagBuilder.textValue(APEv2TagBuilder.genreKey, in: items)
        metadata.trackNumber = APEv2TagBuilder.textValue(APEv2TagBuilder.trackKey, in: items)
        metadata.grouping = APEv2TagBuilder.textValue(APEv2TagBuilder.groupingKey, in: items)

        if let coverItem = items.first(where: {
            $0.key.caseInsensitiveCompare(APEv2TagBuilder.coverArtFrontKey) == .orderedSame
        }), let payload = coverItem.coverArtPayload {
            metadata.artworkData = payload.data
        }
    }

    /// Looks up a text field by key, case-insensitively — shared by
    /// `WavPackMetadataReader` so its reading and this builder's
    /// never-overwrite check agree on what "already present" means.
    static func textValue(_ key: String, in items: [APEv2Tag.Item]) -> String? {
        items.first { $0.key.caseInsensitiveCompare(key) == .orderedSame }?.textValue
    }
}
