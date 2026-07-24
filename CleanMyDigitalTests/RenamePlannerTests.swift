//
//  RenamePlannerTests.swift
//  CleanMyDigitalTests
//

import Testing
import Foundation
@testable import CleanMyDigital

struct RenamePlannerTests {
    @Test func singlesTemplateIsArtistDashTitle() {
        let file = Self.makeFile(
            path: "/Library/Singles/808 State/track.flac",
            title: "Pacific 0101 (Remix Edit)", artist: "808 State",
            category: .singles)

        let proposals = RenamePlanner.plan(for: [file])
        #expect(proposals.count == 1)
        #expect(proposals.first?.proposedName == "808 State - Pacific 0101 (Remix Edit).flac")
    }

    @Test func albumsTemplateIncludesPaddedTrackNumber() {
        let file = Self.makeFile(
            path: "/Library/Albums/Boards of Canada/Music Has the Right to Children/02 track.flac",
            title: "Roygbiv", artist: "Boards of Canada", trackNumber: "3",
            category: .albums)

        let proposals = RenamePlanner.plan(for: [file])
        #expect(proposals.count == 1)
        #expect(proposals.first?.proposedName == "03 Boards of Canada - Roygbiv.flac")
    }

    @Test func albumsTemplateWithTrackTotalStillPadsJustThePart() {
        let file = Self.makeFile(
            path: "/Library/Albums/Artist/Album/track.flac",
            title: "Title", artist: "Artist", trackNumber: "7/12",
            category: .albums)

        let proposals = RenamePlanner.plan(for: [file])
        #expect(proposals.first?.proposedName == "07 Artist - Title.flac")
    }

    @Test func albumsTemplateFallsBackWithoutTrackNumber() {
        let file = Self.makeFile(
            path: "/Library/Compilations/Various/comp.flac",
            title: "Title", artist: "Artist", trackNumber: nil,
            category: .compilations)

        let proposals = RenamePlanner.plan(for: [file])
        #expect(proposals.first?.proposedName == "Artist - Title.flac")
    }

    @Test func filesMissingArtistOrTitleGetNoProposal() {
        let missingArtist = Self.makeFile(
            path: "/Library/Singles/X/a.flac", title: "Title", artist: nil, category: .singles)
        let missingTitle = Self.makeFile(
            path: "/Library/Singles/X/b.flac", title: nil, artist: "Artist", category: .singles)
        let missingBoth = Self.makeFile(
            path: "/Library/Singles/X/c.flac", title: nil, artist: nil, category: .singles)

        let proposals = RenamePlanner.plan(for: [missingArtist, missingTitle, missingBoth])
        #expect(proposals.isEmpty)
    }

    @Test func sanitizesSlashesColonsAndWhitespace() {
        let file = Self.makeFile(
            path: "/Library/Singles/AC-DC/track.flac",
            title: "Rock  /  Roll:   Ain't    Noise   Pollution",
            artist: "AC/DC",
            category: .singles)

        let proposals = RenamePlanner.plan(for: [file])
        #expect(proposals.first?.proposedName == "AC-DC - Rock - Roll- Ain't Noise Pollution.flac")
    }

    @Test func skipsFilesAlreadyNamedCorrectly() {
        let file = Self.makeFile(
            path: "/Library/Singles/808 State/808 State - Pacific 0101.flac",
            title: "Pacific 0101", artist: "808 State",
            category: .singles)

        let proposals = RenamePlanner.plan(for: [file])
        #expect(proposals.isEmpty)
    }

    @Test func proposesCaseOnlyRenamesAndFlagsThem() {
        let file = Self.makeFile(
            path: "/Library/Singles/808 State/808 state - pacific 0101.flac",
            title: "Pacific 0101", artist: "808 State",
            category: .singles)

        let proposals = RenamePlanner.plan(for: [file])
        #expect(proposals.count == 1)
        let proposal = try? #require(proposals.first)
        #expect(proposal?.proposedName == "808 State - Pacific 0101.flac")
        #expect(proposal?.isCaseOnlyChange == true)
    }

    @Test func collidingProposalsFromTwoFilesGetSuffixed() {
        let fileA = Self.makeFile(
            path: "/Library/Singles/Artist/a.flac", title: "Title", artist: "Artist", category: .singles)
        let fileB = Self.makeFile(
            path: "/Library/Singles/Artist/b.flac", title: "Title", artist: "Artist", category: .singles)

        let proposals = RenamePlanner.plan(for: [fileA, fileB])
            .sorted { $0.currentName < $1.currentName }
        #expect(proposals.count == 2)
        #expect(proposals[0].currentName == "a.flac")
        #expect(proposals[0].proposedName == "Artist - Title.flac")
        #expect(proposals[1].currentName == "b.flac")
        #expect(proposals[1].proposedName == "Artist - Title (2).flac")
    }

    @Test func collidesWithAnAlreadyCorrectlyNamedSibling() {
        // "Artist - Title.flac" already exists and keeps its name (its own
        // tags already match); the other file's proposal must not clobber it.
        let alreadyNamed = Self.makeFile(
            path: "/Library/Singles/Artist/Artist - Title.flac",
            title: "Title", artist: "Artist", category: .singles)
        let toRename = Self.makeFile(
            path: "/Library/Singles/Artist/original.flac",
            title: "Title", artist: "Artist", category: .singles)

        let proposals = RenamePlanner.plan(for: [alreadyNamed, toRename])
        #expect(proposals.count == 1)
        #expect(proposals.first?.currentName == "original.flac")
        #expect(proposals.first?.proposedName == "Artist - Title (2).flac")
    }

    @Test func collidesWithAnUnrelatedExistingFileNotBeingRenamed() {
        let unrelated = Self.makeFile(
            path: "/Library/Singles/Artist/Artist - Title.flac",
            title: nil, artist: nil, category: .singles) // not a candidate (missing tags)
        let toRename = Self.makeFile(
            path: "/Library/Singles/Artist/original.flac",
            title: "Title", artist: "Artist", category: .singles)

        let proposals = RenamePlanner.plan(for: [unrelated, toRename])
        #expect(proposals.count == 1)
        #expect(proposals.first?.proposedName == "Artist - Title (2).flac")
    }

    @Test func differentFoldersDoNotCollideWithEachOther() {
        let fileA = Self.makeFile(
            path: "/Library/Singles/Artist1/a.flac", title: "Title", artist: "Artist", category: .singles)
        let fileB = Self.makeFile(
            path: "/Library/Singles/Artist2/b.flac", title: "Title", artist: "Artist", category: .singles)

        let proposals = RenamePlanner.plan(for: [fileA, fileB])
        #expect(proposals.count == 2)
        #expect(proposals.allSatisfy { $0.proposedName == "Artist - Title.flac" })
    }

    // MARK: - Fixture

    private static func makeFile(
        path: String,
        title: String?,
        artist: String?,
        trackNumber: String? = nil,
        category: LibraryCategory
    ) -> AudioFile {
        let url = URL(fileURLWithPath: path)
        return AudioFile(
            url: url,
            fileName: url.lastPathComponent,
            fileExtension: url.pathExtension,
            sizeBytes: 1024,
            duration: 180,
            title: title,
            artist: artist,
            album: "Album",
            artworkThumbnail: nil,
            year: "2000",
            genre: "Electronic",
            trackNumber: trackNumber,
            category: category,
            expectedArtist: artist,
            isReadable: true
        )
    }
}
