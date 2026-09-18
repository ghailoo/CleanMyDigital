//
//  CollectionPlannerTests.swift
//  CleanMyDigitalTests
//

import Testing
import Foundation
@testable import CleanMyDigital

struct CollectionPlannerTests {
    @Test func groupsMixesUnderReleaseNameStrippedOfMixSuffix() {
        let clubMix = Self.makeFile(
            path: "/Library/Singles/2 In A Room/2 In A Room - Ahora Es (Club Mix).flac",
            title: "Ahora Es (Club Mix)", category: .singles)
        let radioEdit = Self.makeFile(
            path: "/Library/Singles/2 In A Room/2 In A Room - Ahora Es (Radio Edit).flac",
            title: "Ahora Es (Radio Edit)", category: .singles)

        let proposals = CollectionPlanner.plan(for: [clubMix, radioEdit])
            .sorted { $0.file.fileName < $1.file.fileName }
        #expect(proposals.count == 2)
        #expect(proposals[0].releaseFolderName == "Artist - Ahora Es")
        #expect(proposals[0].proposedRelativePath == "Artist - Ahora Es/2 In A Room - Ahora Es (Club Mix).flac")
        #expect(proposals[1].releaseFolderName == "Artist - Ahora Es")
        #expect(proposals[1].proposedRelativePath == "Artist - Ahora Es/2 In A Room - Ahora Es (Radio Edit).flac")
    }

    @Test func titleWithoutMixSuffixUsesWholeTitle() {
        let file = Self.makeFile(
            path: "/Library/Singles/808 State/track.flac",
            title: "Pacific 0101", category: .singles)

        let proposals = CollectionPlanner.plan(for: [file])
        #expect(proposals.first?.releaseFolderName == "Artist - Pacific 0101")
        #expect(proposals.first?.proposedRelativePath == "Artist - Pacific 0101/track.flac")
    }

    /// No Title tag: the filename carries it, so the file is still collected
    /// rather than silently skipped.
    @Test func filesMissingTitleFallBackToTheFileName() {
        let file = Self.makeFile(
            path: "/Library/Singles/YBU/02 - YBU - Soul Magic (funk vocal version) (feat. Jonell).flac",
            title: nil, category: .singles, artist: "YBU")

        #expect(CollectionPlanner.plan(for: [file]).first?.releaseFolderName == "YBU - Soul Magic")
    }

    @Test func stripsABracketedMixSuffixToo() {
        let file = Self.makeFile(
            path: "/Library/Singles/Whitney Houston/09 My Love Is Your Love [Wyclef Remix].m4a",
            title: "My Love Is Your Love (Radio Edit) [Wyclef Remix]", category: .singles)

        #expect(CollectionPlanner.plan(for: [file]).first?.releaseFolderName == "Artist - My Love Is Your Love")
    }

    @Test func albumsAndCompilationsAreSkipped() {
        let album = Self.makeFile(
            path: "/Library/Albums/Artist/Album/01 track.flac",
            title: "Track (Remaster)", category: .albums)
        let compilation = Self.makeFile(
            path: "/Library/Compilations/Various/track.flac",
            title: "Track (Remaster)", category: .compilations)

        #expect(CollectionPlanner.plan(for: [album, compilation]).isEmpty)
    }

    @Test func fileAlreadyInsideMatchingReleaseFolderGetsNoProposal() {
        let file = Self.makeFile(
            path: "/Library/Singles/2 In A Room/Artist - Ahora Es/2 In A Room - Ahora Es (Club Mix).flac",
            title: "Ahora Es (Club Mix)", category: .singles)

        #expect(CollectionPlanner.plan(for: [file]).isEmpty)
    }

    @Test func sanitizesPathHostileCharactersInReleaseName() {
        let file = Self.makeFile(
            path: "/Library/Singles/AC-DC/track.flac",
            title: "Rock / Roll: Ain't Noise Pollution (12\" Mix)", category: .singles)

        let proposals = CollectionPlanner.plan(for: [file])
        #expect(proposals.first?.releaseFolderName == "Artist - Rock - Roll- Ain't Noise Pollution")
    }

    // MARK: - Fixture

    private static func makeFile(
        path: String,
        title: String?,
        category: LibraryCategory,
        artist: String? = "Artist"
    ) -> AudioFile {
        let url = URL(fileURLWithPath: path)
        return AudioFile(
            url: url,
            fileName: url.lastPathComponent,
            fileExtension: url.pathExtension,
            sizeBytes: 1024,
            duration: 180,
            bitrateKbps: nil,
            title: title,
            artist: artist,
            album: "Album",
            artworkThumbnail: nil,
            year: "2000",
            genre: "Electronic",
            trackNumber: nil,
            category: category,
            expectedArtist: "Artist",
            isReadable: true
        )
    }
}
