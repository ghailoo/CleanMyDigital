//
//  MatchComparisonBuilder.swift
//  CleanMyDigital
//

import Foundation

/// One field's before/after comparison between a scanned file and a
/// batch-lookup match — used by `ApplyFoundMatchesSheetView` to show, per
/// file, not just *that* a match was found but whether it actually agrees
/// with what the file already has.
struct MatchComparison: Identifiable, Equatable {
    /// What applying this match would actually do to `field` — the
    /// distinction that's otherwise invisible: three files can each show a
    /// found match and look identical, while one will genuinely change a
    /// field, one leaves a *different* value untouched, and one merely
    /// confirms what's already there.
    enum Outcome: Equatable {
        /// The file's field is empty and the match has a value — this
        /// mirrors `fillable.contains(field)` exactly (see
        /// `MatchComparisonBuilder`'s doc comment), so it's guaranteed to
        /// agree with what `LookupCandidate.buildChanges` will actually
        /// write.
        case willFill
        /// The file already has a value, the match has a *different* one,
        /// and nothing is written — the app never overwrites an existing
        /// tag. Worth a human's attention: this is the case that looks
        /// identical to `.agrees` unless the two values are shown side by
        /// side.
        case differsButKept
        /// Both sides already say the same thing (after trimming
        /// whitespace and folding case/diacritics) — the strongest signal
        /// this is the right match.
        case agrees
        /// Nothing to compare: either this provider's search results
        /// structurally never carry this field (see `unavailableNote`), or
        /// this particular result just didn't have a value for it. Never
        /// written, and no claim about agreement can be made either way.
        case noMatchData
    }

    let field: MetadataField
    /// The file's own current tag value, trimmed to nil when empty.
    let currentValue: String?
    /// The match's value for this field, trimmed to nil when empty or
    /// simply unavailable this time.
    let matchValue: String?
    /// Set only when `matchValue` is nil *because this provider's search
    /// results never carry this field at all* (Discogs: Title, Track
    /// Number — see `DiscogsRelease.fillableFields`'s doc comment;
    /// MusicBrainz: Genre, Track Number — see
    /// `MusicBrainzRecording.fillableFields`'s) — shown in place of a bare
    /// dash so it doesn't read as "the release has no title."
    let unavailableNote: String?
    let outcome: Outcome

    var id: MetadataField { field }
}

/// Builds the per-field `MatchComparison`s for a batch-lookup match — pure
/// and network-free, like `DuplicatePlanner`/`CollectionPlanner`.
///
/// `Outcome.willFill` is always derived from the *actual* precomputed
/// `fillable` set a batch lookup already stored (`LookupOutcome.found`'s
/// associated value), not re-derived from "is the current value empty" —
/// so what this shows can never drift from what
/// `LookupCandidate.buildChanges(fillable:discogsToken:)` will really
/// write. This matters most for MusicBrainz Artwork:
/// `MusicBrainzRecording.fillableFields` deliberately never includes it
/// (confirming a Cover Art Archive image actually exists needs a network
/// round-trip the batch lookup doesn't make — see that doc comment), so
/// even when `recording.coverArtURL` is non-nil this reads as "no data"
/// rather than falsely promising a fill that `applySelected()` won't
/// actually perform.
enum MatchComparisonBuilder {
    static func comparisons(file: AudioFile, candidate: LookupCandidate, fillable: Set<MetadataField>) -> [MatchComparison] {
        switch candidate {
        case .discogs(let release):
            return [
                textComparison(.artist, current: file.artist, match: release.parsedArtist, fillable: fillable),
                textComparison(.album, current: file.album, match: release.parsedReleaseTitle, fillable: fillable),
                textComparison(.year, current: file.year, match: release.year, fillable: fillable),
                textComparison(.genre, current: file.genre,
                               match: release.combinedGenre.isEmpty ? nil : release.combinedGenre, fillable: fillable),
                // Discogs search results are release-level only — no
                // per-track Title or Track Number ever comes back, only
                // the separate tracklist-match step either correction
                // path performs.
                textComparison(.title, current: file.title, match: nil, fillable: fillable,
                               unavailableNote: "Discogs search results have no per-track title"),
                textComparison(.trackNumber, current: file.trackNumber, match: nil, fillable: fillable,
                               unavailableNote: "Discogs search results have no per-track number"),
                artworkComparison(
                    hasCurrentArtwork: file.hasArtwork,
                    matchArtworkAvailable: (release.coverImageURL ?? release.thumbURL) != nil,
                    fillable: fillable),
            ]
        case .musicBrainz(let recording):
            return [
                textComparison(.title, current: file.title,
                                match: recording.title.isEmpty ? nil : recording.title, fillable: fillable),
                textComparison(.artist, current: file.artist,
                                match: recording.artistNames.isEmpty ? nil : recording.artistNames, fillable: fillable),
                textComparison(.album, current: file.album, match: recording.releaseTitle, fillable: fillable),
                textComparison(.year, current: file.year, match: recording.yearString, fillable: fillable),
                // MusicBrainz recordings carry no genre at all.
                textComparison(.genre, current: file.genre, match: nil, fillable: fillable,
                               unavailableNote: "Not in MusicBrainz search results"),
                textComparison(.trackNumber, current: file.trackNumber, match: nil, fillable: fillable,
                               unavailableNote: "Not in MusicBrainz search results"),
                artworkComparison(
                    hasCurrentArtwork: file.hasArtwork,
                    matchArtworkAvailable: recording.coverArtURL != nil,
                    fillable: fillable),
            ]
        }
    }

    private static func textComparison(
        _ field: MetadataField, current: String?, match: String?, fillable: Set<MetadataField>,
        unavailableNote: String? = nil
    ) -> MatchComparison {
        let currentValue = (current?.isEmpty == false) ? current : nil
        let matchValue = (match?.isEmpty == false) ? match : nil

        let outcome: MatchComparison.Outcome
        if fillable.contains(field) {
            outcome = .willFill
        } else if let currentValue, let matchValue {
            outcome = normalize(currentValue) == normalize(matchValue) ? .agrees : .differsButKept
        } else {
            outcome = .noMatchData
        }

        return MatchComparison(
            field: field, currentValue: currentValue, matchValue: matchValue,
            unavailableNote: matchValue == nil ? unavailableNote : nil, outcome: outcome)
    }

    /// Artwork can't be compared by value — only by presence — so
    /// "agrees" here means "both sides have *something*", not "the same
    /// image"; still a meaningful, honest signal (no conflict to flag),
    /// just a coarser one than the text fields get.
    private static func artworkComparison(
        hasCurrentArtwork: Bool, matchArtworkAvailable: Bool, fillable: Set<MetadataField>
    ) -> MatchComparison {
        let outcome: MatchComparison.Outcome
        if fillable.contains(.artwork) {
            outcome = .willFill
        } else if hasCurrentArtwork, matchArtworkAvailable {
            outcome = .agrees
        } else {
            outcome = .noMatchData
        }
        return MatchComparison(
            field: .artwork,
            currentValue: hasCurrentArtwork ? "Present" : nil,
            matchValue: matchArtworkAvailable ? "Present" : nil,
            unavailableNote: nil,
            outcome: outcome)
    }

    /// Case/diacritic-insensitive, whitespace-trimmed equality — deliberately
    /// literal rather than fuzzy: a file's "Eurodance" genre tag against a
    /// Discogs release's "Electronic, Euro House, Italodance" is a real
    /// example of values that are thematically related but must still read
    /// as "differs, kept," not "agrees."
    private static func normalize(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
