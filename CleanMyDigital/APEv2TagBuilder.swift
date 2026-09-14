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
        func addTextIfMissing(_ key: String, _ value: String?) {
            guard let value, !value.isEmpty, !hasKey(key) else { return }
            items.append(APEv2Tag.Item(key: key, isBinary: false, valueBytes: Array(value.utf8)))
        }

        addTextIfMissing(titleKey, changes.title)
        addTextIfMissing(artistKey, changes.artist)
        if changes.replacesAlbum, changes.album?.isEmpty == false {
            items.removeAll { $0.key.caseInsensitiveCompare(albumKey) == .orderedSame }
        }
        addTextIfMissing(albumKey, changes.album)
        addTextIfMissing(yearKey, changes.year)
        addTextIfMissing(genreKey, changes.genre)
        addTextIfMissing(trackKey, changes.trackNumber)

        if let artworkJPEG = changes.artworkJPEG, !hasKey(coverArtFrontKey) {
            items.append(.coverArt(key: coverArtFrontKey, filename: "cover.jpg", data: artworkJPEG))
        }

        return items
    }

    /// Looks up a text field by key, case-insensitively — shared by
    /// `WavPackMetadataReader` so its reading and this builder's
    /// never-overwrite check agree on what "already present" means.
    static func textValue(_ key: String, in items: [APEv2Tag.Item]) -> String? {
        items.first { $0.key.caseInsensitiveCompare(key) == .orderedSame }?.textValue
    }
}
