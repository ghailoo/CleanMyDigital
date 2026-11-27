//
//  CollectionPlannerTests.swift
//  CleanMyDigitalTests
//

import Testing
import Foundation
@testable import CleanMyDigital

struct CollectionPlannerTests {
    @Test func groupsMixesUnderSongTitleStrippedOfMixSuffix() throws {
        let clubMix = Self.makeFile(
            path: "/Library/Singles/2 In A Room/2 In A Room - Ahora Es (Club Mix).flac",
            artistRoot: "/Library/Singles/2 In A Room", title: "Ahora Es (Club Mix)")
        let radioEdit = Self.makeFile(
            path: "/Library/Singles/2 In A Room/2 In A Room - Ahora Es (Radio Edit).flac",
            artistRoot: "/Library/Singles/2 In A Room", title: "Ahora Es (Radio Edit)")

        let plan = try #require(CollectionPlanner.plan(for: [clubMix, radioEdit]).first)
        let proposals = plan.proposals.sorted { $0.file.fileName < $1.file.fileName }
        #expect(proposals.count == 2)
        #expect(proposals[0].proposedRelativePath == "Ahora Es/2 In A Room - Ahora Es (Club Mix).flac")
        #expect(proposals[1].proposedRelativePath == "Ahora Es/2 In A Room - Ahora Es (Radio Edit).flac")
    }

    @Test func titleWithoutMixSuffixUsesWholeTitle() throws {
        let file = Self.makeFile(
            path: "/Library/Singles/808 State/track.flac",
            artistRoot: "/Library/Singles/808 State", title: "Pacific 0101")

        let proposal = try #require(CollectionPlanner.plan(for: [file]).first?.proposals.first)
        #expect(proposal.proposedRelativePath == "Pacific 0101/track.flac")
    }

    /// No Title tag: the filename carries it, so the file is still collected
    /// rather than silently skipped.
    @Test func filesMissingTitleFallBackToTheFileName() throws {
        let file = Self.makeFile(
            path: "/Library/Singles/YBU/02 - YBU - Soul Magic (funk vocal version) (feat. Jonell).flac",
            artistRoot: "/Library/Singles/YBU", title: nil, artist: "YBU")

        let proposal = try #require(CollectionPlanner.plan(for: [file]).first?.proposals.first)
        #expect(proposal.songTitle == "Soul Magic")
        #expect(proposal.proposedRelativePath == "Soul Magic/02 - YBU - Soul Magic (funk vocal version) (feat. Jonell).flac")
    }

    @Test func albumsAndCompilationsAreSkipped() {
        let album = Self.makeFile(
            path: "/Library/Albums/Artist/Album/01 track.flac",
            artistRoot: "/Library/Albums/Artist", title: "Track (Remaster)", category: .albums)
        let compilation = Self.makeFile(
            path: "/Library/Compilations/Various/track.flac",
            artistRoot: "/Library/Compilations/Various", title: "Track (Remaster)", category: .compilations)

        #expect(CollectionPlanner.plan(for: [album, compilation]).isEmpty)
    }

    @Test func sanitizesPathHostileCharactersInSongTitle() throws {
        let file = Self.makeFile(
            path: "/Library/Singles/AC-DC/track.flac",
            artistRoot: "/Library/Singles/AC-DC", title: "Rock / Roll: Ain't Noise Pollution (12\" Mix)")

        let proposal = try #require(CollectionPlanner.plan(for: [file]).first?.proposals.first)
        #expect(proposal.proposedRelativePath == "Rock - Roll- Ain't Noise Pollution/track.flac")
    }

    // MARK: - Rule 2: pressing folder name

    @Test func pressingFolderNameUnwrapsABracketedDescriptor() throws {
        let file = Self.makeFile(
            path: "/Library/Singles/808 State/1990 - Close To You [12'' Promo Single]/track.flac",
            artistRoot: "/Library/Singles/808 State", title: "Close To You")

        let proposal = try #require(CollectionPlanner.plan(for: [file]).first?.proposals.first)
        #expect(proposal.pressingName == "1990 - 12'' Promo Single")
        #expect(proposal.proposedRelativePath == "Close To You/1990 - 12'' Promo Single/track.flac")
    }

    @Test func pressingFolderNameStripsArtistAndKeepsTheSecondBracketGroup() throws {
        let file = Self.makeFile(
            path: "/Library/Singles/Maxi Priest/Maxi Priest - Close To You (US CDS Promo) (1990) - PRCD2485/track.flac",
            artistRoot: "/Library/Singles/Maxi Priest", title: "Close To You", artist: "Maxi Priest")

        let proposal = try #require(CollectionPlanner.plan(for: [file]).first?.proposals.first)
        #expect(proposal.pressingName == "US CDS Promo (1990) - PRCD2485")
        #expect(proposal.proposedRelativePath == "Close To You/US CDS Promo (1990) - PRCD2485/track.flac")
    }

    @Test func pressingFolderNameEmptyAfterStrippingGoesStraightInSongFolder() throws {
        let file = Self.makeFile(
            path: "/Library/Singles/808 State/Close To You/track.flac",
            artistRoot: "/Library/Singles/808 State", title: "Close To You")

        // Top folder already *is* the song title — nothing pressing-specific
        // left, and the file isn't nested any deeper, so it stays put.
        #expect(CollectionPlanner.plan(for: [file]).isEmpty)
    }

    /// Field case: loose tracks of different songs directly in the artist
    /// folder must each get their own song folder, not all the first one's.
    @Test func looseTracksOfDifferentSongsGetTheirOwnSongFolders() {
        let love = Self.makeFile(
            path: "/Library/Singles/Adeva/Adeva - Beautiful Love (Remix) (1990).flac",
            artistRoot: "/Library/Singles/Adeva", title: "Beautiful Love (Remix)", artist: "Adeva")
        let around = Self.makeFile(
            path: "/Library/Singles/Adeva/Adeva - Been Around (Triple S Mix).flac",
            artistRoot: "/Library/Singles/Adeva", title: "Been Around (Triple S Mix)", artist: "Adeva")

        let paths = CollectionPlanner.plan(for: [love, around]).flatMap(\.proposals).map(\.proposedRelativePath).sorted()
        #expect(paths == ["Beautiful Love/Adeva - Beautiful Love (Remix) (1990).flac",
                          "Been Around/Adeva - Been Around (Triple S Mix).flac"])
    }

    // MARK: - One folder per song, albums skipped

    /// The KLF case: the same song spelled differently across pressings must
    /// land in one folder, not two.
    @Test func titleSpellingVariantsShareOneSongFolder() {
        let amp = Self.makeFile(
            path: "/Library/Singles/The KLF/1991 - Justified & Ancient (CDM) (Germany)/01 Justified & Ancient.flac",
            artistRoot: "/Library/Singles/The KLF", title: "Justified & Ancient", artist: "The KLF")
        let and = Self.makeFile(
            path: "/Library/Singles/The KLF/The KLF - Justified And Ancient (US CDM) (1992)/01 Justified And Ancient.flac",
            artistRoot: "/Library/Singles/The KLF", title: "Justified And Ancient", artist: "The KLF")
        let question = Self.makeFile(
            path: "/Library/Singles/The KLF/1989 - What Time Is Love/01 What Time Is Love?.flac",
            artistRoot: "/Library/Singles/The KLF", title: "What Time Is Love?", artist: "The KLF")
        let plain = Self.makeFile(
            path: "/Library/Singles/The KLF/1990 - What Time Is Love (Power Remix) (CDM)/01 What Time Is Love.flac",
            artistRoot: "/Library/Singles/The KLF", title: "What Time Is Love (Power Remix)", artist: "The KLF")

        let songFolders = Set(CollectionPlanner.plan(for: [amp, and, question, plain])
            .flatMap(\.proposals).map { $0.proposedRelativePath.components(separatedBy: "/")[0] })
        #expect(songFolders.count == 2)
    }

    /// An album folder (more than four different songs) is left untouched.
    @Test func albumFoldersAreSkipped() {
        let files = ["What Time Is Love? (LP Mix)", "Make It Rain", "3 A.M. Eternal (Live At The S.S.L.)",
                     "Church Of The KLF", "Build A Fire", "The White Room"].enumerated().map { index, title in
            Self.makeFile(
                path: "/Library/Singles/The KLF/The KLF 1991 - The White Room v2/0\(index + 1) \(title).flac",
                artistRoot: "/Library/Singles/The KLF", title: title, artist: "The KLF")
        }

        #expect(CollectionPlanner.plan(for: files).isEmpty)
    }

    /// Four or fewer distinct songs is still a single's release (A-side plus
    /// B-sides), so it's collected as before.
    @Test func aReleaseWithAFewBSidesIsStillCollected() {
        let files = ["Last Train To Trancentral", "Last Train To Trancentral (Dub)", "Techno Trance"]
            .map { title in
                Self.makeFile(
                    path: "/Library/Singles/The KLF/1991 - Last Train To Trancentral (CDM)/\(title).flac",
                    artistRoot: "/Library/Singles/The KLF", title: title, artist: "The KLF")
            }

        #expect(CollectionPlanner.plan(for: files).flatMap(\.proposals).count == 3)
    }

    // MARK: - Rule 8: idempotency

    @Test func alreadyOrganizedWithPressingProposesNothing() {
        let file = Self.makeFile(
            path: "/Library/Singles/Maxi Priest/Close To You/US CDS Promo (1990) - PRCD2485/Maxi Priest - Close To You.mp3",
            artistRoot: "/Library/Singles/Maxi Priest", title: "Close To You", artist: "Maxi Priest")

        #expect(CollectionPlanner.plan(for: [file]).isEmpty)
    }

    /// The nesting bug from the field: a song folder holding a same-named
    /// subfolder. Tracks must flatten into Song/Pressing under the real
    /// artist folder, never into a new Song/Pressing inside the inner one.
    @Test func sameNamedSubfolderFlattensInsteadOfNestingAgain() throws {
        let file = Self.makeFile(
            path: "/Library/Singles/Maxi Priest/Close To You/US 12'' (1990) - 0-96463/Close To You/Maxi Priest - Close To You.flac",
            artistRoot: "/Library/Singles/Maxi Priest", title: "Close To You", artist: "Maxi Priest")

        let plan = try #require(CollectionPlanner.plan(for: [file]).first)
        #expect(plan.artistRoot.path == "/Library/Singles/Maxi Priest")
        #expect(plan.proposals.first?.proposedRelativePath
                == "Close To You/US 12'' (1990) - 0-96463/Maxi Priest - Close To You.flac")
        #expect(plan.sourceFoldersToClean.map(\.path)
                == ["/Library/Singles/Maxi Priest/Close To You/US 12'' (1990) - 0-96463/Close To You"])
    }

    @Test func alreadyOrganizedLooseInSongFolderProposesNothing() {
        let file = Self.makeFile(
            path: "/Library/Singles/808 State/Pacific 0101/track.flac",
            artistRoot: "/Library/Singles/808 State", title: "Pacific 0101")

        #expect(CollectionPlanner.plan(for: [file]).isEmpty)
    }

    @Test func reRunningPlannerOnItsOwnOutputProposesNothing() throws {
        let artistRoot = "/Library/Singles/Maxi Priest"
        let original = Self.makeFile(
            path: "\(artistRoot)/1990 - Close To You [12'' Promo Single]/Maxi Priest - Close To You.mp3",
            artistRoot: artistRoot, title: "Close To You", artist: "Maxi Priest")

        let firstProposal = try #require(CollectionPlanner.plan(for: [original]).first?.proposals.first)
        #expect(firstProposal.proposedRelativePath == "Close To You/1990 - 12'' Promo Single/Maxi Priest - Close To You.mp3")

        let organized = Self.makeFile(
            path: "\(artistRoot)/\(firstProposal.proposedRelativePath)",
            artistRoot: artistRoot, title: "Close To You", artist: "Maxi Priest")
        #expect(CollectionPlanner.plan(for: [organized]).isEmpty)
    }

    // MARK: - Rule 6: name clashes

    @Test func nameClashAppendsTheOtherPressingNameRatherThanOverwriting() throws {
        // Both pressings reduce to "nothing left" (rule 2), so both land
        // directly in the song folder under their original filename —
        // the second one has to be disambiguated rather than overwrite the
        // first.
        let fileA = Self.makeFile(
            path: "/Library/Singles/TestArtist/Common Song -/track.mp3",
            artistRoot: "/Library/Singles/TestArtist", title: "Common Song", artist: "TestArtist")
        let fileB = Self.makeFile(
            path: "/Library/Singles/TestArtist/TestArtist - Common Song/track.mp3",
            artistRoot: "/Library/Singles/TestArtist", title: "Common Song", artist: "TestArtist")

        let proposals = try #require(CollectionPlanner.plan(for: [fileA, fileB]).first).proposals
        #expect(proposals.count == 2)

        let first = try #require(proposals.first { $0.file.url == fileA.url })
        #expect(first.proposedRelativePath == "Common Song/track.mp3")

        let second = try #require(proposals.first { $0.file.url == fileB.url })
        #expect(second.proposedFileName == "track (TestArtist - Common Song).mp3")
        #expect(second.proposedRelativePath == "Common Song/track (TestArtist - Common Song).mp3")
    }

    // MARK: - Fixture

    private static func makeFile(
        path: String,
        artistRoot: String,
        title: String?,
        category: LibraryCategory = .singles,
        artist: String? = nil,
        genre: String? = "Electronic"
    ) -> AudioFile {
        let url = URL(fileURLWithPath: path)
        let rootComponents = URL(fileURLWithPath: artistRoot).standardizedFileURL.pathComponents
        let fileComponents = url.standardizedFileURL.pathComponents
        let relativeComponents = Array(fileComponents.dropFirst(rootComponents.count))
        // A loose file sits directly in the artist root (one component left:
        // its own filename) — anything nested has a folder name to report.
        let expectedArtist = relativeComponents.count > 1 ? relativeComponents.first : nil

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
            genre: genre,
            trackNumber: nil,
            category: category,
            expectedArtist: expectedArtist,
            isReadable: true
        )
    }

    // MARK: - Collecting by genre

    @Test func genreFolderUsesTheLastValueOfAMultiValuedTag() {
        let file = Self.makeFile(
            path: "/Music/Singles/Artist/track.flac", artistRoot: "/Music/Singles",
            title: "Track", artist: "Artist",
            genre: "Electronic, Trance, House, Progressive House")

        #expect(CollectionPlanner.genreFolderName(for: file) == "Progressive House")
    }

    @Test func genreFolderSanitizesTheSlashInValuesLikeFunkSoul() {
        let file = Self.makeFile(
            path: "/Music/Singles/Artist/track.flac", artistRoot: "/Music/Singles",
            title: "Track", artist: "Artist", genre: "Electronic, Funk / Soul")

        // "/" can't appear in a folder name at all.
        let name = try? #require(CollectionPlanner.genreFolderName(for: file))
        #expect(name?.contains("/") == false)
    }

    @Test func genreFolderIsNilWithoutAGenreTag() {
        for genre in [nil, "", "  ", ","] {
            let file = Self.makeFile(
                path: "/Music/Singles/Artist/track.flac", artistRoot: "/Music/Singles",
                title: "Track", artist: "Artist", genre: genre)
            #expect(CollectionPlanner.genreFolderName(for: file) == nil)
        }
    }

    @Test func genreGroupingMovesTracksIntoOneFlatFolderPerGenre() {
        let root = "/Music/Singles"
        let files = [
            Self.makeFile(path: "\(root)/Lane 8/Needed You.flac", artistRoot: root,
                          title: "Needed You", artist: "Lane 8",
                          genre: "Electronic, Deep House"),
            Self.makeFile(path: "\(root)/Bassomatic/Fascinating Rhythm.flac", artistRoot: root,
                          title: "Fascinating Rhythm", artist: "Bassomatic",
                          genre: "Electronic, Downtempo"),
        ]

        let plans = CollectionPlanner.plan(for: files, grouping: .genre)
        #expect(plans.map(\.artistFolderName) == ["Deep House", "Downtempo"])
        // Flat: the destination is just the filename under the genre folder.
        #expect(plans.flatMap(\.proposals).map(\.proposedRelativePath).sorted()
                == ["Fascinating Rhythm.flac", "Needed You.flac"])
        // Nothing is swept up or deleted in this scheme.
        #expect(plans.allSatisfy { $0.sourceFoldersToClean.isEmpty })
    }

    /// The real-library case: three pressings of one track whose tags
    /// disagree about the genre. Deciding per file would scatter them.
    @Test func pressingsOfOneSongShareAGenreFolderEvenWhenTheirTagsDisagree() {
        let root = "/Music/Singles"
        let files = [
            Self.makeFile(path: "\(root)/Bassomatic/a/Fascinating Rhythm (Loud Edit).flac",
                          artistRoot: root, title: "Fascinating Rhythm (Loud Edit)",
                          artist: "Bassomatic", genre: "House"),
            Self.makeFile(path: "\(root)/Bassomatic/b/Fascinating Rhythm (Hook Mix).flac",
                          artistRoot: root, title: "Fascinating Rhythm (Hook Mix)",
                          artist: "Bassomatic", genre: "House"),
            Self.makeFile(path: "\(root)/Bassomatic/c/Fascinating Rhythm (Caniggia Mix).flac",
                          artistRoot: root, title: "Fascinating Rhythm (Caniggia Mix)",
                          artist: "Bassomatic", genre: "Electronic, Funk / Soul, Downtempo"),
        ]

        let plans = CollectionPlanner.plan(for: files, grouping: .genre)
        #expect(plans.count == 1)
        #expect(plans.first?.artistFolderName == "House")
        #expect(plans.first?.proposals.count == 3)
    }

    @Test func genreGroupingLeavesFilesWithNoGenreWhereTheyAre() {
        let root = "/Music/Singles"
        let files = [
            Self.makeFile(path: "\(root)/Artist/tagged.flac", artistRoot: root,
                          title: "Tagged", artist: "Artist", genre: "House"),
            Self.makeFile(path: "\(root)/Artist/untagged.flac", artistRoot: root,
                          title: "Untagged", artist: "Artist", genre: nil),
        ]

        let plans = CollectionPlanner.plan(for: files, grouping: .genre)
        #expect(plans.flatMap(\.proposals).map(\.file.fileName) == ["tagged.flac"])
        #expect(CollectionPlanner.filesWithoutAGenre(in: files).map(\.fileName) == ["untagged.flac"])
    }

    @Test func genreGroupingProposesNothingOnASecondRun() {
        let root = "/Music/Singles"
        let files = [
            Self.makeFile(path: "\(root)/House/Needed You.flac", artistRoot: root,
                          title: "Needed You", artist: "Lane 8", genre: "House"),
        ]

        #expect(CollectionPlanner.plan(for: files, grouping: .genre).isEmpty)
    }

    @Test func genreGroupingDisambiguatesTwoArtistsSameFileName() {
        let root = "/Music/Singles"
        let files = [
            Self.makeFile(path: "\(root)/Lane 8/track.flac", artistRoot: root,
                          title: "One", artist: "Lane 8", genre: "House"),
            Self.makeFile(path: "\(root)/Yotto/track.flac", artistRoot: root,
                          title: "Two", artist: "Yotto", genre: "House"),
        ]

        let names = CollectionPlanner.plan(for: files, grouping: .genre)
            .flatMap(\.proposals).map(\.proposedFileName).sorted()
        #expect(names.count == 2)
        #expect(Set(names).count == 2, "a flat genre folder must not overwrite a same-named file")
    }

    /// The artist scheme is the default, so every existing caller and the
    /// 1.8.1 library-root guard keep working untouched.
    @Test func groupingDefaultsToArtist() {
        let root = "/Music/Depeche Mode"
        let files = [
            Self.makeFile(path: "\(root)/Enjoy The Silence/a.flac", artistRoot: root,
                          title: "Enjoy The Silence", artist: "Depeche Mode"),
        ]

        #expect(CollectionPlanner.plan(for: files).map(\.proposedPathsForTest)
                == CollectionPlanner.plan(for: files, grouping: .artist).map(\.proposedPathsForTest))
    }

    // MARK: - A library root is not an artist folder

    /// The regression this file exists for now: scanning a folder that
    /// holds many ARTIST folders (rather than one artist's own folder) made
    /// the planner read each artist folder as one single's pressings. It
    /// moved the files to `Root/Song/Pressing/` and removed the artist
    /// folder once empty, flattening `Artist/Song/file` into
    /// `Root/Song/file` and losing the artist level for good.
    @Test func proposesNothingInsideAnArtistsOwnFolder() {
        let root = "/Music/Singles"
        let files = [
            Self.makeFile(path: "\(root)/Real McCoy/Another Night.mp3",
                          artistRoot: root, title: "Another Night", artist: "Real McCoy"),
            Self.makeFile(path: "\(root)/Real McCoy/Run Away.mp3",
                          artistRoot: root, title: "Run Away", artist: "Real McCoy"),
        ]

        #expect(CollectionPlanner.plan(for: files).isEmpty)
        #expect(CollectionPlanner.artistFoldersMistakenForReleases(in: files) == ["Real McCoy"])
    }

    /// The guard must not fire on the commonest release-folder naming there
    /// is, or it would switch the whole feature off.
    @Test func aReleaseFolderNamedAfterTheArtistIsStillCollected() {
        let root = "/Music/Depeche Mode"
        let files = [
            Self.makeFile(path: "\(root)/Depeche Mode - Enjoy The Silence (UK 12'')/01 Enjoy The Silence.mp3",
                          artistRoot: root, title: "Enjoy The Silence (Hands And Feet Mix)", artist: "Depeche Mode"),
        ]

        #expect(CollectionPlanner.artistFoldersMistakenForReleases(in: files).isEmpty)
        #expect(!CollectionPlanner.plan(for: files).isEmpty)
    }

    @Test func aMisspelledArtistTagStillIdentifiesTheArtistFolder() {
        #expect(CollectionPlanner.folderIsArtistsOwn("Kings Of Tomorrow", files: [
            Self.makeFile(path: "/M/Kings Of Tomorrow/A.mp3", artistRoot: "/M",
                          title: "A", artist: "Kings Of Tommorow"),
        ]))
    }

    @Test func oneMistaggedFileCannotVetoARealReleaseFolder() {
        let root = "/Music/Moloko"
        let files = [
            Self.makeFile(path: "\(root)/Sing It Back/01 Sing It Back.mp3",
                          artistRoot: root, title: "Sing It Back", artist: "Moloko"),
            Self.makeFile(path: "\(root)/Sing It Back/02 Sing It Back (Boris Mix).mp3",
                          artistRoot: root, title: "Sing It Back (Boris Musical Mix)", artist: "Sing It Back"),
        ]

        #expect(!CollectionPlanner.folderIsArtistsOwn("Sing It Back", files: files))
    }

    @Test func anArtistFolderWithNoArtistTagsAtAllIsLeftAlone() {
        #expect(!CollectionPlanner.folderIsArtistsOwn("Real McCoy", files: [
            Self.makeFile(path: "/M/Real McCoy/Another Night.mp3", artistRoot: "/M",
                          title: "Another Night", artist: nil),
        ]))
    }
}

private extension ArtistCollectionPlan {
    var proposedPathsForTest: [String] { proposals.map(\.proposedRelativePath).sorted() }
}
