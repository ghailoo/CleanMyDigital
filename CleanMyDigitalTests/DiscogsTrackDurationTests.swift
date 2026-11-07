//
//  DiscogsTrackDurationTests.swift
//  CleanMyDigitalTests
//

import Foundation
import Testing
@testable import CleanMyDigital

/// The duration signal behind the batch lookup's corroboration step: a
/// bootleg can be named anything, but it's still the same number of seconds
/// long. Pure — the network part lives in `LibraryScanner`.
@Suite struct DiscogsTrackDurationTests {
    private static func detail(_ durations: [String?], titles: [String]? = nil) throws -> DiscogsReleaseDetail {
        let tracks = durations.enumerated().map { index, duration -> String in
            let field = duration.map { "\"duration\": \"\($0)\"" } ?? "\"duration\": null"
            let title = titles?[index] ?? "Track \(index + 1)"
            return "{\"position\": \"\(index + 1)\", \"title\": \"\(title)\", \(field)}"
        }.joined(separator: ",")
        let json = """
        {"id": 1, "title": "The Nightcrawlers* - Push The Feeling On (Remixes)",
         "tracklist": [\(tracks)]}
        """
        return try JSONDecoder().decode(DiscogsReleaseDetail.self, from: Data(json.utf8))
    }

    @Test func readsMinutesAndHours() throws {
        let d = try Self.detail(["6:13", "1:06:13", "0:45"])
        #expect(d.tracks[0].seconds == 373)
        #expect(d.tracks[1].seconds == 3973)
        #expect(d.tracks[2].seconds == 45)
    }

    /// An unreadable length must never read as zero — zero would match a
    /// file whose own duration failed to decode.
    @Test func anUnreadableLengthIsNil() throws {
        let d = try Self.detail([nil, "", "unknown", "6", "6:13:45:02"])
        #expect(d.tracks.allSatisfy { $0.seconds == nil })
    }

    /// The real release from the screenshot: the file measures 6:13 and the
    /// tracklist says 6:13.
    @Test func aTrackOfTheSameLengthIsFound() throws {
        let d = try Self.detail(["3:10", "6:13", "8:21", "6:00"])
        #expect(d.hasTrack(ofDuration: 373))
    }

    /// The user's own tally: a correct pressing routinely reads 4-6 seconds
    /// off the file. Seven is the limit.
    @Test func sixSecondsEitherWayStillCounts() throws {
        let d = try Self.detail(["6:13"])
        for offset in [-7, -6, -4, 0, 4, 6, 7] {
            #expect(d.hasTrack(ofDuration: TimeInterval(373 + offset)),
                    "\(offset)s off should still count")
        }
        #expect(!d.hasTrack(ofDuration: 373 + 8))
        #expect(!d.hasTrack(ofDuration: 373 - 8))
    }

    @Test func anotherMixOnTheSameReleaseIsNotTheSameLength() throws {
        let d = try Self.detail(["3:10", "8:21", "6:00"])
        #expect(!d.hasTrack(ofDuration: 373))   // 6:13 is not among them
    }

    @Test func anUnknownFileLengthNeverMatches() throws {
        let d = try Self.detail(["6:13"])
        #expect(!d.hasTrack(ofDuration: 0))
    }

    /// The album case: the release is called "Lets Push It" and the file is
    /// "Just Like Before", track 5 on it. The release's own name scores
    /// nothing — but its tracklist holds this title at this length.
    @Test func theTracklistCanAgreeOnBothTitleAndLength() throws {
        let album = try Self.detail(
            ["4:03", "3:47", "3:50", "4:41", "4:04", "5:06"],
            titles: ["Push The Feeling On (MK Dub Revisited Edit)", "Surrender Your Love",
                     "Don't Let The Feeling Go", "Should I Ever (Fall In Love)",
                     "Just Like Before", "Lift Me Up"])
        #expect(album.hasTrack(named: "Just Like Before", ofDuration: 244))

        // Same title, wrong length — a different pressing or a different cut.
        #expect(!album.hasTrack(named: "Just Like Before", ofDuration: 300))
        // Right length, but that title isn't on this release at all.
        #expect(!album.hasTrack(named: "Sax House", ofDuration: 244))
        #expect(album.hasTrack(ofDuration: 244))   // the weaker test still passes
    }

    @Test func titleAndLengthNeedsBothToBeKnown() throws {
        let noTimes = try Self.detail([nil], titles: ["Just Like Before"])
        #expect(!noTimes.hasTrack(named: "Just Like Before", ofDuration: 244))
        let noDuration = try Self.detail(["4:04"], titles: ["Just Like Before"])
        #expect(!noDuration.hasTrack(named: "Just Like Before", ofDuration: 0))
    }
}
