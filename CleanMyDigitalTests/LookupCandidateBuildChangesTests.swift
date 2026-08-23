//
//  LookupCandidateBuildChangesTests.swift
//  CleanMyDigitalTests
//

import Testing
import Foundation
@testable import CleanMyDigital

/// Verifies `LookupCandidate.buildChanges(fillable:discogsToken:)` — the
/// field-by-field mapping shared between the per-file comparison views
/// (`MetadataLookupView.swift`) and the bulk "Apply Found Matches" flow
/// (`ApplyFoundMatchesSheetView`). Artwork cases are limited to
/// "wanted but no URL available", so these never hit the network — the
/// mapping logic itself is what's under test, not `ArtworkDownloader`.
struct LookupCandidateBuildChangesTests {

    // MARK: - Discogs

    @Test func discogsFillsExactlyTheRequestedReleaseLevelFields() async throws {
        let release = Self.makeRelease(
            title: "2Pac - Greatest Hits", year: "1998", genre: ["Hip Hop"], style: ["Gangsta Rap"])
        let changes = try await LookupCandidate.discogs(release)
            .buildChanges(fillable: [.artist, .album, .year, .genre], discogsToken: "token")

        #expect(changes.artist == "2Pac")
        #expect(changes.album == "Greatest Hits")
        #expect(changes.year == "1998")
        #expect(changes.genre == "Hip Hop, Gangsta Rap")
        #expect(changes.artworkJPEG == nil)
    }

    @Test func discogsNeverFillsTitleOrTrackNumber() async throws {
        // Even if a caller mistakenly requested them, the shared mapping
        // has no track data to draw from for a bare LookupCandidate — only
        // the per-file flow's own tracklist-match step can fill these.
        let release = Self.makeRelease(title: "2Pac - Greatest Hits")
        let changes = try await LookupCandidate.discogs(release)
            .buildChanges(fillable: [.title, .trackNumber], discogsToken: "token")

        #expect(changes.title == nil)
        #expect(changes.trackNumber == nil)
        #expect(changes.isEmpty)
    }

    @Test func discogsOnlyFillsWhatsInFillable() async throws {
        let release = Self.makeRelease(title: "2Pac - Greatest Hits", year: "1998")
        let changes = try await LookupCandidate.discogs(release)
            .buildChanges(fillable: [.artist], discogsToken: "token")

        #expect(changes.artist == "2Pac")
        #expect(changes.year == nil)
        #expect(changes.album == nil)
    }

    @Test func discogsGenreIsNilRatherThanEmptyStringWhenTheresNoGenreOrStyle() async throws {
        let release = Self.makeRelease(title: "2Pac - Greatest Hits", genre: nil, style: nil)
        let changes = try await LookupCandidate.discogs(release)
            .buildChanges(fillable: [.genre], discogsToken: "token")

        #expect(changes.genre == nil)
    }

    @Test func discogsSkipsArtworkWhenNoURLIsAvailable() async throws {
        let release = Self.makeRelease(title: "2Pac - Greatest Hits", thumb: nil, coverImage: nil)
        let changes = try await LookupCandidate.discogs(release)
            .buildChanges(fillable: [.artwork], discogsToken: "token")

        #expect(changes.artworkJPEG == nil)
    }

    // MARK: - MusicBrainz

    @Test func musicBrainzFillsExactlyTheRequestedFields() async throws {
        let recording = Self.makeRecording(
            title: "Changes", artistNames: "2Pac", releaseTitle: "Greatest Hits", releaseDate: "1998-01-01")
        let changes = try await LookupCandidate.musicBrainz(recording)
            .buildChanges(fillable: [.title, .artist, .album, .year], discogsToken: "")

        #expect(changes.title == "Changes")
        #expect(changes.artist == "2Pac")
        #expect(changes.album == "Greatest Hits")
        #expect(changes.year == "1998")
        #expect(changes.artworkJPEG == nil)
    }

    @Test func musicBrainzOnlyFillsWhatsInFillable() async throws {
        let recording = Self.makeRecording(title: "Changes", artistNames: "2Pac")
        let changes = try await LookupCandidate.musicBrainz(recording)
            .buildChanges(fillable: [.title], discogsToken: "")

        #expect(changes.title == "Changes")
        #expect(changes.artist == nil)
        #expect(changes.isEmpty == false)
    }

    @Test func musicBrainzSkipsArtworkWhenTheresNoReleaseID() async throws {
        let recording = Self.makeRecording(title: "Changes", artistNames: "2Pac", releaseID: nil)
        let changes = try await LookupCandidate.musicBrainz(recording)
            .buildChanges(fillable: [.artwork], discogsToken: "")

        #expect(changes.artworkJPEG == nil)
        #expect(changes.isEmpty)
    }

    @Test func buildChangesReturnsEmptyChangesWhenFillableIsEmpty() async throws {
        let release = Self.makeRelease(title: "2Pac - Greatest Hits", year: "1998")
        let changes = try await LookupCandidate.discogs(release).buildChanges(fillable: [], discogsToken: "token")
        #expect(changes.isEmpty)
    }

    // MARK: - Fixtures

    private static func makeRelease(
        title: String, year: String? = nil, genre: [String]? = nil, style: [String]? = nil,
        thumb: String? = "https://example.com/thumb.jpg", coverImage: String? = nil
    ) -> DiscogsRelease {
        DiscogsRelease(
            id: 1, title: title, year: year, genre: genre, style: style,
            label: nil, format: nil, thumb: thumb, coverImage: coverImage)
    }

    private static func makeRecording(
        title: String, artistNames: String, releaseTitle: String? = nil,
        releaseDate: String? = nil, releaseID: String? = "some-release-id"
    ) -> MusicBrainzRecording {
        MusicBrainzRecording(
            id: "1", title: title, artistNames: artistNames,
            releaseTitle: releaseTitle, releaseDate: releaseDate, releaseID: releaseID)
    }
}
