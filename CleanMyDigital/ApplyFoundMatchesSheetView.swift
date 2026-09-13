//
//  ApplyFoundMatchesSheetView.swift
//  CleanMyDigital
//

import SwiftUI

/// Reviews and applies "Find All Metadata" batch-lookup matches —
/// `LibraryScanner.lookupOutcome` picks `releases.first` with no human
/// review, so this is where a wrong first hit gets caught before it's
/// written, rather than applied silently. Grouped by folder (`List`/
/// `Section`, same pattern as `DuplicatesSheetView`), since a 12-track
/// album resolves to 12 rows all sharing one release — reviewing and
/// correcting those one at a time is unusable. Writes sequentially via
/// `scanner.applyTagChanges`, same as every other batch write action in
/// this codebase (`AlbumComparisonView.applyToAlbum()`, `CollectSheetView`,
/// `DuplicatesSheetView`) — never parallelized.
///
/// Two correction paths, since they're genuinely different jobs:
/// - Per file: opens the existing per-file `MetadataLookupView`, where the
///   user can re-search with corrected terms and apply.
/// - Per folder (Albums/Compilations only — see `FoundMatchGroup.albumGroup`):
///   opens the existing `AlbumMetadataLookupView` for that folder's
///   `AlbumGroup`, which searches once, matches every file in the folder
///   against the chosen release's tracklist, and applies to all of them —
///   the right tool when the batch picked the wrong release for a whole
///   album/compilation, the common failure mode.
///
/// Every file gets a side-by-side "Current" / "After Apply" comparison
/// (`comparisonPanes`) — the two panes are ONE row's two halves inside the
/// same `List`, not two independently-scrolling views, so they can never
/// drift apart while scrolling. Both panes always list the same fields in
/// the same order (`AfterApplyPresentation.orderedComparisons`); the After
/// Apply side renders each field's `AfterApplyPresentation` — never the raw
/// match value directly — so a field only looks changed when it will
/// actually be written. A file with nothing that will change collapses to
/// one "No changes" line instead of repeating seven identical-looking
/// fields (`AfterApplyPresentation.hasAnyChange`).
///
/// The matched release's own identity (title, year, genre, cover, Discogs
/// link) is shown once per *section* for Albums/Compilations — every file
/// in that kind of folder genuinely found the same match — or once per
/// *file* for Singles, whose files are unrelated releases by definition
/// (see `FoundMatchGroup.albumGroup`'s doc comment); either way it's
/// anchored above the After Apply pane specifically (`twoPaneRow`), since
/// that's where the new values come from.
///
/// Discogs matches here never fill Title/Track Number — Discogs search
/// results are release-level only (see `DiscogsRelease.fillableFields`'s
/// own doc comment). That's an existing, accepted limitation; either
/// correction path's tracklist-match step remains the way to fill those
/// for a Discogs match.
struct ApplyFoundMatchesSheetView: View {
    let scanner: LibraryScanner

    @AppStorage("discogsToken") private var discogsToken = ""
    @AppStorage("backupOriginalsBeforeWriting") private var backupOriginalsBeforeWriting = true

    /// Mirrors `AlbumComparisonView.ApplyOutcome` — distinguishes a file
    /// that failed to write from one that had nothing left to write
    /// (already complete by the time this ran) and from one that wrote
    /// successfully but couldn't back up the original first (backup
    /// failures don't block the write — see `LibraryScanner.applyTagChanges`).
    enum ApplyOutcome {
        case applied
        case appliedWithoutBackup(String)
        case alreadyComplete
        case failed(String)
    }

    @State private var isApplying = false
    @State private var outcomesByURL: [URL: ApplyOutcome] = [:]
    @State private var applySummary: String?
    /// How far `applySelected()` has gotten through its snapshot of
    /// selected files — `applyTotalCount` is fixed for the run,
    /// `applyCompletedCount` advances one file at a time. Exists because
    /// `selection`/`targets` themselves can't be used for this mid-run: see
    /// `footerStatusText`.
    @State private var applyCompletedCount = 0
    @State private var applyTotalCount = 0
    @State private var selection: Set<URL> = []
    /// Every target URL `selection` has ever been synced against — lets
    /// `syncSelection()` tell "a file that's new since last sync" (start it
    /// selected, per "all selected by default") apart from "a file the
    /// user explicitly deselected earlier and is still here" (leave it
    /// alone), rather than only being able to reset to "everything" or
    /// "nothing".
    @State private var knownTargetURLs: Set<URL> = []
    @State private var metadataLookupFile: AudioFile?
    @State private var metadataLookupInitialProvider: MetadataProvider = .discogs
    @State private var albumLookupGroup: AlbumGroup?

    /// Every scanned file with a `.found` batch-lookup outcome, in table
    /// order. Recomputed live, so a file drops off this list the moment
    /// it's applied (`applyTagChanges` clears its `lookupResults` entry) —
    /// including via either correction path, which both apply through the
    /// same `scanner.applyTagChanges`.
    private var targets: [AudioFile] {
        scanner.files.filter { scanner.lookupResults[$0.url]?.isFound == true }
    }

    /// Recomputed live alongside `targets`, same reasoning.
    private var groups: [FoundMatchGroup] {
        FoundMatchPlanner.groups(targets: targets, albumGroups: AlbumCompletenessChecker.groups(for: scanner.files))
    }

    private var selectedTargets: [AudioFile] {
        targets.filter { selection.contains($0.url) }
    }

    var body: some View {
        // No title — the window titlebar (`WindowGroup("Apply Found
        // Matches", ...)` in CleanMyDigitalApp.swift) already says it;
        // repeating it in the subtitle's headline was a pure duplicate.
        // .extraWide — two full comparison columns side by side need more
        // room than any other auxiliary window.
        SheetWindowContainer(
            subtitle: Self.headerSubtitle(groups: groups),
            windowID: "apply-found-matches",
            size: .extraWide
        ) {
            content
        } footer: {
            footer
        }
        .onAppear { syncSelection() }
        .onChange(of: scanner.lookupCompletedCount) { syncSelection() }
        .sheet(item: $metadataLookupFile) { file in
            MetadataLookupView(file: file, scanner: scanner, initialProvider: metadataLookupInitialProvider)
                .onDisappear { syncSelection() }
        }
        .sheet(item: $albumLookupGroup) { group in
            AlbumMetadataLookupView(group: group, scanner: scanner)
                .onDisappear { syncSelection() }
        }
    }

    /// Only mentions "Re-match…" when this batch actually has at least one
    /// group with that control (`sectionShowsSharedMatchIdentity` — an
    /// Albums or Compilations folder). A batch made entirely of Singles has
    /// no group-level correction anywhere in it, only per-file "Correct…",
    /// so describing a "Re-match…" affordance there would point at a
    /// control that doesn't exist. A `static func` (not a computed
    /// property) so it's testable without a live `LibraryScanner` — same
    /// pattern as `ContentView.fileMatches`.
    static func headerSubtitle(groups: [FoundMatchGroup]) -> String {
        let base = "Review what each file's batch lookup found before writing it. \"Correct…\" re-searches one file"
        guard groups.contains(where: sectionShowsSharedMatchIdentity) else { return base + "." }
        return base + "; \"Re-match…\" re-searches a whole album/compilation."
    }

    private var content: some View {
        Group {
            if targets.isEmpty {
                ContentUnavailableView {
                    Label("No Found Matches", systemImage: "magnifyingglass")
                } description: {
                    Text("Run \"Find All Metadata\" first, then come back here to review and apply what it found.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    columnHeaders
                    Divider()
                    List {
                        ForEach(groups) { group in
                            Section {
                                ForEach(group.files) { file in
                                    // Albums/Compilations share one release, shown
                                    // once in the section header (`sectionHeader`)
                                    // — but Singles files are unrelated releases by
                                    // definition, so each file shows its own match
                                    // here instead. Exact inverse of
                                    // `sectionShowsSharedMatchIdentity`.
                                    fileRow(file, showsOwnMatchIdentity: !Self.sectionShowsSharedMatchIdentity(for: group))
                                }
                            } header: {
                                sectionHeader(group)
                            }
                        }
                    }
                    .listStyle(.inset)
                }
            }
        }
        .consistentAnimation(targets.isEmpty)
    }

    /// Pinned above the `List` (not inside it), so it never scrolls away —
    /// unlike a per-section/per-row header, one column header for the whole
    /// window reads as "these two columns run the length of the list."
    /// Uses the same `twoPaneRow`/leading-indent skeleton as every file's
    /// comparison, so the pane split roughly lines up underneath it.
    private var columnHeaders: some View {
        twoPaneRow {
            Text("Current")
        } right: {
            Text("After Apply")
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .padding(.leading, Self.fieldsIndent)
    }

    /// A left half and a right half of equal, responsive width around a
    /// `Divider` — the one skeleton shared by the column headers, each
    /// section's match-identity header, and every file's field comparison,
    /// so their pane boundaries all line up without measuring anything.
    private func twoPaneRow<Left: View, Right: View>(
        @ViewBuilder _ left: () -> Left, @ViewBuilder right: () -> Right
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            left().frame(maxWidth: .infinity, alignment: .leading)
            Divider()
            right().frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// How far the field-comparison area (and the column headers above it)
    /// is indented — roughly under the checkbox on the row above, so values
    /// read as belonging to that file rather than starting at the margin.
    private static let fieldsIndent: CGFloat = 26

    // MARK: - Section header (folder identity + the shared match identity)

    private func sectionHeader(_ group: FoundMatchGroup) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Toggle("", isOn: sectionSelectionBinding(for: group))
                    .labelsHidden()
                    .accessibilityLabel("Select all files in \(sectionTitle(for: group))")
                VStack(alignment: .leading, spacing: 1) {
                    Text(sectionTitle(for: group)).font(.subheadline.weight(.semibold))
                    Text(Self.sectionSubtitle(for: group))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let albumGroup = group.albumGroup {
                    Button("Re-match \(albumGroup.category == .compilations ? "Compilation" : "Album")…") {
                        albumLookupGroup = albumGroup
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            }
            // Every file in this folder found the same match — shown once
            // here rather than repeated on every row below, anchored above
            // the After Apply pane specifically (empty left half) since
            // that's where the new values come from. Only true for
            // Albums/Compilations; `representativeMatch` returns nil for a
            // Singles folder, where each file's row shows its own match
            // instead (see `fileRow`).
            if let match = representativeMatch(for: group) {
                twoPaneRow {
                    EmptyView()
                } right: {
                    matchIdentity(candidate: match.candidate)
                }
                .padding(.leading, Self.fieldsIndent)
            }
        }
        .padding(.bottom, 2)
    }

    private func sectionTitle(for group: FoundMatchGroup) -> String {
        group.albumGroup?.albumTitle ?? group.folderURL.lastPathComponent
    }

    /// Deliberately doesn't say "N tracks matched to this release" for a
    /// Singles folder (`albumGroup == nil`) — Singles are typically loose
    /// files that each resolve to their own, unrelated release, so
    /// implying they share one would be misleading. Albums/Compilations
    /// genuinely do share one release, so that's worth saying explicitly.
    /// A `static func` (not an instance method) so it's directly testable —
    /// same pattern as `ContentView.fileMatches`.
    static func sectionSubtitle(for group: FoundMatchGroup) -> String {
        let files = group.files.count == 1 ? "file" : "files"
        guard let albumGroup = group.albumGroup else {
            return "\(group.files.count) \(files) in this folder"
        }
        let noun = albumGroup.category == .compilations ? "compilation" : "album"
        return "\(group.files.count) \(files) matched — correct the whole \(noun) if the release is wrong"
    }

    private func sectionSelectionBinding(for group: FoundMatchGroup) -> Binding<Bool> {
        Binding(
            get: { group.files.allSatisfy { selection.contains($0.url) } },
            set: { isOn in
                for file in group.files {
                    if isOn { selection.insert(file.url) } else { selection.remove(file.url) }
                }
            }
        )
    }

    /// The match every file in `group` (that has one) resolved to, for the
    /// section header's shared identity block — just the first file's, on
    /// the assumption (true in practice: they were all searched from the
    /// same folder/album context) that a folder's files converge on one
    /// release. If a folder's files genuinely found different releases,
    /// this shows whichever was found first; each row's own "Correct…"
    /// still operates on that file specifically regardless.
    ///
    /// Only meaningful for Albums/Compilations — a Singles folder's files
    /// are unrelated releases by definition (ten singles are ten different
    /// records), so there's no single "representative" match to show for
    /// one; this returns nil there rather than let the caller assert one
    /// exists. `fileRow` shows each Singles file's own match instead.
    private func representativeMatch(
        for group: FoundMatchGroup
    ) -> (provider: MetadataProvider, candidate: LookupCandidate, fillable: Set<MetadataField>)? {
        guard Self.sectionShowsSharedMatchIdentity(for: group) else { return nil }
        return group.files.lazy.compactMap { found(for: $0) }.first
    }

    /// True only for Albums/Compilations (`group.albumGroup != nil`), where
    /// every file in the folder genuinely resolved to the same release and
    /// the section header can show that match once for all of them. False
    /// for Singles, where each file is its own unrelated release — driving
    /// both `representativeMatch` (returns nil there) and `fileRow`'s
    /// per-file identity (shown there instead, as the exact inverse) from
    /// one source of truth rather than two independent `albumGroup != nil`
    /// checks that could drift apart. A `static func` so it's directly
    /// testable — same pattern as `ContentView.fileMatches`.
    static func sectionShowsSharedMatchIdentity(for group: FoundMatchGroup) -> Bool {
        group.albumGroup != nil
    }

    // MARK: - File row

    /// This file's `.found` outcome, split into its three associated
    /// values — computed once per row rather than re-pattern-matching
    /// `scanner.lookupResults[file.url]` separately for the comparison
    /// panes and the "Correct…" button.
    private func found(for file: AudioFile) -> (provider: MetadataProvider, candidate: LookupCandidate, fillable: Set<MetadataField>)? {
        guard case .found(let provider, let candidate, let fillable) = scanner.lookupResults[file.url] else { return nil }
        return (provider, candidate, fillable)
    }

    /// `showsOwnMatchIdentity` is true for a Singles folder (`albumGroup ==
    /// nil`) — unlike Albums/Compilations, its files are unrelated releases
    /// by definition, so there's no shared identity in the section header
    /// above (see `representativeMatch`) and this file's own match is shown
    /// right here instead, anchored above its own After Apply pane.
    private func fileRow(_ file: AudioFile, showsOwnMatchIdentity: Bool) -> some View {
        let found = found(for: file)

        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 10) {
                Toggle("", isOn: selectionBinding(for: file.url))
                    .labelsHidden()
                    .accessibilityLabel("Select \(file.fileName)")

                VStack(alignment: .leading, spacing: 2) {
                    Text(file.fileName).font(.callout).lineLimit(1)
                    outcomeLabel(for: file)
                }

                Spacer()

                Button("Correct…") {
                    metadataLookupInitialProvider = found?.provider ?? .discogs
                    metadataLookupFile = file
                }
                .buttonStyle(.link)
                .font(.caption)
            }

            if let found {
                if showsOwnMatchIdentity {
                    twoPaneRow {
                        EmptyView()
                    } right: {
                        matchIdentity(candidate: found.candidate)
                    }
                    .padding(.leading, Self.fieldsIndent)
                }

                let comparisons = MatchComparisonBuilder.comparisons(
                    file: file, candidate: found.candidate, fillable: found.fillable)

                if AfterApplyPresentation.hasAnyChange(comparisons) {
                    comparisonPanes(comparisons, file: file, candidate: found.candidate, providerLabel: found.provider.rawValue)
                        .padding(.leading, Self.fieldsIndent)
                } else {
                    Text(Self.noChangesText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, Self.fieldsIndent)
                }
            }
        }
        .padding(.vertical, 3)
    }

    private func selectionBinding(for url: URL) -> Binding<Bool> {
        Binding(
            get: { selection.contains(url) },
            set: { isOn in
                if isOn { selection.insert(url) } else { selection.remove(url) }
            }
        )
    }

    @ViewBuilder
    private func artworkThumbnail(for candidate: LookupCandidate, size: CGFloat = 40) -> some View {
        let url: URL? = switch candidate {
        case .discogs(let release): release.coverImageURL ?? release.thumbURL
        case .musicBrainz(let recording): recording.coverArtURL
        }
        AsyncImage(url: url) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            Rectangle().fill(Color.gray.opacity(0.2))
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    /// The match's own identity — release/recording title, artist, year,
    /// genre, and (Discogs only, since `MusicBrainzRecording` carries
    /// neither) format and label — plus cover art and, for Discogs, a link
    /// to the release page so a questionable match can be checked against
    /// the real thing. Shown once per section for Albums/Compilations
    /// (see `sectionHeader`), where every file genuinely shares it, or once
    /// per file for Singles (see `fileRow`), where it doesn't; this answers
    /// "which record was found," while each file's own comparison panes
    /// answer "how does it compare to what's already here."
    @ViewBuilder
    private func matchIdentity(candidate: LookupCandidate) -> some View {
        HStack(alignment: .top, spacing: 8) {
            // Decorative — the title/year/genre text beside it says
            // everything it would. Not combined into one element with the
            // rest of the row because the Discogs link inside must stay
            // independently focusable/activatable for VoiceOver.
            artworkThumbnail(for: candidate)
                .accessibilityHidden(true)
            switch candidate {
            case .discogs(let release):
                // Two lines, not three: title stays alone (the one thing
                // that must be scannable at a glance), but year/genre/
                // format/label and the Discogs link — rarely used, and not
                // worth a whole line on its own — now share one quieter
                // metadata row, the link reduced to a small icon rather
                // than repeating "View on Discogs.com" per file/section.
                VStack(alignment: .leading, spacing: 2) {
                    // `release.title` is already "Artist - Release Title" —
                    // Discogs' own combined format (see `DiscogsRelease.title`'s
                    // doc comment) — same as `DiscogsResultRow` shows it.
                    Text(release.title).font(.caption).lineLimit(1).help(release.title)
                    HStack(spacing: 6) {
                        if let year = release.year, !year.isEmpty { Text(year) }
                        if !release.combinedGenre.isEmpty {
                            Text(release.combinedGenre).lineLimit(1).help(release.combinedGenre)
                        }
                        if !release.formattedFormat.isEmpty { Text(release.formattedFormat) }
                        if let label = release.label?.first { Text(label) }
                        if let url = release.releasePageURL {
                            Link(destination: url) {
                                Image(systemName: "arrow.up.right.square")
                            }
                            .help("View on Discogs.com")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
            case .musicBrainz(let recording):
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(recording.artistNames) — \(recording.title)").font(.caption).lineLimit(1)
                    HStack(spacing: 6) {
                        if let releaseTitle = recording.releaseTitle, !releaseTitle.isEmpty { Text(releaseTitle) }
                        if let year = recording.yearString { Text(year) }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
            }
        }
    }

    // MARK: - Comparison panes (Current | After Apply)

    /// One file's full field-by-field comparison, as one row's two halves —
    /// both panes iterate `AfterApplyPresentation.orderedComparisons` (the
    /// same fields, same order), so a given line is always the same field
    /// on both sides. Nothing here can drift vertically out of sync between
    /// the two panes: a field whose After Apply cell needs a second line
    /// (`.differsButKept`'s note) reserves that same line height on the
    /// Current side too, blank rather than omitted — see `fieldLine`.
    private func comparisonPanes(
        _ comparisons: [MatchComparison], file: AudioFile, candidate: LookupCandidate, providerLabel: String
    ) -> some View {
        let ordered = AfterApplyPresentation.orderedComparisons(comparisons, category: file.category)
        let presentations = ordered.map { AfterApplyPresentation.forField($0, providerLabel: providerLabel) }

        return twoPaneRow {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(ordered.indices, id: \.self) { index in
                    currentLine(comparison: ordered[index], presentation: presentations[index], file: file)
                }
            }
        } right: {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(ordered.indices, id: \.self) { index in
                    afterApplyLine(
                        comparison: ordered[index], presentation: presentations[index], file: file,
                        candidate: candidate, providerLabel: providerLabel)
                }
                // The genuine red flag in this window: Artist AND Album
                // both `.differsButKept` at once — see
                // `matchLooksLikelyWrong`'s doc comment. Anchored under the
                // After Apply pane, since it's a judgment about trusting
                // this match, not about what's on the file today.
                if Self.matchLooksLikelyWrong(comparisons) {
                    Label(Self.likelyWrongText, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private static let fieldLabelWidth: CGFloat = 78
    private static let inlineArtworkSize: CGFloat = 18

    /// One field's line — a fixed-width label plus whatever `primary`
    /// renders, with an optional second line reserved at the exact same
    /// height whether or not `secondLineText` is non-nil (an invisible
    /// placeholder keeps the row's height identical either way), so the
    /// Current and After Apply cells for one field always end at the same
    /// vertical position regardless of which one actually has a note.
    private func fieldLine<Content: View>(
        label: String, hasSecondLine: Bool, secondLineText: String?, @ViewBuilder primary: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: Self.fieldLabelWidth, alignment: .leading)
                primary()
            }
            if hasSecondLine {
                Text(secondLineText ?? " ")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .opacity(secondLineText == nil ? 0 : 1)
                    .padding(.leading, Self.fieldLabelWidth + 6)
                    .help(secondLineText ?? "")
            }
        }
    }

    /// The Current pane's own accessibility element is hidden — its value
    /// is folded into the After Apply line's single merged label instead
    /// (see `AfterApplyPresentation.accessibilityLabel`), so VoiceOver
    /// reads one stop per field, not two.
    private func currentLine(comparison: MatchComparison, presentation: AfterApplyPresentation, file: AudioFile) -> some View {
        fieldLine(
            label: comparison.field.rawValue, hasSecondLine: presentation.note != nil, secondLineText: nil
        ) {
            if comparison.field == .artwork {
                miniCurrentArtwork(file)
            } else {
                Text(comparison.currentValue ?? "–")
                    .font(.caption)
                    .foregroundStyle(comparison.currentValue == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(comparison.currentValue ?? "–")
            }
        }
        .accessibilityHidden(true)
    }

    private func afterApplyLine(
        comparison: MatchComparison, presentation: AfterApplyPresentation, file: AudioFile,
        candidate: LookupCandidate, providerLabel: String
    ) -> some View {
        fieldLine(
            label: comparison.field.rawValue, hasSecondLine: presentation.note != nil, secondLineText: presentation.note
        ) {
            HStack(spacing: 4) {
                if comparison.field == .artwork {
                    miniAfterApplyArtwork(file: file, candidate: candidate, presentation: presentation)
                } else {
                    Text(presentation.displayValue ?? "–")
                        .font(.caption)
                        .fontWeight(presentation.marker == .new ? .semibold : .regular)
                        .foregroundStyle(presentation.displayValue == nil
                                         ? AnyShapeStyle(.tertiary)
                                         : (presentation.marker == .new ? AnyShapeStyle(.blue) : AnyShapeStyle(.primary)))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(presentation.displayValue ?? "–")
                }
                markerIcon(presentation.marker)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AfterApplyPresentation.accessibilityLabel(
            field: comparison.field, comparison: comparison, presentation: presentation, providerLabel: providerLabel))
    }

    /// Never the only signal a field was added or confirmed — see
    /// `AfterApplyPresentation.Marker`'s doc comment — so this is always
    /// paired with a tint on the value itself (added) or nothing extra
    /// (confirmed reads fine from the checkmark alone, same convention as
    /// the rest of the app's found/agree badges) and, either way, with the
    /// spoken label on `afterApplyLine`'s accessibility element.
    @ViewBuilder
    private func markerIcon(_ marker: AfterApplyPresentation.Marker) -> some View {
        switch marker {
        case .new:
            Image(systemName: "arrow.down.circle.fill").font(.caption2).foregroundStyle(.blue)
        case .confirmed:
            Image(systemName: "checkmark.circle.fill").font(.caption2).foregroundStyle(.green)
        case .none:
            EmptyView()
        }
    }

    @ViewBuilder
    private func miniCurrentArtwork(_ file: AudioFile) -> some View {
        if let thumbnail = file.artworkThumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: Self.inlineArtworkSize, height: Self.inlineArtworkSize)
                .clipShape(RoundedRectangle(cornerRadius: 3))
        } else {
            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [2]))
                .frame(width: Self.inlineArtworkSize, height: Self.inlineArtworkSize)
        }
    }

    /// Artwork's After Apply cell doesn't go through `AfterApplyPresentation
    /// .displayValue` (a presence marker, not a real image) — it shows the
    /// incoming cover when it will fill, otherwise the file's own current
    /// artwork unchanged, exactly mirroring what `applySelected()` will
    /// actually leave the file with.
    @ViewBuilder
    private func miniAfterApplyArtwork(file: AudioFile, candidate: LookupCandidate, presentation: AfterApplyPresentation) -> some View {
        if presentation.marker == .new {
            artworkThumbnail(for: candidate, size: Self.inlineArtworkSize)
        } else {
            miniCurrentArtwork(file)
        }
    }

    static let likelyWrongText = "Artist and Album both differ — check this release"

    static let noChangesText = "No changes — every comparable field already agrees or has nothing to compare"

    /// The genuine red flag in this window: Artist AND Album both
    /// `.differsButKept` at once — the strongest available signal (short of
    /// actually opening "Correct…") that a match is the wrong release
    /// entirely, not just missing a field or two. A single differing field
    /// is the routine case every match can show without meaning anything is
    /// wrong; two core identity fields disagreeing simultaneously is not.
    /// Derived from `MatchComparisonBuilder`'s own outcome classification
    /// rather than a parallel notion of severity, and deliberately this
    /// narrow so it stays rare enough, across a real batch, to still mean
    /// something. A `static func` so it's directly testable.
    static func matchLooksLikelyWrong(_ comparisons: [MatchComparison]) -> Bool {
        let artistDiffers = comparisons.first { $0.field == .artist }?.outcome == .differsButKept
        let albumDiffers = comparisons.first { $0.field == .album }?.outcome == .differsButKept
        return artistDiffers && albumDiffers
    }

    @ViewBuilder
    private func outcomeLabel(for file: AudioFile) -> some View {
        switch outcomesByURL[file.url] {
        case nil:
            EmptyView()
        case .applied:
            Label("Applied", systemImage: "checkmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(.green)
        case .appliedWithoutBackup(let message):
            Label("Applied, but backup failed — \(message)", systemImage: "exclamationmark.triangle")
                .font(.caption2)
                .foregroundStyle(.orange)
        case .alreadyComplete:
            Label("Already complete", systemImage: "checkmark.circle")
                .font(.caption2)
                .foregroundStyle(.secondary)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(.red)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Text(Self.footerStatusText(
                isApplying: isApplying, selectedCount: selection.count, targetCount: targets.count,
                completed: applyCompletedCount, total: applyTotalCount))
                .font(.callout)
                .foregroundStyle(.secondary)
            if let applySummary {
                Text(applySummary).font(.caption).foregroundStyle(.secondary)
                    .transition(.opacity)
            }
            Spacer()
            if isApplying { ProgressView().controlSize(.small) }
            Button("Apply Selected Matches") { Task { await applySelected() } }
                .buttonStyle(.borderedProminent)
                .disabled(selection.isEmpty || isApplying)
        }
        .padding()
        // Appears once an apply run finishes — same reasoning as
        // RenameSheetView's footer.
        .consistentAnimation(applySummary)
    }

    /// While idle, the ordinary "N of M selected" count. While applying,
    /// `selection` is a frozen pre-apply snapshot but `targets` shrinks
    /// live as each file's `lookupResults` entry clears
    /// (`applyTagChanges`) — dividing the frozen numerator by the live,
    /// shrinking denominator could show more files selected than exist
    /// ("130 of 108 selected"). The selection is being consumed, not
    /// browsed, during a run, so this shows progress against the run's own
    /// fixed snapshot instead — always coherent by construction. A
    /// `static func` so it's testable without a live view — same pattern
    /// as `ContentView.fileMatches`.
    static func footerStatusText(
        isApplying: Bool, selectedCount: Int, targetCount: Int, completed: Int, total: Int
    ) -> String {
        guard isApplying else { return "\(selectedCount) of \(targetCount) selected" }
        return "Applying \(completed) of \(total)…"
    }

    // MARK: - Selection lifecycle

    /// Keeps `selection` matching "all selected by default" as `targets`
    /// changes underneath it — called on appear, whenever a correction
    /// sheet closes, and whenever the background batch lookup completes
    /// another file while this window is open. A file new since the last
    /// sync starts selected; a file the user already explicitly
    /// deselected stays that way; a file that's gone (applied, or
    /// resolved by a correction) is simply dropped.
    private func syncSelection() {
        let currentURLs = Set(targets.map(\.url))
        let newURLs = currentURLs.subtracting(knownTargetURLs)
        selection.formIntersection(currentURLs)
        selection.formUnion(newURLs)
        knownTargetURLs = currentURLs
    }

    private func applySelected() async {
        isApplying = true
        defer { isApplying = false }
        outcomesByURL = [:]

        let files = selectedTargets
        applyTotalCount = files.count
        applyCompletedCount = 0
        var appliedCount = 0
        var appliedWithoutBackupCount = 0
        var alreadyCompleteCount = 0
        var failedCount = 0

        for file in files {
            defer { applyCompletedCount += 1 }
            guard case .found(_, let candidate, let fillable) = scanner.lookupResults[file.url] else { continue }

            do {
                let changes = try await candidate.buildChanges(fillable: fillable, discogsToken: discogsToken)
                guard !changes.isEmpty else {
                    outcomesByURL[file.url] = .alreadyComplete
                    alreadyCompleteCount += 1
                    continue
                }

                let backupFailure = try await scanner.applyTagChanges(
                    changes, to: file, backupFirst: backupOriginalsBeforeWriting)
                if let backupFailure {
                    outcomesByURL[file.url] = .appliedWithoutBackup(backupFailure.localizedDescription)
                    appliedWithoutBackupCount += 1
                } else {
                    outcomesByURL[file.url] = .applied
                }
                appliedCount += 1
            } catch {
                outcomesByURL[file.url] = .failed(error.localizedDescription)
                failedCount += 1
            }
        }

        applySummary = Self.summaryText(
            applied: appliedCount, appliedWithoutBackup: appliedWithoutBackupCount,
            alreadyComplete: alreadyCompleteCount, failed: failedCount, total: files.count)

        syncSelection()
    }

    /// "Applied to X of Y file(s)" plus whichever of
    /// without-backup/already-complete/failed counts are nonzero — same
    /// wording pattern as `AlbumComparisonView.applySummaryText`.
    private static func summaryText(
        applied: Int, appliedWithoutBackup: Int, alreadyComplete: Int, failed: Int, total: Int
    ) -> String {
        var parts = ["Applied to \(applied) of \(pluralized(total, "file"))"]
        if appliedWithoutBackup > 0 { parts.append("\(appliedWithoutBackup) without a backup") }
        if alreadyComplete > 0 { parts.append("\(alreadyComplete) already complete") }
        if failed > 0 { parts.append("\(failed) failed") }
        return parts.joined(separator: ", ") + "."
    }
}
