//
//  MetadataQueryCleanedTrackTitleTests.swift
//  CleanMyDigitalTests
//

import Testing
import Foundation
@testable import CleanMyDigital

/// Verifies `MetadataQuery.cleanedTrackTitle(from:artist:category:)` — the
/// filename-cleaning heuristics shared by `DiscogsQuery`/`MusicBrainzQuery`
/// (per-track search) and the album-completeness track-matching
/// (`AlbumComparisonView.loadDetail()`'s calls into
/// `DiscogsReleaseDetail.autoMatchedTrack`/`allMatchedTracks`).
struct MetadataQueryCleanedTrackTitleTests {

    // MARK: - Leading track number, bare forms

    @Test func stripsABareTrackNumberFollowedBySpaceHyphenSpace() {
        let cleaned = MetadataQuery.cleanedTrackTitle(from: "01 - Title.mp3", artist: "Artist", category: .albums)
        #expect(cleaned == "Title")
    }

    @Test func stripsABareTrackNumberFollowedByADot() {
        let cleaned = MetadataQuery.cleanedTrackTitle(from: "3. Title.mp3", artist: "Artist", category: .albums)
        #expect(cleaned == "Title")
    }

    @Test func stripsABareTrackNumberFollowedByAnUnderscore() {
        let cleaned = MetadataQuery.cleanedTrackTitle(from: "07_Title.mp3", artist: "Artist", category: .albums)
        #expect(cleaned == "Title")
    }

    @Test func stripsABareTrackNumberFollowedByAClosingParenthesis() {
        let cleaned = MetadataQuery.cleanedTrackTitle(from: "12) Title.mp3", artist: "Artist", category: .albums)
        #expect(cleaned == "Title")
    }

    // MARK: - Leading track number, wrapped in parentheses

    @Test func stripsATrackNumberWrappedInParenthesesFollowedBySpace() {
        let cleaned = MetadataQuery.cleanedTrackTitle(from: "(01) Title.mp3", artist: "Artist", category: .albums)
        #expect(cleaned == "Title")
    }

    @Test func stripsATrackNumberWrappedInParenthesesWithNoTrailingSeparator() {
        // The closing ")" is itself one of the trailing-separator characters
        // the bare-form regex already accepts, so this needs no space after
        // the parenthesized number to strip correctly.
        let cleaned = MetadataQuery.cleanedTrackTitle(from: "(12)Title.mp3", artist: "Artist", category: .albums)
        #expect(cleaned == "Title")
    }

    // MARK: - Leading "[Artist Name] " prefix

    @Test func stripsABracketedArtistPrefixThatExactlyMatchesTheKnownArtist() {
        let cleaned = MetadataQuery.cleanedTrackTitle(
            from: "[Anouar Brahem] Raf Raf.flac", artist: "Anouar Brahem", category: .albums)
        #expect(cleaned == "Raf Raf")
    }

    @Test func bracketedArtistStrippingAppliesToEveryCategoryNotJustSingles() {
        for category: LibraryCategory in [.singles, .albums, .compilations] {
            let cleaned = MetadataQuery.cleanedTrackTitle(
                from: "[Anouar Brahem] Raf Raf.flac", artist: "Anouar Brahem", category: category)
            #expect(cleaned == "Raf Raf")
        }
    }

    @Test func bracketedArtistMatchIsFuzzyAndCaseInsensitiveLikeTheDashCase() {
        // Bracket content is a substring of the known artist — same
        // either-direction contains comparison the Singles dash-stripping
        // logic already uses (e.g. covering collaborations).
        let cleaned = MetadataQuery.cleanedTrackTitle(
            from: "[brahem] Raf Raf.flac", artist: "Anouar Brahem", category: .albums)
        #expect(cleaned == "Raf Raf")
    }

    @Test func bracketedTextThatDoesNotMatchTheArtistIsLeftAlone() {
        let cleaned = MetadataQuery.cleanedTrackTitle(
            from: "[Live] Raf Raf.flac", artist: "Anouar Brahem", category: .albums)
        #expect(cleaned == "[Live] Raf Raf")
    }

    @Test func bracketedArtistIsLeftAloneWhenNoArtistIsKnown() {
        let cleaned = MetadataQuery.cleanedTrackTitle(
            from: "[Anouar Brahem] Raf Raf.flac", artist: "", category: .albums)
        #expect(cleaned == "[Anouar Brahem] Raf Raf")
    }

    /// The real-world case this fixes: for `.compilations`, `artist` is
    /// forced to "Various" (see `DiscogsQuery`'s doc comment), which could
    /// never fuzzily match a real per-track artist like "Ice MC" — so the
    /// fuzzy-match gate the other categories use would leave the bracket
    /// in place forever. Compilations strip it unconditionally instead,
    /// since a leading "[Artist Name]" there is the per-track artist by
    /// convention.
    @Test func compilationsStripTheBracketedPrefixUnconditionallyEvenWhenItDoesNotMatchTheArtist() {
        let cleaned = MetadataQuery.cleanedTrackTitle(
            from: "(01) [Ice MC] It's A Rainy Day (Euro Club Mix).flac", artist: "Various", category: .compilations)
        #expect(cleaned == "It's A Rainy Day (Euro Club Mix)")
    }

    /// Regression: only `.compilations` strips unconditionally — the other
    /// categories must still leave a non-matching bracket alone.
    @Test func singlesAndAlbumsStillGateTheBracketStripOnAFuzzyArtistMatch() {
        for category: LibraryCategory in [.singles, .albums] {
            let cleaned = MetadataQuery.cleanedTrackTitle(
                from: "[Ice MC] It's A Rainy Day.flac", artist: "Various", category: category)
            #expect(cleaned == "[Ice MC] It's A Rainy Day")
        }
    }

    @Test func bracketedTextIsOnlyStrippedNearTheStartNotLaterInTheTitle() {
        // "near the start" — anchored to the very beginning of the
        // (track-number-stripped) name, not matched anywhere in the string,
        // so a legitimate bracketed suffix elsewhere is left alone.
        let cleaned = MetadataQuery.cleanedTrackTitle(
            from: "Raf Raf [Anouar Brahem].flac", artist: "Anouar Brahem", category: .albums)
        #expect(cleaned == "Raf Raf [Anouar Brahem]")
    }

    // MARK: - The real-world failing example

    @Test func cleansTheRealWorldParenthesizedTrackNumberAndBracketedArtistExample() {
        let cleaned = MetadataQuery.cleanedTrackTitle(
            from: "(01) [Anouar Brahem] Raf Raf.flac", artist: "Anouar Brahem", category: .albums)
        #expect(cleaned == "Raf Raf")
    }

    // MARK: - Existing Singles-only "Artist - " stripping still holds

    @Test func singlesStripsALeadingArtistDashPrefixThatMatchesTheKnownArtist() {
        let cleaned = MetadataQuery.cleanedTrackTitle(
            from: "Anouar Brahem - Raf Raf (Extended Mix).mp3", artist: "Anouar Brahem", category: .singles)
        #expect(cleaned == "Raf Raf (Extended Mix)")
    }

    @Test func albumsAndCompilationsKeepADashInTheTitleIntact() {
        for category: LibraryCategory in [.albums, .compilations] {
            let cleaned = MetadataQuery.cleanedTrackTitle(
                from: "01 - Track - Reprise.mp3", artist: "Artist", category: category)
            #expect(cleaned == "Track - Reprise")
        }
    }

    @Test func combinedParenthesizedTrackNumberAndBracketedArtistWorksAlongsideTheSinglesDashSplit() {
        // The bracket step runs before the Singles dash split, so a
        // bracketed-artist prefix doesn't get misread as the "Artist" side
        // of an "Artist - Title" split once it's already been removed.
        let cleaned = MetadataQuery.cleanedTrackTitle(
            from: "(02) [Anouar Brahem] Track - Reprise.mp3", artist: "Anouar Brahem", category: .singles)
        #expect(cleaned == "Track - Reprise")
    }

    // MARK: - Never strips a trailing mix/version parenthetical (the fix)

    /// The real-world case that motivated this: "The KLF - 3 A.M. Eternal
    /// (Live At The S.S.L.)" found the exact pressing on Discogs with the
    /// mix name kept; stripping it down to "3 A.M. Eternal" found only
    /// generic, wrong pressings. For a maxi single, the mix/version name is
    /// often the single most identifying part of the title, not noise —
    /// `cleanedTrackTitle` must never remove or truncate it.
    @Test func neverStripsATrailingMixParentheticalFromASinglesFileName() {
        let cleaned = MetadataQuery.cleanedTrackTitle(
            from: "1. The KLF - 3 A.M. Eternal (Live At The S.S.L.).flac", artist: "The KLF", category: .singles)
        #expect(cleaned == "3 A.M. Eternal (Live At The S.S.L.)")
    }

    @Test func neverStripsATrailingMixParentheticalRegardlessOfCategory() {
        for category: LibraryCategory in [.singles, .albums, .compilations] {
            let cleaned = MetadataQuery.cleanedTrackTitle(
                from: "Track Title (Euro Club Mix).mp3", artist: "Artist", category: category)
            #expect(cleaned == "Track Title (Euro Club Mix)")
        }
    }

    /// `strippingTrailingParenthetical` — the function that WOULD strip a
    /// mix name — still exists and still works; this just confirms
    /// `cleanedTrackTitle` never calls it, by checking its output would
    /// have differed if it had.
    @Test func strippingTrailingParentheticalRemainsAvailableButUnusedByCleanedTrackTitle() {
        let title = "3 A.M. Eternal (Live At The S.S.L.)"
        #expect(MetadataQuery.strippingTrailingParenthetical(from: title) == "3 A.M. Eternal")

        let cleaned = MetadataQuery.cleanedTrackTitle(
            from: "The KLF - \(title).flac", artist: "The KLF", category: .singles)
        #expect(cleaned == title)
    }
}

struct FeaturedArtistStrippingTests {
    @Test func dropsTheFeaturedCreditButKeepsTheMixName() {
        #expect(MetadataQuery.cleanedTrackTitle(
            from: "02 - YBU - Soul Magic (funk vocal version) (feat. Jonell).flac",
            artist: "YBU", category: .singles) == "Soul Magic (funk vocal version)")
    }

    @Test func handlesBracketsBareCreditsAndCase() {
        #expect(MetadataQuery.strippingFeaturedArtist(from: "Soul Magic [Ft. Jonell]") == "Soul Magic")
        #expect(MetadataQuery.strippingFeaturedArtist(from: "Soul Magic feat. Jonell (Funk Mix)") == "Soul Magic (Funk Mix)")
        #expect(MetadataQuery.strippingFeaturedArtist(from: "Soul Magic Featuring Jonell") == "Soul Magic")
    }

    @Test func handlesAccentedSpellings() {
        #expect(MetadataQuery.cleanedTrackTitle(
            from: "09 My Love Is Your Love (f\u{00E9}at. Dyme) [Wyclef Remix].m4a",
            artist: "Whitney Houston", category: .singles) == "My Love Is Your Love [Wyclef Remix]")
    }

    @Test func leavesTitlesWithoutACreditAlone() {
        #expect(MetadataQuery.strippingFeaturedArtist(from: "The Feat Of Clay") == "The Feat Of Clay")
        #expect(MetadataQuery.strippingFeaturedArtist(from: "Loft Party (Club Mix)") == "Loft Party (Club Mix)")
    }
}

struct FileNameSeparatorTests {
    @Test func splitsArtistAcrossNonBreakingSpacesAndDashVariants() {
        #expect(MetadataQuery.cleanedTrackTitle(
            from: "Young MC\u{00A0}-\u{00A0}Principals Office  (12 Inch Version).mp3",
            artist: "Young MC", category: .singles) == "Principals Office (12 Inch Version)")
        #expect(MetadataQuery.artistParsedFromFileName("Young MC – Principals Office.mp3") == "Young MC")
    }
}

struct SceneGroupTagTests {
    @Test func dropsTheTrailingGroupTagFromALowercaseSceneName() {
        #expect(MetadataQuery.cleanedTrackTitle(
            from: "02-x-dream - live fast-die young-gem.mp3",
            artist: "X-Dream", category: .singles) == "live fast-die young")
    }

    @Test func leavesMixedCaseTitlesAlone() {
        #expect(MetadataQuery.strippingSceneGroupTag(from: "Show Me What You Got (Remix) Jay-Z") == "Show Me What You Got (Remix) Jay-Z")
        #expect(MetadataQuery.strippingSceneGroupTag(from: "Live Fast-Die Young") == "Live Fast-Die Young")
    }
}

/// The real file: "Archigram - Doggystyle_1318768774 - Crydamoure 2.mp3"
/// found nothing on Discogs until the download ID came out of the title.
struct IdentifierNumberTests {
    @Test func dropsADownloadIDGluedIntoTheFileName() {
        #expect(MetadataQuery.cleanedTrackTitle(
            from: "Archigram - Doggystyle_1318768774 - Crydamoure 2.mp3",
            artist: "Archigram", category: .singles) == "Doggystyle - Crydamoure 2")
    }

    @Test func keepsShortNumbersThatBelongToTheTitle() {
        #expect(MetadataQuery.strippingIdentifierNumber(from: "1999") == "1999")
        #expect(MetadataQuery.strippingIdentifierNumber(from: "Blink 182") == "Blink 182")
        #expect(MetadataQuery.strippingIdentifierNumber(from: "20000 Leagues") == "20000 Leagues")
        #expect(MetadataQuery.strippingIdentifierNumber(from: "Pacific 0101 (Remix Edit)") == "Pacific 0101 (Remix Edit)")
    }

    @Test func cleansUpTheSeparatorTheIDLeavesBehind() {
        #expect(MetadataQuery.strippingIdentifierNumber(from: "Doggystyle - 1318768774 - Crydamoure") == "Doggystyle - Crydamoure")
        #expect(MetadataQuery.strippingIdentifierNumber(from: "Doggystyle 1318768774") == "Doggystyle")
    }

    @Test func aTitleThatIsOnlyAnIDIsLeftAlone() {
        #expect(MetadataQuery.strippingIdentifierNumber(from: "1318768774") == "1318768774")
    }
}

struct TrailingDashSegmentTests {
    @Test func dropsTheLabelThatTrailsTheTitle() {
        #expect(MetadataQuery.strippingTrailingDashSegment(from: "Doggystyle - Crydamoure 2") == "Doggystyle")
    }

    @Test func dropsOnlyTheLastSegment() {
        #expect(MetadataQuery.strippingTrailingDashSegment(from: "A - B - C") == "A - B")
    }

    @Test func nilWhenThereIsNothingToDrop() {
        #expect(MetadataQuery.strippingTrailingDashSegment(from: "Doggystyle") == nil)
        #expect(MetadataQuery.strippingTrailingDashSegment(from: " - Crydamoure") == nil)
    }
}

/// Two more real files that found nothing: a rip named
/// "Artist - Album - NN - Title", and a duration typed into the filename.
struct FileNameNoiseTests {
    @Test func dropsTheAlbumAndTrackNumberAheadOfTheTitle() {
        #expect(MetadataQuery.cleanedTrackTitle(
            from: "Klangkarussell - Sonnentanz - 04 - Sonnentanz (Kellerkind Remix).flac",
            artist: "Klangkarussell", category: .singles) == "Sonnentanz (Kellerkind Remix)")
    }

    @Test func dropsATrailingDuration() {
        #expect(MetadataQuery.cleanedTrackTitle(
            from: "2. Soul Creation - Different Worlds (Kings Of Tomorrow Mix) (5-55).mp3",
            artist: "Soul Creation", category: .singles) == "Different Worlds (Kings Of Tomorrow Mix)")
        #expect(MetadataQuery.strippingDurationMarker(from: "Track (10:07)") == "Track")
        #expect(MetadataQuery.strippingDurationMarker(from: "Track [4.20]") == "Track")
    }

    @Test func leavesRealParentheticalsAlone() {
        #expect(MetadataQuery.strippingDurationMarker(from: "Track (Part 1-2)") == "Track (Part 1-2)")
        #expect(MetadataQuery.strippingDurationMarker(from: "Anthem (1999-2000)") == "Anthem (1999-2000)")
        #expect(MetadataQuery.strippingDurationMarker(from: "3 A.M. Eternal (Live At The S.S.L.)")
                == "3 A.M. Eternal (Live At The S.S.L.)")
    }

    @Test func leavesATitleWithoutANumberedSegmentAlone() {
        #expect(MetadataQuery.strippingTrackNumberSegment(from: "Track - Reprise") == "Track - Reprise")
        #expect(MetadataQuery.strippingTrackNumberSegment(from: "Doggystyle - Crydamoure 2") == "Doggystyle - Crydamoure 2")
    }
}

/// "…Chris Lake Remix [www.slider.kz].mp3" — a download site's watermark
/// stamped into the filename.
struct DownloadSiteTagTests {
    @Test func dropsTheSiteTagFromTheRealFile() {
        #expect(MetadataQuery.cleanedTrackTitle(
            from: "Josh Wink & Lil' Louis - French kiss (How's Your Evening So Far) Chris Lake Remix [www.slider.kz].mp3",
            artist: "Josh Wink & Lil' Louis", category: .singles)
            == "French kiss (How's Your Evening So Far) Chris Lake Remix")
    }

    @Test func dropsOtherShapesOfTheSameThing() {
        #expect(MetadataQuery.strippingDownloadSiteTag(from: "Track (mp3crazy.com)") == "Track")
        #expect(MetadataQuery.strippingDownloadSiteTag(from: "Track [Muzlan.ru]") == "Track")
        #expect(MetadataQuery.strippingDownloadSiteTag(from: "Track - www.site.ru") == "Track")
        #expect(MetadataQuery.strippingDownloadSiteTag(from: "[www.x.kz] Track") == "Track")
    }

    @Test func leavesRealTitlesAlone() {
        #expect(MetadataQuery.strippingDownloadSiteTag(from: "3 A.M. Eternal (Live At The S.S.L.)")
                == "3 A.M. Eternal (Live At The S.S.L.)")
        #expect(MetadataQuery.strippingDownloadSiteTag(from: "Finally (DJ Meri Mix)") == "Finally (DJ Meri Mix)")
        #expect(MetadataQuery.strippingDownloadSiteTag(from: "Mr. Vain (Club Mix)") == "Mr. Vain (Club Mix)")
    }

    // MARK: - Codec / container markers

    @Test func stripsABareTrailingCodecMarker() {
        let cleaned = MetadataQuery.cleanedTrackTitle(
            from: "02_Real McCoy - Come & Get Your Love (Junior's House Mix) DTS.wav",
            artist: "Real McCoy", category: .singles)
        #expect(cleaned == "Come & Get Your Love (Junior's House Mix)")
    }

    @Test func stripsABracketedCodecMarker() {
        let cleaned = MetadataQuery.cleanedTrackTitle(
            from: "Artist - Title [FLAC] (Club Mix).flac", artist: "Artist", category: .singles)
        #expect(cleaned == "Title (Club Mix)")
    }

    @Test func stripsATrailingBitrateMarker() {
        let cleaned = MetadataQuery.cleanedTrackTitle(
            from: "Artist - Title (Club Mix) - 320kbps.mp3", artist: "Artist", category: .singles)
        #expect(cleaned == "Title (Club Mix)")
    }

    @Test func keepsAMixNameThatIsNotACodec() {
        let cleaned = MetadataQuery.cleanedTrackTitle(
            from: "Artist - Title (Radio Edit).mp3", artist: "Artist", category: .singles)
        #expect(cleaned == "Title (Radio Edit)")
    }

    // MARK: - Scene-style filenames (underscores, bare dashes)

    @Test func splitsASceneStyleFileNameAtItsBareDash() {
        let cleaned = MetadataQuery.cleanedTrackTitle(
            from: "207-offer_nissim_feat_maya-first_time__jose_spinnin_cortex_remix-nvs.mp3",
            artist: "Offer Nissim", category: .singles)
        #expect(cleaned == "first time jose spinnin cortex remix")
    }

    @Test func sceneStyleArtistIsParsedFromTheFileNameToo() {
        #expect(MetadataQuery.artistParsedFromFileName(
            "207-offer_nissim_feat_maya-first_time__jose_spinnin_cortex_remix-nvs.mp3")
            == "offer nissim feat maya")
    }

    @Test func aNameWithSpacesIsNotTreatedAsSceneStyle() {
        let cleaned = MetadataQuery.cleanedTrackTitle(
            from: "Artist - Hi-Fi Title.mp3", artist: "Artist", category: .singles)
        #expect(cleaned == "Hi-Fi Title")
    }
}
