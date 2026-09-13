//
//  AfterApplyPresentation.swift
//  CleanMyDigital
//

import Foundation

/// What one field's "After Apply" cell should show in
/// `ApplyFoundMatchesSheetView`'s side-by-side before/after comparison —
/// pure and view-free, like `MatchComparisonBuilder`, so the layout can be
/// unit tested without SwiftUI.
///
/// Deliberately built ONLY from an already-computed `MatchComparison`'s
/// `outcome`/`currentValue`/`matchValue` — never re-derives whether a field
/// will be written, so the right pane can never promise a change
/// `MatchComparisonBuilder`/`LookupCandidate.buildChanges` wouldn't actually
/// make. `MatchComparison`'s classification logic itself is untouched.
struct AfterApplyPresentation: Equatable {
    /// Whether to visually call out this field's After Apply value — never
    /// the only signal a marker means something: pair it with the spoken
    /// accessibility label (see `accessibilityLabel(field:comparison:presentation:providerLabel:)`),
    /// not tint alone.
    enum Marker: Equatable {
        case none
        /// `.willFill` — the one outcome that actually changes the file,
        /// and the main thing this window communicates.
        case new
        /// `.agrees` — both sides already say the same thing.
        case confirmed
    }

    /// What the file will actually contain once applied. Only `.willFill`
    /// takes the match's value; every other outcome leaves the file
    /// untouched, so this mirrors `currentValue`, not `matchValue`.
    let displayValue: String?
    let marker: Marker
    /// A quiet secondary note shown only for `.differsButKept`, naming the
    /// disagreement without presenting it as a change — e.g. `Discogs:
    /// "Ben Lost" — not applied`. `nil` for every other outcome.
    let note: String?

    static func forField(_ comparison: MatchComparison, providerLabel: String) -> AfterApplyPresentation {
        switch comparison.outcome {
        case .willFill:
            AfterApplyPresentation(displayValue: comparison.matchValue, marker: .new, note: nil)
        case .differsButKept:
            AfterApplyPresentation(
                displayValue: comparison.currentValue, marker: .none,
                note: comparison.matchValue.map { "\(providerLabel): \"\($0)\" — not applied" })
        case .agrees:
            AfterApplyPresentation(displayValue: comparison.currentValue, marker: .confirmed, note: nil)
        case .noMatchData:
            AfterApplyPresentation(displayValue: comparison.currentValue, marker: .none, note: nil)
        }
    }

    /// The single spoken label VoiceOver reads for one field, spanning both
    /// panes — `ApplyFoundMatchesSheetView` hides the Current pane's own
    /// element and folds its value in here, so a field is one stop, not
    /// two, and the "added" signal never rides on colour/badge alone.
    /// Artwork has no real text value (`MatchComparison`'s values are
    /// presence markers — see `MatchComparisonBuilder.artworkComparison`),
    /// so it's worded around presence instead of quoting "Present".
    static func accessibilityLabel(
        field: MetadataField, comparison: MatchComparison, presentation: AfterApplyPresentation, providerLabel: String
    ) -> String {
        let isArtwork = field == .artwork
        let current = isArtwork ? (comparison.currentValue != nil ? "present" : "none") : (comparison.currentValue ?? "empty")
        switch comparison.outcome {
        case .willFill:
            let incoming = isArtwork ? "new artwork" : (presentation.displayValue ?? "")
            return "\(field.rawValue): \(current), will become \(incoming)"
        case .differsButKept:
            return "\(field.rawValue): \(current), unchanged, \(providerLabel) suggests \(comparison.matchValue ?? "")"
        case .agrees:
            return "\(field.rawValue): \(current), confirmed"
        case .noMatchData:
            return "\(field.rawValue): \(current), no data to compare"
        }
    }

    /// The fixed field order every file's two panes render in. Track Number
    /// is dropped entirely for Singles rather than shown as a permanent
    /// dash — Singles don't check it at all (see `AudioFile.applicableFields`).
    private static let fieldOrder: [MetadataField] = [.title, .artist, .album, .year, .genre, .trackNumber, .artwork]

    static func orderedComparisons(_ comparisons: [MatchComparison], category: LibraryCategory) -> [MatchComparison] {
        let byField = Dictionary(uniqueKeysWithValues: comparisons.map { ($0.field, $0) })
        return fieldOrder
            .filter { $0 != .trackNumber || category != .singles }
            .compactMap { byField[$0] }
    }

    /// A file's row collapses to a single "No changes" line when nothing
    /// will actually be written. `.differsButKept` and `.noMatchData`
    /// fields don't count as changes — the file's tags stay exactly as they
    /// are either way — only `.willFill` does.
    static func hasAnyChange(_ comparisons: [MatchComparison]) -> Bool {
        comparisons.contains { $0.outcome == .willFill }
    }
}
