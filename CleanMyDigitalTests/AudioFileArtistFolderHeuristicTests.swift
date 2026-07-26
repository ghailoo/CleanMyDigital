//
//  AudioFileArtistFolderHeuristicTests.swift
//  CleanMyDigitalTests
//

import Testing
@testable import CleanMyDigital

struct AudioFileArtistFolderHeuristicTests {
    @Test func flagsAFolderNameContainingA4DigitYear() {
        #expect(AudioFile.looksLikeAlbumFolderName("2Pac - 1998 - Greatest Hits (Bootleg)"))
        #expect(AudioFile.looksLikeAlbumFolderName("Greatest Hits (2003)"))
    }

    @Test func flagsAFolderNameWithTwoOrMoreDashSeparators() {
        #expect(AudioFile.looksLikeAlbumFolderName("Various Artists - The Collection - Disc One"))
    }

    @Test func doesNotFlagAPlainArtistName() {
        #expect(!AudioFile.looksLikeAlbumFolderName("2Pac"))
        #expect(!AudioFile.looksLikeAlbumFolderName("The Prodigy"))
    }

    @Test func doesNotFlagAnArtistNameWithOnlyOneDashSeparator() {
        #expect(!AudioFile.looksLikeAlbumFolderName("Artist - Side Project"))
    }
}
