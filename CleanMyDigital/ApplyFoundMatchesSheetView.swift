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
/// The release/recording identity (title, year, genre, format, label,
/// cover, provider link) is shown once per *section* for Albums/
/// Compilations, not once per file — every file in that kind of folder
/// genuinely found the same match, so repeating it per row would just
/// crowd out the one thing that actually varies file to file: how each
/// file's own tags compare to it. Singles are the opposite case: a Singles
/// folder's files are unrelated releases by definition (see
/// `FoundMatchGroup.albumGroup`'s doc comment), so each file shows its own
/// match identity on its own row instead — see `fileRow`. Either way, the
/// per-file comparison itself is a disclosure — collapsed by default (a
/// batch can hold 30+ files, so a full field table per row is over 400
/// lines before anyone expands anything) to one concrete line naming only
/// the fields that will actually be written, expandable via a chevron on
/// the file row to the full field-by-field table with real before/after
/// values — see `collapsedSummary`.
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
    /// Which files' full before/after comparison table is expanded — all
    /// collapsed by default, since a batch can hold 30+ files and even one
    /// concrete line per file (let alone a full field table) would be over
    /// 400 lines before anyone expands anything at that scale. The
    /// collapsed summary (see `collapsedSummary`) names exactly which
    /// fields will actually be written, so it's still concrete, not just a
    /// verdict — expanding is for the real before/after values, or when a
    /// match looks like it might be the wrong release entirely.
    ///
    /// Rendered as an explicit chevron `Button` on the file row itself, not
    /// a `DisclosureGroup` — a `DisclosureGroup`'s built-in triangle reads
    /// as basically invisible next to a wide multi-line custom label inside
    /// a `List` row, which made the whole affordance easy to miss entirely.
    /// Same underlying per-file expand/collapse state and behavior either
    /// way; only the visual affordance changed, to make it unmistakable —
    /// and to sit beside the file's own name rather than beside whichever
    /// comparison field happened to render first, which used to read as
    /// controlling that one field instead of the whole file.
    @State private var expandedFileURLs: Set<URL> = []

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
        // .wide — the per-file disclosure content is the tallest of any
        // auxiliary window's.
        SheetWindowContainer(
            subtitle: Self.headerSubtitle(groups: groups),
            windowID: "apply-found-matches",
            size: .wide
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
        .consistentAnimation(targets.isEmpty)
    }

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
            // here rather than repeated on every row below. Only true for
            // Albums/Compilations; `representativeMatch` returns nil for a
            // Singles folder, where each file's row shows its own match
            // instead (see `fileRow`).
            if let match = representativeMatch(for: group) {
                matchIdentity(candidate: match.candidate)
                    .padding(.leading, 26)
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
    /// table, the disclosure summary, and the "Correct…" button.
    private func found(for file: AudioFile) -> (provider: MetadataProvider, candidate: LookupCandidate, fillable: Set<MetadataField>)? {
        guard case .found(let provider, let candidate, let fillable) = scanner.lookupResults[file.url] else { return nil }
        return (provider, candidate, fillable)
    }

    /// `showsOwnMatchIdentity` is true for a Singles folder (`albumGroup ==
    /// nil`) — unlike Albums/Compilations, its files are unrelated releases
    /// by definition, so there's no shared identity in the section header
    /// above (see `representativeMatch`) and this file's own match is shown
    /// right here instead.
    ///
    /// The expand/collapse chevron lives in the top `HStack`, alongside the
    /// selection `Toggle` and filename — not indented in with the
    /// comparison content below it, where it used to sit beside the first
    /// field line and read as controlling that field rather than the whole
    /// file. See `expandedFileURLs`'s doc comment for why it's a plain
    /// `Button` with its own chevron rather than a `DisclosureGroup`.
    private func fileRow(_ file: AudioFile, showsOwnMatchIdentity: Bool) -> some View {
        let found = found(for: file)
        let isExpanded = expandedFileURLs.contains(file.url)

        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 10) {
                Toggle("", isOn: selectionBinding(for: file.url))
                    .labelsHidden()
                    .accessibilityLabel("Select \(file.fileName)")

                if found != nil {
                    Button {
                        if isExpanded { expandedFileURLs.remove(file.url) } else { expandedFileURLs.insert(file.url) }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 10)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                    .accessibilityLabel(isExpanded ? "Collapse details" : "Expand details")
                }

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
                    matchIdentity(candidate: found.candidate)
                        .padding(.leading, 26)
                }

                let comparisons = MatchComparisonBuilder.comparisons(
                    file: file, candidate: found.candidate, fillable: found.fillable)

                collapsedSummary(comparisons, providerLabel: found.provider.rawValue)
                    .padding(.leading, 26)

                if isExpanded {
                    comparisonTable(comparisons, file: file, candidate: found.candidate, provider: found.provider)
                        .padding(.leading, 26)
                        .transition(.opacity)
                }
            }
        }
        .padding(.vertical, 3)
        .consistentAnimation(isExpanded)
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
    /// "which record was found," while each file's own disclosure answers
    /// "how does it compare to what's already here."
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

    // MARK: - Comparison summary (collapsed) and table (expanded)

    /// The collapsed state for a file — up to three lines, each naming real
    /// values, never just field names or bare verdicts (an earlier version
    /// of this view showed only field names and verdicts with no real
    /// values anywhere, which is the complaint the field-by-field
    /// comparison exists to fix):
    ///
    /// - **Fills** — fields that are empty on the file and have a value in
    ///   the match (`.willFill`). There is no "before" for these — the
    ///   current value is always nothing — so this shows only the incoming
    ///   value, never an arrow from an empty left-hand side.
    /// - **Keeps** — fields that already have a value on the file *and* a
    ///   different one in the match (`.differsButKept`). This is the one
    ///   outcome where both sides matter (nothing is written, but a human
    ///   should see what disagreed), so it's the only line that shows both.
    /// - A **risky-match** line when `matchLooksLikelyWrong` — the flag has
    ///   to say in words why it's flagged, not just show a triangle next to
    ///   text that reads identically to an unflagged row.
    ///
    /// Agreeing and no-data fields are left entirely for the expanded
    /// table, where their real values are still shown — naming them here
    /// too was what made a single file take five lines, which at 85 files
    /// was over 400 lines of scrolling before anyone expanded anything.
    /// When neither Fills nor Keeps has anything, a single "No changes"
    /// line takes their place.
    @ViewBuilder
    private func collapsedSummary(_ comparisons: [MatchComparison], providerLabel: String) -> some View {
        let fills = comparisons.filter { $0.outcome == .willFill }
        let keeps = comparisons.filter { $0.outcome == .differsButKept }
        let fillsText = Self.fillsLineText(fills)
        let keepsText = Self.keepsLineText(keeps, providerLabel: providerLabel)

        VStack(alignment: .leading, spacing: 2) {
            if let fillsText {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down.circle.fill").foregroundStyle(.blue).font(.caption2)
                    Text("Fills").font(.caption.weight(.semibold))
                    Text(fillsText).font(.caption).lineLimit(1).help(fillsText)
                }
                .accessibilityElement(children: .combine)
            }
            if let keepsText {
                HStack(spacing: 4) {
                    Text("Keeps").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(keepsText).font(.caption).foregroundStyle(.secondary).lineLimit(1).help(keepsText)
                }
                .accessibilityElement(children: .combine)
            }
            if Self.matchLooksLikelyWrong(comparisons) {
                Label(Self.likelyWrongText, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if fillsText == nil, keepsText == nil {
                Text(Self.noChangesText).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// "Fills   Year 1997 · Genre Electronic, Garage House · Artwork ✓" —
    /// the incoming value only, no arrow and no empty left-hand side, since
    /// `.willFill` means the file's field is empty by definition (see
    /// `MatchComparison.Outcome.willFill`'s doc comment). Artwork has no
    /// meaningful "value" to print (its comparison values are just
    /// presence markers — see `MatchComparisonBuilder.artworkComparison`),
    /// so it gets a checkmark instead. `nil` when there's nothing to fill,
    /// so the caller can tell "no line" apart from "line with no fields."
    static func fillsLineText(_ fills: [MatchComparison]) -> String? {
        guard !fills.isEmpty else { return nil }
        return fills.map { comparison in
            comparison.field == .artwork ? "Artwork ✓" : "\(comparison.field.rawValue) \(comparison.matchValue ?? "–")"
        }.joined(separator: " · ")
    }

    /// "Artist "Byron Stingily" · Discogs says "Byron Stingily Featuring
    /// Leee John"" — the only collapsed line with two sides, since
    /// `.differsButKept` is the only outcome where both the file's current
    /// value and the match's differ and neither is nothing (see
    /// `MatchComparison.Outcome.differsButKept`'s doc comment). Several
    /// differing fields join on each side in the same order, so "Artist …,
    /// Album …" on the left lines up with "…, …" on the right. `nil` when
    /// nothing differs, matching `fillsLineText`.
    static func keepsLineText(_ keeps: [MatchComparison], providerLabel: String) -> String? {
        guard !keeps.isEmpty else { return nil }
        let current = keeps.map { "\($0.field.rawValue) \"\($0.currentValue ?? "")\"" }.joined(separator: ", ")
        let matched = keeps.map { "\"\($0.matchValue ?? "")\"" }.joined(separator: ", ")
        return "\(current) · \(providerLabel) says \(matched)"
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

    private func comparisonTable(
        _ comparisons: [MatchComparison], file: AudioFile, candidate: LookupCandidate, provider: MetadataProvider
    ) -> some View {
        // Changed fields first (what someone opened this for), agreements
        // after (confirmation, condensed), no-data fields last (context
        // only — nothing to act on or compare).
        let ordered = comparisons.sorted { lhs, rhs in
            priority(lhs.outcome) < priority(rhs.outcome)
        }
        return VStack(spacing: 0) {
            ForEach(ordered) { comparison in
                if comparison.field == .artwork {
                    artworkComparisonRow(comparison, file: file, candidate: candidate, providerLabel: provider.rawValue)
                } else {
                    MetadataComparisonRow(
                        fieldLabel: comparison.field.rawValue, currentValue: comparison.currentValue,
                        matchColumnLabel: provider.rawValue, matchValue: comparison.matchValue,
                        matchPlaceholder: comparison.unavailableNote, isCondensed: comparison.outcome == .agrees
                    ) {
                        outcomeIndicator(comparison.outcome)
                    }
                }
                if comparison.id != ordered.last?.id { Divider() }
            }
        }
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
        .padding(.top, 4)
    }

    private func priority(_ outcome: MatchComparison.Outcome) -> Int {
        switch outcome {
        case .willFill: 0
        case .differsButKept: 1
        case .agrees: 2
        case .noMatchData: 3
        }
    }

    /// Artwork can't go through `MetadataComparisonRow`'s plain-text
    /// columns — it needs real thumbnails, not the presence placeholder
    /// `MatchComparisonBuilder` uses internally for its outcome
    /// classification — so this renders them directly from `file`/
    /// `candidate` while still reusing `comparison.outcome` for the
    /// trailing indicator. Each side always shows something — a real
    /// thumbnail or an explicit "empty" placeholder — never a bare dash,
    /// so it's never ambiguous which image (if either) is which.
    private func artworkComparisonRow(
        _ comparison: MatchComparison, file: AudioFile, candidate: LookupCandidate, providerLabel: String
    ) -> some View {
        let matchURL: URL? = switch candidate {
        case .discogs(let release): release.coverImageURL ?? release.thumbURL
        case .musicBrainz(let recording): recording.coverArtURL
        }
        return HStack(alignment: .top) {
            Text(MetadataField.artwork.rawValue)
                .font(.subheadline.weight(.medium))
                .frame(width: 100, alignment: .leading)
            artworkSlot(caption: "Current", isEmpty: file.artworkThumbnail == nil) {
                if let thumbnail = file.artworkThumbnail {
                    Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fit)
                }
            }
            artworkSlot(caption: providerLabel, isEmpty: matchURL == nil) {
                if let matchURL {
                    AsyncImage(url: matchURL) { image in
                        image.resizable().aspectRatio(contentMode: .fit)
                    } placeholder: {
                        ProgressView().controlSize(.small)
                    }
                }
            }
            outcomeIndicator(comparison.outcome)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    /// One labeled artwork slot — the image `content` builds when
    /// `isEmpty` is false, or an explicit dashed "None" placeholder at the
    /// same size when it's true, so an empty slot always reads as
    /// "confirmed empty" rather than "loading" or "missing by accident."
    /// `isEmpty` is passed explicitly rather than inferred from `content`,
    /// since a `@ViewBuilder if/else` never actually produces `EmptyView`
    /// itself — it produces `_ConditionalContent`, which can't be checked
    /// against a concrete type this way.
    private func artworkSlot<Content: View>(
        caption: String, isEmpty: Bool, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color.secondary.opacity(0.35),
                                  style: StrokeStyle(lineWidth: 1, dash: isEmpty ? [3] : []))
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.gray.opacity(isEmpty ? 0.05 : 0)))
                if isEmpty {
                    Text("None").font(.system(size: 8)).foregroundStyle(.tertiary)
                } else {
                    content()
                }
            }
            .frame(width: 32, height: 32)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            Text(caption).font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(caption): \(isEmpty ? "no artwork" : "artwork present")")
    }

    private func outcomeIndicator(_ outcome: MatchComparison.Outcome) -> some View {
        Image(systemName: outcomeSymbol(outcome))
            .foregroundStyle(outcomeColor(outcome))
            .help(outcomeWord(outcome))
            .accessibilityLabel(outcomeWord(outcome))
    }

    private func outcomeSymbol(_ outcome: MatchComparison.Outcome) -> String {
        switch outcome {
        case .willFill: "arrow.down.circle.fill"
        case .agrees: "checkmark.circle.fill"
        case .differsButKept: "exclamationmark.circle.fill"
        case .noMatchData: "minus.circle"
        }
    }

    /// `.differsButKept` deliberately does NOT get a warning colour —
    /// nothing is written, so a field merely differing from the match is
    /// the routine, harmless case every match can show; orange here read as
    /// alarming for something that's actually inert. The one place this
    /// window does flag genuine risk is `matchLooksLikelyWrong`'s red
    /// triangle in `collapsedSummary`, derived from two fields disagreeing
    /// at once rather than any single field's outcome.
    private func outcomeColor(_ outcome: MatchComparison.Outcome) -> Color {
        switch outcome {
        case .willFill: .blue
        case .agrees: .green
        case .differsButKept: .secondary
        case .noMatchData: .secondary
        }
    }

    private func outcomeWord(_ outcome: MatchComparison.Outcome) -> String {
        switch outcome {
        case .willFill: "Will fill"
        case .agrees: "Agrees"
        case .differsButKept: "Differs, kept"
        case .noMatchData: "No data"
        }
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
