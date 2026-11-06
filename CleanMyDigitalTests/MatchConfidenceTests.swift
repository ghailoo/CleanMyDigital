//
//  MatchConfidenceTests.swift
//  CleanMyDigitalTests
//

import Foundation
import Testing
@testable import CleanMyDigital

@Suite struct MatchScoreWordTests {
    @Test func splitsOnAnythingThatIsntALetterOrNumber() {
        #expect(MatchScore.words(in: "Josh Wink & Lil' Louis") == ["josh", "wink", "lil", "louis"])
    }

    @Test func foldsCaseAndAccents() {
        #expect(MatchScore.words(in: "Ultra Naté") == MatchScore.words(in: "ULTRA NATE"))
    }

    @Test func dropsBracketsAndFeatCredits() {
        // A release is titled "Finally"; the mix names a track inside it.
        #expect(MatchScore.words(in: "Finally (DJ Meri Mix)") == ["finally"])
        #expect(MatchScore.words(in: "Kings Of Tomorrow Feat. Julie McKnight")
                == ["kings", "of", "tomorrow"])
    }
}

@Suite struct MatchScoreConfidenceTests {
    @Test func sameNameIsConfident() {
        #expect(MatchScore.confidence(
            fileName: "Kings Of Tomorrow Finally",
            resultName: "Kings Of Tomorrow - Finally") == .confident)
    }

    @Test func wordOrderDoesntMatter() {
        #expect(MatchScore.confidence(
            fileName: "Finally Kings Of Tomorrow",
            resultName: "Kings Of Tomorrow - Finally") == .confident)
    }

    /// The real file: the tag misspells the artist, and the release credits
    /// a featured singer the file doesn't.
    @Test func aTypoAndAFeatCreditStillMatch() {
        #expect(MatchScore.confidence(
            fileName: "Kings Of Tommorow Finally (DJ Meri Mix)",
            resultName: "Kings Of Tomorrow Feat. Julie McKnight - Finally") == .confident)
    }

    @Test func coveringTheFileButCarryingExtraWordsIsOnlyReview() {
        // Every word of the file is there, but the release says much more.
        let confidence = MatchScore.confidence(
            fileName: "Sonnentanz",
            resultName: "Klangkarussell - Sonnentanz Summer Sun Remixes Deluxe")
        #expect(confidence == .review)
    }

    /// The real file: the title is *inside* the brackets, and a second
    /// track's name trails it. Stripping brackets throws the title away.
    @Test func aTitleInsideBracketsStillMatches() {
        #expect(MatchScore.confidence(
            fileName: "nikke nicole ( nikke does it better ) miller lite",
            resultName: "Nikke Nicole - Nikke Does It Better") == .review)
        // The trailing "miller lite" is a second track on the release, so it
        // can't be confident — but it's the user's to tick, not a no-match.
        #expect(MatchScore.confidence(
            fileName: "nikke nicole ( nikke does it better )",
            resultName: "Nikke? Nicole!* - Nikke Does It Better") == .confident)
    }

    @Test func aDifferentReleaseIsNoMatch() {
        #expect(MatchScore.confidence(
            fileName: "Josh Wink Lil Louis French Kiss",
            resultName: "Daft Punk - Discovery") == .none)
    }

    @Test func halfTheWordsIsNoMatch() {
        #expect(MatchScore.confidence(
            fileName: "Soul Creation Different Worlds",
            resultName: "Soul Creation - Pure Sounds") == .none)
    }

    @Test func percentagesReportBothDirections() {
        let (coverage, balance) = MatchScore.percentages(
            fileName: "Sonnentanz",
            resultName: "Klangkarussell Sonnentanz")
        #expect(coverage == 1.0)          // the file's one word is there
        #expect(balance < 0.9)            // but the result says twice as much
    }

    @Test func anEmptyNameScoresNothing() {
        #expect(MatchScore.confidence(fileName: "", resultName: "Daft Punk - Discovery") == .none)
        #expect(MatchScore.confidence(fileName: "Daft Punk", resultName: "") == .none)
    }

    @Test func aSharedWordIsCountedOnce() {
        // "Sonnentanz - Sonnentanz" must not score twice off one result word.
        let (coverage, _) = MatchScore.percentages(
            fileName: "Sonnentanz Sonnentanz", resultName: "Sonnentanz")
        #expect(coverage == 0.5)
    }
}
