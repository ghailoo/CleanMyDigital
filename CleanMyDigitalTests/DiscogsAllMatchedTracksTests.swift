//
//  DiscogsAllMatchedTracksTests.swift
//  CleanMyDigitalTests
//

import Testing
import Foundation
@testable import CleanMyDigital

/// Verifies `DiscogsReleaseDetail.allMatchedTracks(for:)` — the multi-match
/// helper used only by the album-completeness "what's covered" check, so a
/// combined/segued rip like "06 - Misterio - Interlude.flac" can credit
/// every shorter track title concatenated into its name instead of just
/// the one `autoMatchedTrack(for:)` would pick.
///
/// `DiscogsReleaseDetail`'s tracklist storage is private (by design — see
/// `autoMatchedTrack(for:)`'s own doc comment), so fixtures are built by
/// decoding a minimal JSON payload shaped like Discogs' real
/// `/releases/{id}` response, the same way the app itself constructs one.
struct DiscogsAllMatchedTracksTests {
    @Test func autoMatchIgnoresPunctuationDifferences() throws {
        let detail = try Self.makeDetail(trackTitles: ["Intro", "Ain't Talkin' 'Bout Dub"])

        #expect(detail.autoMatchedTrack(for: "Apollo Four Forty - Ain't Talkin' Bout Dub")?.title == "Ain't Talkin' 'Bout Dub")
    }

    @Test func creditsACompoundFilenameForBothConcatenatedTracks() throws {
        let detail = try Self.makeDetail(trackTitles: ["Intro", "Mistério", "Interlude", "Outro"])

        let matched = detail.allMatchedTracks(for: "Misterio - Interlude")

        #expect(Set(matched.map(\.title)) == ["Mistério", "Interlude"])
    }

    @Test func returnsEmptyWhenThereIsNoPrimaryMatchAtAll() throws {
        let detail = try Self.makeDetail(trackTitles: ["Intro", "Mistério", "Interlude", "Outro"])

        #expect(detail.allMatchedTracks(for: "Totally Unrelated Filename").isEmpty)
    }

    @Test func returnsJustThePrimaryMatchWhenNothingElseAlsoMatches() throws {
        let detail = try Self.makeDetail(trackTitles: ["Intro", "Changes", "Outro"])

        let matched = detail.allMatchedTracks(for: "Changes")

        #expect(matched.map(\.title) == ["Changes"])
    }

    @Test func includesThePrimaryMatchEvenWhenOnlyTheReverseDirectionMatched() throws {
        // "Changes" only matches "Changes (Radio Edit)" via the track-contains-file
        // direction, not the file-contains-track direction this function's own
        // supplementary pass checks — the primary match must still come through.
        let detail = try Self.makeDetail(trackTitles: ["Changes (Radio Edit)", "Outro"])

        let matched = detail.allMatchedTracks(for: "Changes")

        #expect(matched.map(\.title) == ["Changes (Radio Edit)"])
    }

    @Test func excludesAShortGenericSupplementaryTitleEvenWhenItLiterallyAppears() throws {
        let detail = try Self.makeDetail(trackTitles: ["Interlude", "Love"])

        let matched = detail.allMatchedTracks(for: "Love Interlude")

        #expect(matched.map(\.title) == ["Interlude"])
    }

    // MARK: - Fixture

    private static func makeDetail(trackTitles: [String]) throws -> DiscogsReleaseDetail {
        let tracklistJSON = trackTitles.enumerated().map { index, title -> String in
            "{\"position\": \"\(index + 1)\", \"title\": \"\(title)\"}"
        }.joined(separator: ",")
        let json = """
        {
            "id": 12345,
            "title": "Various - Some Compilation",
            "tracklist": [\(tracklistJSON)]
        }
        """
        return try JSONDecoder().decode(DiscogsReleaseDetail.self, from: Data(json.utf8))
    }
}
