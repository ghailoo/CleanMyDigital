//
//  MaxiTrackPlannerTests.swift
//  CleanMyDigitalTests
//

import Foundation
import Testing
@testable import CleanMyDigital

@Suite struct MaxiTrackPlannerTests {
    private static func makeFile(
        name: String = "Artist - Track.flac",
        duration: TimeInterval? = 300,
        title: String? = "Track",
        grouping: String? = nil,
        isReadable: Bool = true
    ) -> AudioFile {
        let url = URL(fileURLWithPath: "/tmp/MaxiTrackPlannerTests/\(name)")
        return AudioFile(
            url: url, fileName: name, fileExtension: url.pathExtension,
            sizeBytes: 1024, duration: duration, bitrateKbps: 1000,
            title: title, artist: "Artist", album: "Album", artworkThumbnail: nil,
            year: "1999", genre: "House", trackNumber: nil, grouping: grouping,
            category: .singles, expectedArtist: nil, isReadable: isReadable)
    }

    @Test func fourMinutesExactlyIsNotAMaxiTrack() {
        #expect(MaxiTrackPlanner.plan(for: [Self.makeFile(duration: 240)]).isEmpty)
        #expect(MaxiTrackPlanner.plan(for: [Self.makeFile(duration: 241)]).count == 1)
    }

    @Test func shortTracksAndUnknownLengthsAreSkipped() {
        #expect(MaxiTrackPlanner.plan(for: [Self.makeFile(duration: 180)]).isEmpty)
        #expect(MaxiTrackPlanner.plan(for: [Self.makeFile(duration: nil)]).isEmpty)
        #expect(MaxiTrackPlanner.plan(for: [Self.makeFile(isReadable: false)]).isEmpty)
    }

    @Test func aFileThatAlreadyHasAGroupingIsLeftAlone() {
        #expect(MaxiTrackPlanner.plan(for: [Self.makeFile(grouping: "Trance Anthems")]).isEmpty)
        #expect(MaxiTrackPlanner.plan(for: [Self.makeFile(grouping: MaxiTrackPlanner.groupingValue)]).isEmpty)
        // An empty grouping tag is not a grouping.
        #expect(MaxiTrackPlanner.plan(for: [Self.makeFile(grouping: "")]).count == 1)
    }

    @Test func theNameRaisesTheConfidence() {
        let named = Self.makeFile(name: "Artist - Track (Extended Mix).flac")
        #expect(MaxiTrackPlanner.plan(for: [named]).first?.certainty == .nameAgrees)

        let plain = Self.makeFile(name: "Artist - Track.flac")
        #expect(MaxiTrackPlanner.plan(for: [plain]).first?.certainty == .durationOnly)
    }

    @Test func theTitleTagCountsToo() {
        let file = Self.makeFile(name: "01 track.flac", title: "Track (Maxi Version)")
        #expect(MaxiTrackPlanner.plan(for: [file]).first?.certainty == .nameAgrees)
    }

    @Test func everyHintIsRecognisedWhateverTheCase() {
        for hint in ["MAXI", "extended", "12 Inch", "12\"", "Long Version", "Club Mix"] {
            let file = Self.makeFile(name: "Artist - Track (\(hint)).flac", title: nil)
            #expect(MaxiTrackPlanner.nameSuggestsMaxi(file), "\(hint) should read as a maxi version")
        }
    }

    @Test func theChangeWritesOnlyTheGrouping() {
        let proposal = MaxiTrackProposal(file: Self.makeFile(), certainty: .durationOnly)
        let changes = MaxiTrackPlanner.changes(for: proposal)
        #expect(changes.grouping == "Maxi Track")
        #expect(changes.title == nil)
        #expect(changes.artist == nil)
        #expect(changes.replacing.isEmpty)   // never overwrites anything
    }
}

@Suite struct MaxiTrackNameEvidenceTests {
    private static func makeFile(_ name: String, _ duration: TimeInterval) -> AudioFile {
        let url = URL(fileURLWithPath: "/tmp/MaxiTrackPlannerTests/\(name)")
        return AudioFile(
            url: url, fileName: name, fileExtension: url.pathExtension,
            sizeBytes: 1024, duration: duration, bitrateKbps: 1000,
            title: nil, artist: "Artist", album: "Album", artworkThumbnail: nil,
            year: "1999", genre: "House", trackNumber: nil, grouping: nil,
            category: .singles, expectedArtist: nil, isReadable: true)
    }

    private static func certainty(_ name: String, _ duration: TimeInterval) -> MaxiTrackCertainty? {
        MaxiTrackPlanner.plan(for: [makeFile(name, duration)]).first?.certainty
    }

    /// The whole point of this pass: a remix of a four-minute single is the
    /// long pressing, and nothing in the old hint list said so.
    @Test func aRemixCountsAsAMaxiTrack() {
        #expect(Self.certainty("iiO - Rapture (John Creamer & Stephane K Remix).flac", 591) == .nameAgrees)
        #expect(Self.certainty("iiO - Rapture (Deep Dish Miami Dub).flac", 648) == .nameAgrees)
        #expect(Self.certainty("IIO - Rapture (Kenan Savrun Rework).wav", 518) == .nameAgrees)
    }

    /// A name that says "radio" or "original" just past four minutes is
    /// taken at its word and never offered at all.
    @Test func aShortFormNameJustOverFourMinutesIsLeftOut() {
        #expect(Self.certainty("iiO - Rapture (Original Radio Mix).flac", 254) == nil)
        #expect(Self.certainty("iiO - Rapture (Riva edit).flac", 245) == nil)
        #expect(Self.certainty("Kadoc - The Nighttrain (Original).flac", 295) == nil)
    }

    /// Past five minutes the clock disagrees too loudly — it stays in the
    /// list for a human to decide, but unticked.
    @Test func aShortFormNameThatRunsLongIsStillWorthALook() {
        #expect(Self.certainty("iiO - Rapture (original mix).flac", 407) == .durationOnly)
        #expect(Self.certainty("Artist - Track (Radio Edit).flac", 400) == .durationOnly)
    }

    /// "Original Extended Mix" says both things; the maxi hint wins.
    @Test func aMaxiHintOutranksAShortFormHint() {
        #expect(Self.certainty("iiO - Rapture (Original Extended Mix).flac", 404) == .nameAgrees)
        #expect(Self.certainty("iiO ft. Nadia Ali - Is It Love Inst Remix Remaster II (Original Mix).flac", 427) == .nameAgrees)
    }

    /// A bare "mix" counts too — but not when it's the short version's own
    /// name, where "mix" is just the noun after "radio" or "original".
    @Test func aBareMixCountsUnlessItIsARadioOrOriginalMix() {
        #expect(Self.certainty("iiO - Rapture (Riva mix).flac", 461) == .nameAgrees)
        #expect(Self.certainty("Kadoc - The Night Train (Merlyn's Cafe Sledge Mix).flac", 369) == .nameAgrees)
        #expect(Self.certainty("iiO - Rapture (Original Radio Mix).flac", 254) == nil)
        #expect(Self.certainty("Artist - Track (Original Mix).flac", 250) == nil)
        #expect(Self.certainty("Artist - Track (Original Mix).flac", 407) == .durationOnly)
    }

    /// Hints match whole words: an artist called Dubfire isn't a dub, and
    /// an "Editor's Cut" isn't an edit.
    @Test func hintsMatchWholeWordsOnly() {
        #expect(Self.certainty("Dubfire - Roadkill.flac", 300) == .durationOnly)
        #expect(Self.certainty("Artist - Track (Editorial).flac", 250) == .durationOnly)
    }
}
