//
//  FileSearchTests.swift
//  CleanMyDigitalTests
//

import Foundation
import Testing
@testable import CleanMyDigital

private func makeFile(
    path: String = "/Music/Daft Punk/01 One More Time.flac",
    title: String? = "One More Time",
    artist: String? = "Daft Punk",
    album: String? = "Discovery",
    year: String? = "2001",
    genre: String? = "House",
    trackNumber: String? = "1/14"
) -> AudioFile {
    let url = URL(fileURLWithPath: path)
    return AudioFile(
        url: url,
        fileName: url.lastPathComponent,
        fileExtension: url.pathExtension.lowercased(),
        sizeBytes: 1024,
        duration: 320,
        bitrateKbps: 1000,
        title: title,
        artist: artist,
        album: album,
        artworkThumbnail: nil,
        year: year,
        genre: genre,
        trackNumber: trackNumber,
        category: .singles,
        expectedArtist: nil,
        isReadable: true
    )
}

private func matches(_ query: String, _ file: AudioFile = makeFile()) -> Bool {
    FileSearch.matches(file, terms: FileSearch.terms(in: query))
}

@Suite struct FileSearchParsingTests {
    @Test func blankQueryHasNoTerms() {
        #expect(FileSearch.terms(in: "   ").isEmpty)
    }

    @Test func splitsOnWhitespace() {
        let terms = FileSearch.terms(in: "daft  discovery")
        #expect(terms.count == 2)
        #expect(terms.allSatisfy { $0.field == nil && !$0.isNegated })
    }

    @Test func readsFieldPrefix() {
        let terms = FileSearch.terms(in: "artist:daft")
        #expect(terms == [.init(field: .artist, text: "daft", isNegated: false)])
    }

    @Test func unknownPrefixStaysPartOfTheText() {
        // "Pt. 2: Reprise" shouldn't be read as a field named "pt. 2".
        let terms = FileSearch.terms(in: "remix:dub")
        #expect(terms == [.init(field: nil, text: "remix:dub", isNegated: false)])
    }

    @Test func quotesKeepAPhraseTogether() {
        let terms = FileSearch.terms(in: "album:\"hotel costes\"")
        #expect(terms == [.init(field: .album, text: "hotel costes", isNegated: false)])
    }

    @Test func leadingDashNegates() {
        let terms = FileSearch.terms(in: "-flac")
        #expect(terms == [.init(field: nil, text: "flac", isNegated: true)])
    }

    @Test func aLoneDashIsNotATerm() {
        #expect(FileSearch.terms(in: "-").isEmpty)
    }
}

@Suite struct FileSearchMatchingTests {
    @Test func bareTermSearchesEveryField() {
        #expect(matches("discovery"))     // album
        #expect(matches("house"))         // genre
        #expect(matches("2001"))          // year
        #expect(matches("One More"))      // title and file name
        #expect(!matches("nirvana"))
    }

    @Test func everyTermHasToMatch() {
        #expect(matches("daft discovery"))
        #expect(!matches("daft nevermind"))
    }

    @Test func fieldPrefixRestrictsTheMatch() {
        #expect(matches("artist:daft"))
        // "Discovery" is the album, so it must not match as an artist.
        #expect(!matches("artist:discovery"))
    }

    @Test func negationExcludes() {
        #expect(!matches("-daft"))
        #expect(matches("-nirvana"))
        #expect(matches("daft -nevermind"))
    }

    @Test func searchesFormatAndFolder() {
        #expect(matches("format:flac"))
        #expect(!matches("format:mp3"))
        #expect(matches("folder:\"Daft Punk\""))
    }

    @Test func missingTagsDontMatchButDontCrash() {
        let bare = makeFile(title: nil, artist: nil, album: nil, year: nil, genre: nil, trackNumber: nil)
        #expect(!matches("artist:daft", bare))
        #expect(matches("One More", bare))   // still in the file name
    }
}
