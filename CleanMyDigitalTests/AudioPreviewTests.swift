//
//  AudioPreviewTests.swift
//  CleanMyDigitalTests
//

import Foundation
import Testing
@testable import CleanMyDigital

struct AudioPreviewTests {
    /// An undecodable file must leave a quiet per-row message and no
    /// playing state — never throw out to the caller.
    @Test func undecodableFileRecordsInlineFailure() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).mp3")
        try Data("not audio".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let preview = AudioPreview()
        preview.play(url, root: nil)

        #expect(preview.playingURL == nil)
        #expect(preview.failures[url] != nil)
        #expect(preview.lastURL == url)
    }
}
