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
        let proposals = DuplicatePlanner.plan(for: groups, root: root)

        #expect(proposals.count == 1)
        #expect(proposals.first?.proposedRelativePath == "_CleanMyDigital Duplicates/Sub/extra.mp3")
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
