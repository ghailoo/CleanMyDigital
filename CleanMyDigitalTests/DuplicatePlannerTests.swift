//
//  DuplicatePlannerTests.swift
//  CleanMyDigitalTests
//

import Testing
import Foundation
@testable import CleanMyDigital

struct DuplicatePlannerTests {
    @Test func groupsFilesWithSameArtistAndTitle() {
        let a = Self.makeFile(path: "/Library/Singles/Artist/a.flac", artist: "Artist", title: "Title")
        let b = Self.makeFile(path: "/Library/Singles/Artist/b.mp3", artist: "Artist", title: "Title")
        let unrelated = Self.makeFile(path: "/Library/Singles/Artist/c.mp3", artist: "Artist", title: "Other Title")

        let groups = DuplicatePlanner.groups(for: [a, b, unrelated], cutoffHz: [:])
        #expect(groups.count == 1)
        #expect(groups.first?.files.count == 2)
    }

    @Test func matchIsCaseAndWhitespaceInsensitive() {
        let a = Self.makeFile(path: "/Library/Singles/Artist/a.flac", artist: "  Artist ", title: "Title")
        let b = Self.makeFile(path: "/Library/Singles/Artist/b.mp3", artist: "artist", title: "  title  ")

        let groups = DuplicatePlanner.groups(for: [a, b], cutoffHz: [:])
        #expect(groups.count == 1)
    }

    @Test func filesMissingArtistOrTitleAreSkipped() {
        let noArtist = Self.makeFile(path: "/Library/Singles/Artist/a.flac", artist: nil, title: "Title")
        let noTitle = Self.makeFile(path: "/Library/Singles/Artist/b.flac", artist: "Artist", title: nil)

        #expect(DuplicatePlanner.groups(for: [noArtist, noTitle], cutoffHz: [:]).isEmpty)
    }

    @Test func singleFilesAreNotDuplicates() {
        let a = Self.makeFile(path: "/Library/Singles/Artist/a.flac", artist: "Artist", title: "Title")
        #expect(DuplicatePlanner.groups(for: [a], cutoffHz: [:]).isEmpty)
    }

    @Test func rankingPrefersHigherBitrateWhenNoCutoffMeasured() {
        let low = Self.makeFile(path: "/Library/Singles/Artist/low.mp3", artist: "Artist", title: "Title", bitrateKbps: 128)
        let high = Self.makeFile(path: "/Library/Singles/Artist/high.flac", artist: "Artist", title: "Title", bitrateKbps: 900)

        let group = try! #require(DuplicatePlanner.groups(for: [low, high], cutoffHz: [:]).first)
        #expect(group.keeper.url == high.url)
        #expect(group.extras.map(\.url) == [low.url])
    }

    @Test func rankingPrefersHigherCutoffOverHigherBitrateWhenBothMeasured() {
        // A "fake" 320kbps file with a low cutoff should lose to a lower
        // nominal bitrate file that's actually full-range.
        let fake = Self.makeFile(path: "/Library/Singles/Artist/fake.mp3", artist: "Artist", title: "Title", bitrateKbps: 320)
        let real = Self.makeFile(path: "/Library/Singles/Artist/real.mp3", artist: "Artist", title: "Title", bitrateKbps: 192)

        let cutoffHz: [URL: Double] = [fake.url: 16000, real.url: 20000]
        let group = try! #require(DuplicatePlanner.groups(for: [fake, real], cutoffHz: cutoffHz).first)
        #expect(group.keeper.url == real.url)
    }

    @Test func genuineMP3BeatsFakeFLACWhenGraded() {
        // A transcoded FLAC has the higher bitrate and here even the
        // higher measured cutoff; the verdict still wins.
        let fake = Self.makeFile(path: "/Library/Singles/Artist/fake.flac", artist: "Artist", title: "Title", bitrateKbps: 900)
        let mp3 = Self.makeFile(path: "/Library/Singles/Artist/real.mp3", artist: "Artist", title: "Title", bitrateKbps: 320)

        let group = try! #require(DuplicatePlanner.groups(
            for: [fake, mp3], cutoffHz: [fake.url: 19_800, mp3.url: 19_600],
            grades: [fake.url: .fake, mp3.url: .medium]).first)
        #expect(group.keeper.url == mp3.url)
    }

    @Test func quarantinePlanMirrorsPathAndSkipsAlreadyQuarantined() {
        let root = URL(fileURLWithPath: "/Library/Singles")
        let fake = Self.makeFile(path: "/Library/Singles/Artist/fake.flac", artist: "Artist", title: "Title")
        let parked = Self.makeFile(path: "/Library/Singles/_CleanMyDigital Quarantine/Artist/old.flac", artist: "Artist", title: "Old")

        let plan = DuplicatePlanner.quarantinePlan(for: [fake, parked], roots: [root])
        #expect(plan.map(\.file.url) == [fake.url])
        #expect(plan.first?.proposedRelativePath == "_CleanMyDigital Quarantine/Artist/fake.flac")
    }

    @Test func unmeasuredFileIsNotPenalizedAgainstAFlaggedMeasuredFile() {
        // `measured` has a known-bad low cutoff; `unmeasured` hasn't been
        // analyzed at all but has a much higher bitrate. Falling back to
        // bitrate (since cutoff isn't known for both) should favor the
        // unmeasured file, not treat missing data as worse than a known flag.
        let measured = Self.makeFile(path: "/Library/Singles/Artist/measured.mp3", artist: "Artist", title: "Title", bitrateKbps: 128)
        let unmeasured = Self.makeFile(path: "/Library/Singles/Artist/unmeasured.flac", artist: "Artist", title: "Title", bitrateKbps: 900)

        let cutoffHz: [URL: Double] = [measured.url: 14000]
        let group = try! #require(DuplicatePlanner.groups(for: [measured, unmeasured], cutoffHz: cutoffHz).first)
        #expect(group.keeper.url == unmeasured.url)
    }

    @Test func filesAlreadyInsideReviewFolderAreExcluded() {
        let keeper = Self.makeFile(path: "/Library/Singles/Artist/keeper.flac", artist: "Artist", title: "Title", bitrateKbps: 900)
        let alreadyMoved = Self.makeFile(
            path: "/Library/Singles/Artist/_CleanMyDigital Duplicates/extra.mp3",
            artist: "Artist", title: "Title", bitrateKbps: 128)

        #expect(DuplicatePlanner.groups(for: [keeper, alreadyMoved], cutoffHz: [:]).isEmpty)
    }

    @Test func planMirrorsRelativePathUnderReviewFolder() {
        let root = URL(fileURLWithPath: "/Library/Singles/Artist")
        let keeper = Self.makeFile(path: "/Library/Singles/Artist/keeper.flac", artist: "Artist", title: "Title", bitrateKbps: 900)
        let extra = Self.makeFile(path: "/Library/Singles/Artist/Sub/extra.mp3", artist: "Artist", title: "Title", bitrateKbps: 128)

        let groups = DuplicatePlanner.groups(for: [keeper, extra], cutoffHz: [:])
        let proposals = DuplicatePlanner.plan(for: groups, roots: [root])

        #expect(proposals.count == 1)
        #expect(proposals.first?.proposedRelativePath == "_CleanMyDigital Duplicates/Sub/extra.mp3")
    }

    /// A Singles scan can cover several artist folders at once, and a
    /// duplicate group spanning two of them is exactly the case that
    /// motivates it — the same track filed under two artists. Each loser's
    /// path has to be measured against the root it actually came from, so
    /// it moves into a review folder inside its own artist folder rather
    /// than being dragged under whichever folder was selected first.
    @Test func planMeasuresEachFileAgainstItsOwnRootAcrossSeveralFolders() {
        let rootA = URL(fileURLWithPath: "/Library/Singles/Artist A")
        let rootB = URL(fileURLWithPath: "/Library/Singles/Artist B")
        let keeper = Self.makeFile(
            path: "/Library/Singles/Artist A/best.flac", artist: "Artist", title: "Title", bitrateKbps: 900)
        let extra = Self.makeFile(
            path: "/Library/Singles/Artist B/Sub/worse.mp3", artist: "Artist", title: "Title", bitrateKbps: 128)

        let groups = DuplicatePlanner.groups(for: [keeper, extra], cutoffHz: [:])
        let proposals = DuplicatePlanner.plan(for: groups, roots: [rootA, rootB])

        #expect(proposals.count == 1)
        // Relative to Artist B, the root the loser lives under — not to
        // Artist A, which comes first in `roots`.
        #expect(proposals.first?.proposedRelativePath == "_CleanMyDigital Duplicates/Sub/worse.mp3")
    }

    /// Nested selections resolve to the nearest enclosing root, matching
    /// `LibraryScanner.root(containing:)` — otherwise a file could be
    /// planned against an outer root while the move resolved it against
    /// the inner one, sending it somewhere the preview never showed.
    @Test func planPrefersTheDeepestRootWhenSelectionsAreNested() {
        let outer = URL(fileURLWithPath: "/Library/Singles")
        let inner = URL(fileURLWithPath: "/Library/Singles/Artist")
        let keeper = Self.makeFile(
            path: "/Library/Singles/Artist/keeper.flac", artist: "Artist", title: "Title", bitrateKbps: 900)
        let extra = Self.makeFile(
            path: "/Library/Singles/Artist/extra.mp3", artist: "Artist", title: "Title", bitrateKbps: 128)

        let groups = DuplicatePlanner.groups(for: [keeper, extra], cutoffHz: [:])
        let proposals = DuplicatePlanner.plan(for: groups, roots: [outer, inner])

        #expect(proposals.first?.proposedRelativePath == "_CleanMyDigital Duplicates/extra.mp3")
    }

    /// A file outside every scanned root can't be given a meaningful
    /// relative path, so it's dropped rather than guessed at.
    @Test func planSkipsFilesOutsideEveryRoot() {
        let root = URL(fileURLWithPath: "/Library/Singles/Artist A")
        let keeper = Self.makeFile(
            path: "/Elsewhere/keeper.flac", artist: "Artist", title: "Title", bitrateKbps: 900)
        let extra = Self.makeFile(
            path: "/Elsewhere/extra.mp3", artist: "Artist", title: "Title", bitrateKbps: 128)

        let groups = DuplicatePlanner.groups(for: [keeper, extra], cutoffHz: [:])

        #expect(DuplicatePlanner.plan(for: groups, roots: [root]).isEmpty)
    }

    // MARK: - Fixture

    private static func makeFile(
        path: String,
        artist: String?,
        title: String?,
        bitrateKbps: Int? = nil
    ) -> AudioFile {
        let url = URL(fileURLWithPath: path)
        return AudioFile(
            url: url,
            fileName: url.lastPathComponent,
            fileExtension: url.pathExtension,
            sizeBytes: 1024,
            duration: 180,
            bitrateKbps: bitrateKbps,
            title: title,
            artist: artist,
            album: "Album",
            artworkThumbnail: nil,
            year: "2000",
            genre: "Electronic",
            trackNumber: nil,
            category: .singles,
            expectedArtist: artist,
            isReadable: true
        )
    }
}
