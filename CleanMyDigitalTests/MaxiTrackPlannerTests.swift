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
