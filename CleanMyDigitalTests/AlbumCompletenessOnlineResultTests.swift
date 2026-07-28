//
//  AlbumCompletenessOnlineResultTests.swift
//  CleanMyDigitalTests
//

import Testing
import Foundation
@testable import CleanMyDigital

/// Verifies the two pieces behind "an online (Discogs) completeness
/// confirmation persists for the session": the pure track-diff helper
/// `[DiscogsTrack].missingTitles(matchedTrackIDs:)`, and
/// `LibraryScanner`'s storage/reset of `albumCompletenessResults` —
/// mirroring the existing `lookupResults`/`spectralResults` pattern.
struct AlbumCompletenessOnlineResultTests {

    // MARK: - [DiscogsTrack].missingTitles(matchedTrackIDs:)

    @Test func missingTitlesIsEmptyWhenEveryTrackIsMatched() {
        let tracks = [
            DiscogsTrack(position: "1", title: "Intro", duration: nil),
            DiscogsTrack(position: "2", title: "Changes", duration: "4:20"),
        ]
        let matchedIDs = Set(tracks.map(\.id))
        #expect(tracks.missingTitles(matchedTrackIDs: matchedIDs).isEmpty)
    }

    @Test func missingTitlesListsTracksNotInTheMatchedSet() {
        let intro = DiscogsTrack(position: "1", title: "Intro", duration: nil)
        let changes = DiscogsTrack(position: "2", title: "Changes", duration: "4:20")
        let outro = DiscogsTrack(position: "3", title: "Outro", duration: nil)
        let tracks = [intro, changes, outro]

        let missing = tracks.missingTitles(matchedTrackIDs: [changes.id])

        #expect(missing == ["Intro", "Outro"])
    }

    @Test func missingTitlesReturnsEveryTitleWhenNothingIsMatched() {
        let tracks = [
            DiscogsTrack(position: "1", title: "Intro", duration: nil),
            DiscogsTrack(position: "2", title: "Changes", duration: "4:20"),
        ]
        #expect(tracks.missingTitles(matchedTrackIDs: []) == ["Intro", "Changes"])
    }

    // MARK: - LibraryScanner.albumCompletenessResults

    @Test func recordAlbumCompletenessResultStoresItKeyedByFolderURL() async throws {
        let folder = try Self.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data().write(to: folder.appendingPathComponent("track.mp3"))

        let scanner = LibraryScanner()
        await scanner.scan(folder: folder, category: .albums)

        let albumFolder = folder
        scanner.recordAlbumCompletenessResult(.confirmedComplete, for: albumFolder)
        #expect(scanner.albumCompletenessResults[albumFolder] == .confirmedComplete)

        scanner.recordAlbumCompletenessResult(.missingTracks(["Intro"]), for: albumFolder)
        #expect(scanner.albumCompletenessResults[albumFolder] == .missingTracks(["Intro"]))
    }

    @Test func albumCompletenessResultsAreClearedByANewScan() async throws {
        let folder = try Self.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data().write(to: folder.appendingPathComponent("track.mp3"))

        let scanner = LibraryScanner()
        await scanner.scan(folder: folder, category: .albums)
        scanner.recordAlbumCompletenessResult(.confirmedComplete, for: folder)
        #expect(!scanner.albumCompletenessResults.isEmpty)

        await scanner.scan(folder: folder, category: .albums)
        #expect(scanner.albumCompletenessResults.isEmpty)
    }

    private static func makeTempFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}
