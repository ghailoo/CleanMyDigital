//
//  DroppedFoldersTests.swift
//  CleanMyDigitalTests
//

import Foundation
import Testing
@testable import CleanMyDigital

@Suite struct DroppedFoldersTests {
    /// Stands in for the filesystem: anything without an extension is a folder.
    private func resolve(_ paths: [String], category: LibraryCategory) -> DroppedFolders.Resolution {
        DroppedFolders.resolve(
            paths.map { URL(fileURLWithPath: $0) },
            category: category,
            isDirectory: { $0.pathExtension.isEmpty }
        )
    }

    @Test func aDroppedFolderIsTheRoot() {
        let result = resolve(["/Music/Singles/Daft Punk"], category: .singles)
        #expect(result.roots.map(\.lastPathComponent) == ["Daft Punk"])
        #expect(result.rejectedCount == 0)
    }

    @Test func droppedTracksScanTheFolderTheyreIn() {
        let result = resolve([
            "/Music/Singles/Daft Punk/one.flac",
            "/Music/Singles/Daft Punk/two.mp3",
        ], category: .singles)
        #expect(result.roots.map(\.lastPathComponent) == ["Daft Punk"])
    }

    @Test func nonAudioFilesAreRejectedNotScanned() {
        let result = resolve([
            "/Music/Singles/Daft Punk",
            "/Users/me/invoice.pdf",
        ], category: .singles)
        #expect(result.roots.count == 1)
        #expect(result.rejectedCount == 1)
    }

    @Test func singlesTakeEveryDroppedFolder() {
        let result = resolve([
            "/Music/Singles/Daft Punk",
            "/Music/Singles/Chemical Brothers",
        ], category: .singles)
        #expect(result.roots.count == 2)
        #expect(result.ignoredFolders.isEmpty)
        #expect(result.summary(category: .singles) == nil)
    }

    @Test func albumsKeepOnlyTheFirstFolderAndSaySo() {
        let result = resolve([
            "/Music/Albums/Discovery",
            "/Music/Albums/Homework",
        ], category: .albums)
        #expect(result.roots.map(\.lastPathComponent) == ["Discovery"])
        #expect(result.ignoredFolders.map(\.lastPathComponent) == ["Homework"])

        let summary = result.summary(category: .albums)
        #expect(summary?.contains("Discovery") == true)
        #expect(summary?.contains("1 other folder") == true)
    }

    @Test func theSameFolderTwiceIsScannedOnce() {
        let result = resolve([
            "/Music/Singles/Daft Punk",
            "/Music/Singles/Daft Punk/one.flac",
        ], category: .singles)
        #expect(result.roots.count == 1)
    }

    @Test func nothingScannableIsEmpty() {
        let result = resolve(["/Users/me/invoice.pdf"], category: .albums)
        #expect(result.isEmpty)
        #expect(result.rejectedCount == 1)
    }
}
