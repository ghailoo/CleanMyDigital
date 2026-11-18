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

    @Test func singlesAppendsMixFromFilenameWhenTitleLacksIt() {
        let file = Self.makeFile(
            path: "/Library/Singles/2 In A Room/She's Got Me Going Crazy (12\" Mix).flac",
            title: "She's Got Me Going Crazy", artist: "2 In A Room",
            category: .singles)

        let proposals = RenamePlanner.plan(for: [file])
        #expect(proposals.first?.proposedName == "2 In A Room - She's Got Me Going Crazy (12\" Mix).flac")
    }

    @Test func singlesDoesNotDuplicateMixAlreadyInTitle() {
        let file = Self.makeFile(
            path: "/Library/Singles/808 State/track (Remix Edit).flac",
            title: "Pacific 0101 (Remix Edit)", artist: "808 State",
            category: .singles)

        let proposals = RenamePlanner.plan(for: [file])
        #expect(proposals.first?.proposedName == "808 State - Pacific 0101 (Remix Edit).flac")
    }

    @Test func singlesWithDifferentMixesInSameFolderStayDistinct() {
        let clubMix = Self.makeFile(
            path: "/Library/Singles/2 In A Room/01 - Ahora Es (Club Mix).flac",
            title: "Ahora Es", artist: "2 In A Room",
            category: .singles)
        let radioEdit = Self.makeFile(
            path: "/Library/Singles/2 In A Room/02 - Ahora Es (Radio Edit).flac",
            title: "Ahora Es", artist: "2 In A Room",
            category: .singles)

        let proposals = RenamePlanner.plan(for: [clubMix, radioEdit])
            .sorted { $0.currentName < $1.currentName }
        #expect(proposals.count == 2)
        #expect(proposals[0].proposedName == "2 In A Room - Ahora Es (Club Mix).flac")
        #expect(proposals[1].proposedName == "2 In A Room - Ahora Es (Radio Edit).flac")
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
            bitrateKbps: nil,
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

    // MARK: - Packaging after the mix name

    /// Beatport rips end the Title tag with the BPM, which the file also
    /// carries in a proper BPM field. Verified on the user's own files:
    /// TITLE=Needed You (Original Mix) 125, BPM=125.
    @Test func dropsABPMGluedOnAfterTheMixName() {
        let file = Self.makeFile(
            path: "/M/Camelphat, Vomee - Needed You (Original Mix) 125.flac",
            title: "Needed You (Original Mix) 125",
            artist: "Camelphat, Vomee", category: .singles)

        #expect(RenamePlanner.plan(for: [file]).first?.proposedName
            == "Camelphat, Vomee - Needed You (Original Mix).flac")
    }

    @Test func keepsASecondVersionGroupAfterTheFirst() {
        #expect(MetadataQuery.trimmingAfterVersionGroup("My Love Is Your Love (Radio Edit) [Wyclef Remix]")
            == "My Love Is Your Love (Radio Edit) [Wyclef Remix]")
    }

    @Test func leavesATitleWithNoVersionGroupCompletelyAlone() {
        #expect(MetadataQuery.trimmingAfterVersionGroup("Close To You (US CDS Promo) (1990)")
            == "Close To You (US CDS Promo) (1990)")
        #expect(MetadataQuery.trimmingAfterVersionGroup("Thandaza (Feat. Alan Dixon)")
            == "Thandaza (Feat. Alan Dixon)")
    }

    @Test func keepsAFeaturedCreditSittingBeforeTheMixName() {
        #expect(MetadataQuery.trimmingAfterVersionGroup("Thandaza (Feat. Alan Dixon) (Original Mix) 123")
            == "Thandaza (Feat. Alan Dixon) (Original Mix)")
    }

    @Test func aWordMerelyContainingAVersionWordIsNotAVersionGroup() {
        // "Dubfire" is a producer, not a dub — so there is no version group
        // here and the year after it stays.
        #expect(MetadataQuery.trimmingAfterVersionGroup("Track (Dubfire) 1999")
            == "Track (Dubfire) 1999")
    }
}
