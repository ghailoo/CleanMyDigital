//
//  TrackInspectorTests.swift
//  CleanMyDigitalTests
//

import Testing
import Foundation
@testable import CleanMyDigital

struct TrackInspectorTests {
    @Test func sharedValueWhenAllAgreeMixedOtherwise() {
        let a = Self.file("a.flac", title: "Close To You", year: "1990")
        let b = Self.file("b.flac", title: "Close To You (Dub)", year: "1990")
        #expect(TrackInspector.shared(.year, in: [a, b]) == .value("1990"))
        #expect(TrackInspector.shared(.title, in: [a, b]) == .mixed)
    }

    @Test func editsBecomeExplicitReplacementsSkippingUnchangedAndEmpty() {
        let file = Self.file("a.flac", title: "Close To You", year: "1990")
        let changes = TrackInspector.changes(for: file, edits: [.title: "Close To You", .year: " 1991 ", .genre: "  "])
        #expect(changes.title == nil)          // unchanged
        #expect(changes.year == "1991")        // trimmed
        #expect(changes.genre == nil)          // empty can't clear a tag
        #expect(changes.replacing == [.year])
    }

    @Test func apeBuilderReplacesAnEditedTitleInsteadOfDroppingIt() {
        let existing = [APEv2Tag.Item(key: "Title", isBinary: false, valueBytes: Array("Old".utf8))]
        var changes = TagChanges()
        changes.title = "New"
        changes.replacing = [.title]
        let items = APEv2TagBuilder.build(changes: changes, existing: existing)
        #expect(APEv2TagBuilder.textValue("Title", in: items) == "New")
        #expect(items.filter { $0.key == "Title" }.count == 1)
    }

    /// Grouping is where the Maxi Track tag lands, so the inspector has to
    /// show it and be able to correct it by hand.
    @Test func groupingIsEditableAndOverwrites() {
        #expect(TrackInspector.editableFields.contains(.grouping))

        var file = Self.file("a.flac", title: "Rapture", year: "2001")
        file.grouping = "Maxi Track"
        #expect(TrackInspector.value(of: .grouping, in: file) == "Maxi Track")

        let changes = TrackInspector.changes(for: file, edits: [.grouping: "Classics"])
        #expect(changes.grouping == "Classics")
        #expect(changes.replaces(.grouping))   // a manual edit overwrites

        // Re-typing what's already there writes nothing.
        #expect(TrackInspector.changes(for: file, edits: [.grouping: "Maxi Track"]).isEmpty)
    }

    private static func file(_ name: String, title: String?, year: String?) -> AudioFile {
        let url = URL(fileURLWithPath: "/Music/Maxi Priest/\(name)")
        return AudioFile(
            url: url, fileName: name, fileExtension: "flac", sizeBytes: 1, duration: 1, bitrateKbps: nil,
            title: title, artist: "Maxi Priest", album: nil, artworkThumbnail: nil, year: year,
            genre: nil, trackNumber: nil, category: .singles, expectedArtist: nil, isReadable: true)
    }
}
