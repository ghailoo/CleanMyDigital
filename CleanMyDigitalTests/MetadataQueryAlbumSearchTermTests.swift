//
//  MetadataQueryAlbumSearchTermTests.swift
//  CleanMyDigitalTests
//

import Testing
import Foundation
@testable import CleanMyDigital

/// Verifies `MetadataQuery.strippingDiscAnnotation(from:)` and
/// `MetadataQuery.albumSearchTerm(for:)` — the album/release-title search
/// term shared by `DiscogsQuery`/`MusicBrainzQuery`/`DiscogsAlbumQuery`.
struct MetadataQueryAlbumSearchTermTests {
    // MARK: - strippingDiscAnnotation: real disc/CD markers get stripped

    @Test func stripsAHyphenatedCDMarker() {
        #expect(MetadataQuery.strippingDiscAnnotation(from: "Maxi Power Best Of 94 (CD-1)") == "Maxi Power Best Of 94")
    }

    @Test func stripsACDMarkerWithNoHyphen() {
        #expect(MetadataQuery.strippingDiscAnnotation(from: "Best Of 94 (CD1)") == "Best Of 94")
    }

    @Test func stripsACDMarkerWithASpaceInsteadOfAHyphen() {
        #expect(MetadataQuery.strippingDiscAnnotation(from: "Best Of 94 (CD 2)") == "Best Of 94")
    }

    @Test func stripsABracketedDiscMarker() {
        #expect(MetadataQuery.strippingDiscAnnotation(from: "Best Of 94 [Disc 1]") == "Best Of 94")
    }

    @Test func stripsADiskMarker() {
        #expect(MetadataQuery.strippingDiscAnnotation(from: "Best Of 94 (Disk 2)") == "Best Of 94")
    }

    @Test func stripsRegardlessOfCase() {
        #expect(MetadataQuery.strippingDiscAnnotation(from: "Best Of 94 (cd-1)") == "Best Of 94")
    }

    // MARK: - strippingDiscAnnotation: must NOT strip Vol./Volume/Part

    /// The exact regression this is guarding against: this library has a
    /// real compilation folder named "100% DJ Hits '97 Vol. 1" — stripping
    /// "Vol. 1" would break a search that currently works.
    @Test func doesNotStripAVolumeAbbreviation() {
        let term = "100% DJ Hits '97 Vol. 1"
        #expect(MetadataQuery.strippingDiscAnnotation(from: term) == term)
    }

    @Test func doesNotStripTheWordVolume() {
        let term = "Dance Hits Volume 2"
        #expect(MetadataQuery.strippingDiscAnnotation(from: term) == term)
    }

    @Test func doesNotStripTheWordPart() {
        let term = "Some Compilation Part 2"
        #expect(MetadataQuery.strippingDiscAnnotation(from: term) == term)
    }

    @Test func leavesATermWithNoTrailingDiscMarkerUnchanged() {
        let term = "Maxi Power Best Of 94"
        #expect(MetadataQuery.strippingDiscAnnotation(from: term) == term)
    }

    /// Only a *trailing* marker is stripped — one that isn't at the very
    /// end is left alone rather than guessed at.
    @Test func doesNotStripADiscMarkerThatIsNotTrailing() {
        let term = "(CD-1) Best Of 94"
        #expect(MetadataQuery.strippingDiscAnnotation(from: term) == term)
    }

    // MARK: - albumSearchTerm: prefers the Album tag, falls back to the folder

    @Test func albumSearchTermUsesTheAlbumTagWhenPresent() {
        let file = Self.makeFile(path: "/Music/Compilations/Maxi Power Best Of 94 (CD-1)/01 Track.flac",
                                  album: "Maxi Power Best Of 94 (CD-1)")
        #expect(MetadataQuery.albumSearchTerm(for: file) == "Maxi Power Best Of 94")
    }

    @Test func albumSearchTermFallsBackToTheContainingFolderNameWhenTheTagIsEmpty() {
        let file = Self.makeFile(path: "/Music/Compilations/Maxi Power Best Of 94 (CD-1)/01 Track.flac", album: nil)
        #expect(MetadataQuery.albumSearchTerm(for: file) == "Maxi Power Best Of 94")
    }

    @Test func albumSearchTermFallsBackToTheFolderNameWhenTheTagIsAnEmptyString() {
        let file = Self.makeFile(path: "/Music/Compilations/Best Of 94/01 Track.flac", album: "")
        #expect(MetadataQuery.albumSearchTerm(for: file) == "Best Of 94")
    }

    @Test func albumSearchTermStripsTheDiscMarkerFromTheFolderFallbackToo() {
        let file = Self.makeFile(path: "/Music/Compilations/Best Of 94 [Disc 2]/01 Track.flac", album: nil)
        #expect(MetadataQuery.albumSearchTerm(for: file) == "Best Of 94")
    }

    @Test func albumSearchTermDoesNotStripAVolumeSuffixFromTheTag() {
        let file = Self.makeFile(
            path: "/Music/Compilations/100% DJ Hits '97 Vol. 1/01 Track.flac", album: "100% DJ Hits '97 Vol. 1")
        #expect(MetadataQuery.albumSearchTerm(for: file) == "100% DJ Hits '97 Vol. 1")
    }

    // MARK: - Fixture

    private static func makeFile(path: String, album: String?) -> AudioFile {
        let url = URL(fileURLWithPath: path)
        return AudioFile(
            url: url,
            fileName: url.lastPathComponent,
            fileExtension: url.pathExtension,
            sizeBytes: 1024,
            duration: 180,
            bitrateKbps: nil,
            title: "Title",
            artist: "Artist",
            album: album,
            artworkThumbnail: nil,
            year: "1994",
            genre: "Dance",
            trackNumber: "1",
            category: .compilations,
            expectedArtist: nil,
            isReadable: true
        )
    }
}
