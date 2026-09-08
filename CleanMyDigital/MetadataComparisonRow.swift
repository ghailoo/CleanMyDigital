//
//  MetadataComparisonRow.swift
//  CleanMyDigital
//

import SwiftUI

/// One field's "current value / provider value" row, shared by every place
/// in the app that compares a file's tags against a metadata-provider
/// match: `MetadataLookupView.swift`'s per-file `ComparisonView` (Discogs)
/// and `MusicBrainzComparisonView`, and `ApplyFoundMatchesSheetView`'s
/// per-file comparison table. One layout, reused, rather than three
/// near-identical ones — each caller supplies its own trailing
/// `indicator` since what that indicator means differs (a plain
/// fillable/not checkmark for the two per-file tabs, a richer
/// agree/differ/will-fill/no-data marker for the batch review sheet's
/// `MatchComparison.Outcome`).
///
/// Both value columns are single-line and truncate rather than wrap — a
/// long value (a multi-genre list, say) would otherwise push the row
/// taller and break the table's alignment — with the full untruncated text
/// available on hover via `.help`.
struct MetadataComparisonRow<Indicator: View>: View {
    let fieldLabel: String
    let currentValue: String?
    let matchColumnLabel: String
    let matchValue: String?
    /// Shown in place of a bare "–" when `matchValue` is nil for an
    /// explainable reason (e.g. "Discogs search results have no per-track
    /// title") rather than just "no info this time."
    var matchPlaceholder: String?
    /// Renders at a smaller size, tighter padding, and a uniformly muted
    /// color — for a field where both sides already agree: still visible
    /// as confirmation (that's the strongest signal a match is correct),
    /// but it isn't the reason someone opened this row, so it shouldn't
    /// compete for attention with the fields that are actually changing.
    /// Leaves the two existing per-file tabs' full-weight rendering
    /// untouched, since neither passes this.
    var isCondensed = false
    @ViewBuilder var indicator: () -> Indicator

    init(
        fieldLabel: String, currentValue: String?, matchColumnLabel: String, matchValue: String?,
        matchPlaceholder: String? = nil, isCondensed: Bool = false, @ViewBuilder indicator: @escaping () -> Indicator
    ) {
        self.fieldLabel = fieldLabel
        self.currentValue = currentValue
        self.matchColumnLabel = matchColumnLabel
        self.matchValue = matchValue
        self.matchPlaceholder = matchPlaceholder
        self.isCondensed = isCondensed
        self.indicator = indicator
    }

    var body: some View {
        HStack(alignment: .top) {
            Text(fieldLabel)
                .font(isCondensed ? .caption.weight(.medium) : .subheadline.weight(.medium))
                .foregroundStyle(isCondensed ? .secondary : .primary)
                .frame(width: 100, alignment: .leading)
            valueColumn(
                currentValue?.isEmpty == false ? currentValue! : "–",
                caption: "Current", baseColor: AnyShapeStyle(.secondary))
            valueColumn(
                matchValue ?? matchPlaceholder ?? "–",
                caption: matchColumnLabel, baseColor: AnyShapeStyle(matchValue == nil ? .tertiary : .primary))
            indicator()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, isCondensed ? 4 : 8)
    }

    private func valueColumn(_ text: String, caption: String, baseColor: AnyShapeStyle) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(text)
                .font(isCondensed ? .caption : .body)
                .foregroundStyle(isCondensed ? AnyShapeStyle(.secondary) : baseColor)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(text)
            Text(caption).font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
