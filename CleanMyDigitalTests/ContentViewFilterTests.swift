//
//  ContentViewFilterTests.swift
//  CleanMyDigitalTests
//

import Testing
import Foundation
import AppKit
import SwiftUI
@testable import CleanMyDigital

/// Verifies the pure logic behind the merged summary/filter row (see
/// `ContentView.summaryBar`) and the conditional Lookup/Cutoff columns —
/// pulled out of the view as static functions specifically so they're
/// testable without a live `LibraryScanner` or a rendered `Table`.
struct ContentViewFilterTests {
    // MARK: - fileMatches

    @Test func allMatchesEveryFileRegardlessOfIssues() {
        let complete = Self.makeCompleteFile()
        let broken = Self.makeFile(title: nil)
        #expect(ContentView.fileMatches(complete, filter: .all, lookupResults: [:]))
        #expect(ContentView.fileMatches(broken, filter: .all, lookupResults: [:]))
    }

    @Test func issuesMatchesOnlyFilesWithAtLeastOneIssue() {
        let complete = Self.makeCompleteFile()
        let broken = Self.makeFile(title: nil)
        #expect(!ContentView.fileMatches(complete, filter: .issues, lookupResults: [:]))
        #expect(ContentView.fileMatches(broken, filter: .issues, lookupResults: [:]))
    }

    @Test func noMetadataMatchesOnlyFilesMissingEveryApplicableField() {
        // Missing just the title (plus the always-nil-by-default artwork
        // in this fixture) is still short of "everything" for an Albums
        // file, which also checks artist/album/year/genre/track number.
        let missingSomeFields = Self.makeFile(title: nil)
        let missingEverything = Self.makeFile(
            title: nil, artist: nil, album: nil, year: nil, genre: nil, trackNumber: nil)
        #expect(!ContentView.fileMatches(missingSomeFields, filter: .noMetadata, lookupResults: [:]))
        #expect(ContentView.fileMatches(missingEverything, filter: .noMetadata, lookupResults: [:]))
    }

    @Test func completeMatchesOnlyFilesWithNoIssues() {
        let complete = Self.makeCompleteFile()
        let broken = Self.makeFile(title: nil)
        #expect(ContentView.fileMatches(complete, filter: .complete, lookupResults: [:]))
        #expect(!ContentView.fileMatches(broken, filter: .complete, lookupResults: [:]))
    }

    @Test func foundMatchesOnlyFilesWithAFoundLookupOutcomeRegardlessOfIssues() throws {
        // "Found" is orthogonal to issue severity — a file can still be
        // missing fields (that's *why* a lookup ran for it) and match here,
        // as long as the lookup actually found something.
        let broken = Self.makeFile(title: nil)
        let noMatchFile = Self.makeFile(title: nil, name: "no-match.mp3")
        let lookupResults: [URL: LookupOutcome] = [
            broken.url: try Self.makeFoundOutcome(),
            noMatchFile.url: .noMatch,
        ]
        #expect(ContentView.fileMatches(broken, filter: .found, lookupResults: lookupResults))
        #expect(!ContentView.fileMatches(noMatchFile, filter: .found, lookupResults: lookupResults))
    }

    // MARK: - filterStats

    @Test func filterStatsCountsEachBucketIndependently() throws {
        let complete = Self.makeCompleteFile(name: "complete.mp3")
        let withIssue = Self.makeFile(title: nil, name: "issue.mp3")
        let noMetadata = Self.makeFile(
            title: nil, artist: nil, album: nil, year: nil, genre: nil, trackNumber: nil,
            name: "empty.mp3")
        let files = [complete, withIssue, noMetadata]
        let lookupResults: [URL: LookupOutcome] = [withIssue.url: try Self.makeFoundOutcome()]

        let stats = ContentView.filterStats(files: files, lookupResults: lookupResults)
        let byFilter = Dictionary(uniqueKeysWithValues: stats.map { ($0.filter, $0) })

        #expect(byFilter[.all]?.count == 3)
        // withIssue and noMetadata both have issues.
        #expect(byFilter[.issues]?.count == 2)
        #expect(byFilter[.noMetadata]?.count == 1)
        #expect(byFilter[.complete]?.count == 1)
        #expect(byFilter[.found]?.count == 1)
    }

    @Test func filterStatsCarriesTheLabelAndSeverityColorForEveryFilterCase() {
        let stats = ContentView.filterStats(files: [], lookupResults: [:])
        #expect(stats.count == ContentView.Filter.allCases.count)

        let byFilter = Dictionary(uniqueKeysWithValues: stats.map { ($0.filter, $0) })
        #expect(byFilter[.all]?.label == "Total")
        #expect(byFilter[.all]?.color == .secondary)
        #expect(byFilter[.issues]?.label == "With issues")
        #expect(byFilter[.issues]?.color == .orange)
        #expect(byFilter[.noMetadata]?.label == "No metadata")
        #expect(byFilter[.noMetadata]?.color == .red)
        #expect(byFilter[.complete]?.label == "Complete")
        #expect(byFilter[.complete]?.color == .green)
        #expect(byFilter[.found]?.label == "Found")
        #expect(byFilter[.found]?.color == .blue)
    }

    @Test func filterStatsOnAnEmptyLibraryIsAllZeroesNotEmpty() {
        // The merged row should still render its five stats (all reading
        // zero) rather than vanish, same as the old separate summary bar
        // did before any scan populated `scanner.files`.
        let stats = ContentView.filterStats(files: [], lookupResults: [:])
        #expect(stats.allSatisfy { $0.count == 0 })
    }

    // MARK: - Column visibility

    @Test func lookupColumnIsHiddenUntilABatchLookupHasProducedAResult() {
        #expect(!ContentView.showsLookupColumn(lookupResults: [:]))
        #expect(ContentView.showsLookupColumn(lookupResults: [URL(fileURLWithPath: "/tmp/a.mp3"): .noMatch]))
    }

    @Test func cutoffColumnIsHiddenUntilASpectralAnalysisHasProducedAResult() {
        #expect(!ContentView.showsCutoffColumn(spectralResults: [:]))
        #expect(ContentView.showsCutoffColumn(
            spectralResults: [URL(fileURLWithPath: "/tmp/a.flac"): .inconclusive]))
    }

    // MARK: - Fixtures

    /// A file with every field filled in, including artwork — the one
    /// combination `hasIssues` reads false for. `AudioFile.hasArtwork` only
    /// checks `artworkThumbnail != nil`, so a 1x1 placeholder image is
    /// enough; nothing here reads its actual pixels.
    private static func makeCompleteFile(name: String = "complete.mp3") -> AudioFile {
        makeFile(
            title: "Title", artist: "Artist", album: "Album", year: "1999", genre: "Genre",
            trackNumber: "1", artworkThumbnail: NSImage(size: NSSize(width: 1, height: 1)),
            name: name)
    }

    private static func makeFile(
        title: String? = "Title", artist: String? = "Artist", album: String? = "Album",
        year: String? = "1999", genre: String? = "Genre", trackNumber: String? = "1",
        artworkThumbnail: NSImage? = nil, category: LibraryCategory = .albums,
        name: String = "track.mp3"
    ) -> AudioFile {
        let url = URL(fileURLWithPath: "/tmp/ContentViewFilterTests/\(name)")
        return AudioFile(
            url: url, fileName: url.lastPathComponent, fileExtension: url.pathExtension,
            sizeBytes: 1024, duration: 180, bitrateKbps: 320,
            title: title, artist: artist, album: album,
            artworkThumbnail: artworkThumbnail,
            year: year, genre: genre, trackNumber: trackNumber,
            category: category, expectedArtist: nil,
            isReadable: true)
    }

    /// A `.found` outcome via a minimally-decoded `DiscogsRelease` (only
    /// `id`/`title` are non-optional) — same technique
    /// `DiscogsReleaseFormatTests` uses, since `DiscogsRelease` has no
    /// direct memberwise initializer available outside its own file.
    private static func makeFoundOutcome() throws -> LookupOutcome {
        let json = Data(#"{"id": 1, "title": "Artist - Track"}"#.utf8)
        let release = try JSONDecoder().decode(DiscogsRelease.self, from: json)
        return .found(provider: .discogs, candidate: .discogs(release), fillableFields: [])
    }
}
