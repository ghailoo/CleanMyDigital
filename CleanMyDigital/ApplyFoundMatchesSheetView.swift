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
/// Every file is a card whose field grid shows Field | Current → After
/// Apply on one line per field (`fieldRows`), under one pinned column
/// header. The After Apply column renders each field's
/// `AfterApplyPresentation` — never the raw match value — so a field only
/// looks changed when it will actually be written. A file with nothing to
/// write collapses to one "No changes" line.
///
/// The matched release's identity (cover, title, year, Discogs link) is
/// shown once per section for Albums/Compilations — every file there found
/// the same match — or once per card for Singles, whose files are
/// unrelated releases (see `FoundMatchGroup.albumGroup`).
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
    /// Opt-in: also rewrite an existing Album to drop "(CDM)"-style format
    /// suffixes — the one deliberate exception to "only fill empty fields".
    @AppStorage("removeAlbumFormatSuffixes") private var removeFormatSuffixes = false

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

    /// A match for a format this app can't write (.ogg today) is still worth
    /// showing — it says what the file is — but it can't be selected or
    /// applied, since every attempt would just fail in the apply run.
    static func isWritable(_ file: AudioFile) -> Bool {
        TagWriterRouter.canWrite(fileExtension: file.fileExtension)
    }

    private var writableTargets: [AudioFile] {
        targets.filter(Self.isWritable)
    }

    /// Recomputed live alongside `targets`, same reasoning.
    private var groups: [FoundMatchGroup] {
        FoundMatchPlanner.groups(targets: targets, albumGroups: AlbumCompletenessChecker.groups(for: scanner.files))
    }

    private var selectedTargets: [AudioFile] {
        writableTargets.filter { selection.contains($0.url) }
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

    // MARK: - Layout metrics

    /// One set of metrics shared by the pinned column header, section
    /// headers, and every file card, so the Field | Current | After Apply
    /// columns line up down the whole list without measuring anything.
    private enum Metrics {
        static let outerPadding: CGFloat = 16
        static let cardPadding: CGFloat = 14
        /// Field rows start under the file name, past the checkbox.
        static let contentIndent: CGFloat = 26
        static let labelWidth: CGFloat = 64
        static let arrowWidth: CGFloat = 16
        static let columnSpacing: CGFloat = 8
        static let artworkSize: CGFloat = 22
        static let coverSize: CGFloat = 44
        static let cardCorner: CGFloat = 10
        /// Deselected files stay readable but visibly won't be written.
        static let deselectedOpacity: Double = 0.45
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
                    ScrollView {
                        // Section headers pin on a material bar so cards scroll
                        // underneath them rather than behind an opaque strip.
                        LazyVStack(alignment: .leading, spacing: 10, pinnedViews: .sectionHeaders) {
                            ForEach(groups) { group in
                                Section {
                                    ForEach(group.files) { file in
                                        // Albums/Compilations share one release, shown
                                        // once in the section header; Singles files are
                                        // unrelated releases, so each card shows its own.
                                        fileCard(file, showsOwnMatchIdentity: !Self.sectionShowsSharedMatchIdentity(for: group))
                                    }
                                } header: {
                                    sectionHeader(group)
                                }
                            }
                        }
                        .padding(.bottom, Metrics.outerPadding)
                    }
                }
            }
        }
        .consistentAnimation(targets.isEmpty)
    }

    /// Pinned above the scroll view, so the columns stay named the whole
    /// way down. Built from `fieldColumns` with the same leading/trailing
    /// insets as a card's field rows, so it sits exactly over them.
    private var columnHeaders: some View {
        fieldColumns {
            Color.clear.frame(height: 1)
        } current: {
            Text("Current")
        } arrow: {
            EmptyView()
        } after: {
            Text("After Apply")
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.leading, Metrics.outerPadding + Metrics.cardPadding + Metrics.contentIndent)
        .padding(.trailing, Metrics.outerPadding + Metrics.cardPadding)
        .padding(.vertical, 7)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    /// The one column skeleton — label, Current, arrow, After Apply — shared
    /// by the pinned header and every field row.
    private func fieldColumns<FieldLabel: View, Current: View, Arrow: View, After: View>(
        alignment: VerticalAlignment = .firstTextBaseline,
        @ViewBuilder label: () -> FieldLabel,
        @ViewBuilder current: () -> Current,
        @ViewBuilder arrow: () -> Arrow,
        @ViewBuilder after: () -> After
    ) -> some View {
        HStack(alignment: alignment, spacing: Metrics.columnSpacing) {
            label().frame(width: Metrics.labelWidth, alignment: .leading)
            current().frame(maxWidth: .infinity, alignment: .leading)
            arrow().frame(width: Metrics.arrowWidth)
            after().frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Section header (folder identity + the shared match identity)

    private func sectionHeader(_ group: FoundMatchGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Toggle("", isOn: sectionSelectionBinding(for: group))
                    .labelsHidden()
                    .accessibilityLabel("Select all files in \(sectionTitle(for: group))")
                Image(systemName: group.albumGroup == nil ? "folder" : "opticaldisc")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(sectionTitle(for: group))
                        .font(.headline)
                        .lineLimit(1)
                    Text(Self.sectionSubtitle(for: group))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if let albumGroup = group.albumGroup {
                    Button("Re-match \(albumGroup.category == .compilations ? "Compilation" : "Album")…") {
                        albumLookupGroup = albumGroup
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityHint("Re-searches the whole \(albumGroup.category == .compilations ? "compilation" : "album") on Discogs")
                }
            }
            // Albums/Compilations only — every file in the folder found this
            // same release (see `representativeMatch`).
            if let match = representativeMatch(for: group) {
                matchIdentity(candidate: match.candidate)
                    .padding(.leading, Metrics.contentIndent)
            }
        }
        .padding(.horizontal, Metrics.outerPadding + Metrics.cardPadding)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
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
            get: {
                let selectable = group.files.filter(Self.isWritable)
                return !selectable.isEmpty && selectable.allSatisfy { selection.contains($0.url) }
            },
            set: { isOn in
                for file in group.files where Self.isWritable(file) {
                    if isOn { selection.insert(file.url) } else { selection.remove(file.url) }
                }
            }
        )
    }

    /// The match every file in `group` (that has one) resolved to, for the
    /// section header's shared identity block — just the first file's, on
    /// the assumption (true in practice: they were all searched from the
    /// same folder/album context) that a folder's files converge on one
    /// release. Each card's own "Correct…" still operates on that file.
    /// Returns nil for Singles, whose files are unrelated releases.
    private func representativeMatch(
        for group: FoundMatchGroup
    ) -> (provider: MetadataProvider, candidate: LookupCandidate, fillable: Set<MetadataField>)? {
        guard Self.sectionShowsSharedMatchIdentity(for: group) else { return nil }
        return group.files.lazy.compactMap { found(for: $0) }.first
    }

    /// True only for Albums/Compilations (`group.albumGroup != nil`), where
    /// every file in the folder genuinely resolved to the same release and
    /// the section header can show that match once for all of them. False
    /// for Singles, where each card shows its own match instead — one source
    /// of truth for both. A `static func` so it's directly testable.
    static func sectionShowsSharedMatchIdentity(for group: FoundMatchGroup) -> Bool {
        group.albumGroup != nil
    }

    // MARK: - File card

    /// This file's `.found` outcome, split into its three associated values.
    private func found(for file: AudioFile) -> (provider: MetadataProvider, candidate: LookupCandidate, fillable: Set<MetadataField>)? {
        guard case .found(let provider, let candidate, let fillable) = scanner.lookupResults[file.url] else { return nil }
        return (provider, candidate, fillable)
    }

    /// One file as a card: checkbox, name, a change-count badge and
    /// "Correct…" on top; the match identity (Singles only) and the field
    /// grid below. Deselected cards dim their body, not their checkbox, so
    /// it still reads as something to re-check.
    private func fileCard(_ file: AudioFile, showsOwnMatchIdentity: Bool) -> some View {
        let found = found(for: file)
        let comparisons: [MatchComparison] = found.map { found in
            let built = MatchComparisonBuilder.comparisons(file: file, candidate: found.candidate, fillable: found.fillable)
            return removeFormatSuffixes ? AfterApplyPresentation.applyingFormatSuffixRemoval(to: built) : built
        } ?? []
        let isSelected = selection.contains(file.url)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Toggle("", isOn: selectionBinding(for: file.url))
                    .labelsHidden()
                    .accessibilityLabel("Select \(file.fileName)")
                    .disabled(!Self.isWritable(file))
                    .help(Self.isWritable(file)
                          ? "" : "CleanMyDigital can't write tags to this format yet")

                VStack(alignment: .leading, spacing: 2) {
                    Text(file.fileName)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(file.fileName)
                    outcomeLabel(for: file)
                }

                Spacer(minLength: 8)

                changeBadge(comparisons)

                Button("Correct…") {
                    metadataLookupInitialProvider = found?.provider ?? .discogs
                    metadataLookupFile = file
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityHint("Re-searches this one file")
            }

            if let found {
                VStack(alignment: .leading, spacing: 10) {
                    if showsOwnMatchIdentity {
                        matchIdentity(candidate: found.candidate)
                    }
                    if AfterApplyPresentation.hasAnyChange(comparisons) {
                        fieldRows(comparisons, file: file, candidate: found.candidate, providerLabel: found.provider.rawValue)
                    } else {
                        Text(Self.noChangesText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.leading, Metrics.contentIndent)
                .opacity(isSelected ? 1 : Metrics.deselectedOpacity)
            }
        }
        .padding(Metrics.cardPadding)
        .background(.quinary, in: RoundedRectangle(cornerRadius: Metrics.cardCorner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.cardCorner, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
        }
        .consistentAnimation(isSelected)
        .padding(.horizontal, Metrics.outerPadding)
    }

    private func selectionBinding(for url: URL) -> Binding<Bool> {
        Binding(
            get: { selection.contains(url) },
            set: { isOn in
                if isOn { selection.insert(url) } else { selection.remove(url) }
            }
        )
    }

    /// The card's one-glance verdict: a quiet count of fields that will be
    /// written, or — replacing it, since it's the thing to act on — an
    /// orange "Check release" when `matchLooksLikelyWrong`.
    @ViewBuilder
    private func changeBadge(_ comparisons: [MatchComparison]) -> some View {
        if Self.matchLooksLikelyWrong(comparisons) {
            badge(Label("Check release", systemImage: "exclamationmark.triangle.fill"), tint: .orange)
        } else {
            let count = comparisons.filter { $0.outcome == .willFill }.count
            if count > 0 {
                badge(Text(pluralized(count, "change")), tint: .accentColor)
            }
        }
    }

    private func badge(_ content: some View, tint: Color) -> some View {
        content
            .font(.caption.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(tint.opacity(0.14), in: Capsule())
    }

    @ViewBuilder
    private func artworkThumbnail(for candidate: LookupCandidate, size: CGFloat) -> some View {
        let url: URL? = switch candidate {
        case .discogs(let release): release.coverImageURL ?? release.thumbURL
        case .musicBrainz(let recording): recording.coverArtURL
        }
        AsyncImage(url: url) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            Rectangle().fill(.quaternary)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size > 30 ? 6 : 4, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: size > 30 ? 6 : 4, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
        }
    }

    /// The match's own identity — "which record was found" — cover art, the
    /// release title, and one quiet metadata line (year · genre · format ·
    /// label) with a Discogs link. Each card's field grid then answers "how
    /// does it compare to what's already here."
    @ViewBuilder
    private func matchIdentity(candidate: LookupCandidate) -> some View {
        HStack(alignment: .center, spacing: 10) {
            // Decorative — the text beside it says everything it would. Not
            // combined with the text because the Discogs link must stay
            // independently focusable for VoiceOver.
            artworkThumbnail(for: candidate, size: Metrics.coverSize)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                switch candidate {
                case .discogs(let release):
                    // `release.title` is already Discogs' own "Artist - Release Title".
                    Text(release.title)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                        .help(release.title)
                    HStack(spacing: 6) {
                        let details = [release.year, release.combinedGenre, release.formattedFormat, release.label?.first]
                            .compactMap { $0 }
                            .filter { !$0.isEmpty }
                            .joined(separator: " · ")
                        Text(details).lineLimit(1).help(details)
                        if let url = release.releasePageURL {
                            Link(destination: url) {
                                Image(systemName: "arrow.up.right.square")
                            }
                            .help("View on Discogs.com")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                case .musicBrainz(let recording):
                    Text("\(recording.artistNames) — \(recording.title)")
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    Text([recording.releaseTitle, recording.yearString].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    // MARK: - Field grid (Current → After Apply)

    /// Every field, same order for every file
    /// (`AfterApplyPresentation.orderedComparisons`), one row each: the label
    /// once, then Current and After Apply side by side. Only rows that will
    /// actually change get an arrow, primary-weight text, and a tinted
    /// highlight; everything that stays as-is recedes to secondary, so the
    /// eye lands on what Apply will write.
    private func fieldRows(
        _ comparisons: [MatchComparison], file: AudioFile, candidate: LookupCandidate, providerLabel: String
    ) -> some View {
        let ordered = AfterApplyPresentation.orderedComparisons(comparisons, category: file.category)
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(ordered, id: \.field) { comparison in
                fieldRow(
                    comparison, presentation: .forField(comparison, providerLabel: providerLabel),
                    file: file, candidate: candidate, providerLabel: providerLabel)
            }
            // Also flagged by the header badge; this line says why.
            if Self.matchLooksLikelyWrong(comparisons) {
                Label(Self.likelyWrongText, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.top, 2)
            }
        }
    }

    /// One field as a single VoiceOver stop spanning both columns (see
    /// `AfterApplyPresentation.accessibilityLabel`) — the "added" signal is
    /// never carried by the tint alone.
    private func fieldRow(
        _ comparison: MatchComparison, presentation: AfterApplyPresentation, file: AudioFile,
        candidate: LookupCandidate, providerLabel: String
    ) -> some View {
        let willChange = presentation.marker == .new
        let isArtwork = comparison.field == .artwork

        return fieldColumns(alignment: isArtwork ? .center : .firstTextBaseline) {
            Text(comparison.field.rawValue)
                .font(.caption)
                .foregroundStyle(.secondary)
        } current: {
            if isArtwork {
                currentArtwork(file)
            } else {
                valueText(comparison.currentValue, highlighted: false, recedes: !willChange)
            }
        } arrow: {
            if willChange {
                Image(systemName: "arrow.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        } after: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    if isArtwork {
                        if willChange {
                            artworkThumbnail(for: candidate, size: Metrics.artworkSize)
                        } else {
                            currentArtwork(file)
                        }
                    } else {
                        valueText(presentation.displayValue, highlighted: willChange, recedes: !willChange)
                    }
                    if presentation.marker == .confirmed {
                        Image(systemName: "checkmark")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                if let note = presentation.note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .help(note)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AfterApplyPresentation.accessibilityLabel(
            field: comparison.field, comparison: comparison, presentation: presentation, providerLabel: providerLabel))
    }

    /// A field value: an em dash when empty, secondary when it isn't
    /// changing, and — for a value Apply will write — primary, medium
    /// weight, on a soft accent highlight (outdented by its own padding so
    /// the text still aligns with the column).
    private func valueText(_ value: String?, highlighted: Bool, recedes: Bool) -> some View {
        let style: AnyShapeStyle = value == nil ? AnyShapeStyle(.tertiary)
            : recedes ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary)
        return Text(value ?? "—")
            .font(.callout.weight(highlighted ? .medium : .regular))
            .foregroundStyle(style)
            .lineLimit(1)
            .truncationMode(.tail)
            .help(value ?? "")
            .padding(.horizontal, highlighted ? 5 : 0)
            .padding(.vertical, highlighted ? 1 : 0)
            .background {
                if highlighted {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.accentColor.opacity(0.15))
                }
            }
            .padding(.leading, highlighted ? -5 : 0)
    }

    @ViewBuilder
    private func currentArtwork(_ file: AudioFile) -> some View {
        if let thumbnail = file.artworkThumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: Metrics.artworkSize, height: Metrics.artworkSize)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(.tertiary, style: StrokeStyle(lineWidth: 1, dash: [2]))
                .frame(width: Metrics.artworkSize, height: Metrics.artworkSize)
        }
    }

    static let likelyWrongText = "Artist and Album both differ — check this release"

    static let noChangesText = "No changes — every comparable field already agrees or has nothing to compare"

    /// The genuine red flag in this window: Artist AND Album both
    /// `.differsButKept` at once — the strongest available signal (short of
    /// actually opening "Correct…") that a match is the wrong release
    /// entirely, not just missing a field or two. A single differing field
    /// is routine; two core identity fields disagreeing simultaneously is
    /// not. Deliberately this narrow so it stays rare enough to mean
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
                .font(.caption)
                .foregroundStyle(.green)
        case .appliedWithoutBackup(let message):
            Label("Applied, but backup failed — \(message)", systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
        case .alreadyComplete:
            Label("Already complete", systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Text(Self.footerStatusText(
                isApplying: isApplying, selectedCount: selection.count, targetCount: writableTargets.count,
                completed: applyCompletedCount, total: applyTotalCount))
                .font(.callout)
                .foregroundStyle(.secondary)
            if let applySummary {
                Text(applySummary).font(.caption).foregroundStyle(.secondary)
                    .transition(.opacity)
            }
            Spacer()
            Toggle("Remove format suffixes from Album", isOn: $removeFormatSuffixes)
                .toggleStyle(.checkbox)
                .help("Also rewrites existing Album tags to drop markers like \"(CDM)\", \"(EP)\" or \" - Single\". Each change shows in the list before you apply.")
                .disabled(isApplying)
            if isApplying { ProgressView().controlSize(.small) }
            Button("Apply Selected Matches") { Task { await applySelected() } }
                .accessibilityHint("Writes the selected matches' fields into the files' tags")
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(selection.isEmpty || isApplying)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
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
        let currentURLs = Set(writableTargets.map(\.url))
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
                var changes = try await candidate.buildChanges(fillable: fillable, discogsToken: discogsToken)
                if removeFormatSuffixes, changes.album == nil,
                   let cleaned = MetadataQuery.strippingFormatSuffix(from: file.album) {
                    changes.album = cleaned
                    changes.replacing = [.album]
                }
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
