//
//  ContentView.swift
//  CleanMyDigital
//
//  Created by Ghailen Ben Othman on 09/07/2026.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers



















struct ContentView: View {
    enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case issues = "Missing Metadata"
        case noMetadata = "No Metadata at All"
        case complete = "Complete"
        case found = "Found"

        var id: String { rawValue }
    }

    /// One entry in the merged summary/filter row (see `summaryBar`) — a
    /// count paired with the `Filter` case selecting it produces, plus the
    /// label and severity colour the old separate summary bar used. Pulled
    /// out as a pure function of `files`/`lookupResults` (rather than a
    /// computed property reading `scanner` directly) so the mapping from
    /// filter to label/color/count can be unit tested without a live
    /// `LibraryScanner`.
    struct FilterStat: Identifiable {
        let filter: Filter
        let label: String
        let color: Color
        let count: Int
        var id: Filter { filter }
    }

    static func filterStats(files: [AudioFile], lookupResults: [URL: LookupOutcome]) -> [FilterStat] {
        [
            FilterStat(filter: .all, label: "Total", color: .secondary,
                       count: files.count),
            FilterStat(filter: .issues, label: "With issues", color: .orange,
                       count: files.count(where: \.hasIssues)),
            FilterStat(filter: .noMetadata, label: "No metadata", color: .red,
                       count: files.count(where: \.hasNoMetadata)),
            FilterStat(filter: .complete, label: "Complete", color: .green,
                       count: files.count { !$0.hasIssues }),
            FilterStat(filter: .found, label: "Found", color: .blue,
                       count: files.count { lookupResults[$0.url]?.isFound == true }),
        ]
    }

    /// The predicate behind each `Filter` case — shared by `filteredFiles`
    /// and (indirectly, via `filterStats`' counts) the merged summary/filter
    /// row, so the two can never disagree about what a given filter means.
    static func fileMatches(_ file: AudioFile, filter: Filter, lookupResults: [URL: LookupOutcome]) -> Bool {
        switch filter {
        case .all: return true
        case .issues: return file.hasIssues
        case .noMetadata: return file.hasNoMetadata
        case .complete: return !file.hasIssues
        case .found: return lookupResults[file.url]?.isFound == true
        }
    }

    /// The Lookup and Cutoff table columns only ever hold data once "Find
    /// All Metadata" / "Check for Transcodes" has actually run — before
    /// that they're just reserved blank space (Lookup empty, Cutoff four
    /// em-dashes) taking room from every other column. Pulled out as pure
    /// functions of the scanner's result dictionaries so the
    /// column-visibility rule is unit-testable independent of the `Table`
    /// view itself.
    static func showsLookupColumn(lookupResults: [URL: LookupOutcome]) -> Bool {
        !lookupResults.isEmpty
    }

    static func showsCutoffColumn(spectralResults: [URL: SpectralCutoffOutcome]) -> Bool {
        !spectralResults.isEmpty
    }

    let scanner: LibraryScanner

    @Environment(\.openWindow) private var openWindow
    @State private var showFolderPicker = false
    @State private var showCSVExporter = false
    @State private var csvDocument = CSVDocument(text: "")
    @State private var selectedCategory: LibraryCategory = .albums
    @State private var showCategoryPrompt = true
    @State private var filter: Filter = .issues
    @State private var searchText = ""
    @State private var sortOrder = [KeyPathComparator(\AudioFile.fileName)]
    @State private var selection: Set<AudioFile.ID> = []
    @State private var metadataLookupFile: AudioFile?
    @State private var metadataLookupInitialProvider: MetadataProvider = .discogs
    @AppStorage("discogsToken") private var discogsToken = ""
    @AppStorage("musicBrainzContact") private var musicBrainzContact = ""

    private var filteredFiles: [AudioFile] {
        var result = scanner.files
        result = result.filter { Self.fileMatches($0, filter: filter, lookupResults: scanner.lookupResults) }
        if !searchText.isEmpty {
            result = result.filter {
                $0.fileName.localizedCaseInsensitiveContains(searchText)
                    || ($0.title?.localizedCaseInsensitiveContains(searchText) ?? false)
                    || ($0.artist?.localizedCaseInsensitiveContains(searchText) ?? false)
                    || ($0.album?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
        return result.sorted(using: sortOrder)
    }

    var body: some View {
        Group {
            switch scanner.state {
            case .idle:
                emptyState
            case .enumerating, .scanning:
                scanningState
            case .finished:
                resultsTable
            }
        }
        // Cross-fades idle → scanning → results instead of a hard cut,
        // without animating the table's own rows once we're in it.
        .consistentAnimation(scanner.state)
        .frame(minWidth: 800, minHeight: 500)
        .toolbar { toolbarContent }
        .labelStyle(.titleAndIcon)
        .searchable(text: $searchText, prompt: "Search file, title, artist, album")
        // Singles are commonly filed one folder per artist, so several can
        // be scanned as one library rather than scanning their shared
        // parent and walking everything else under it. Albums and
        // Compilations stay single-folder: both derive meaning from the
        // scanned folder's own structure (artist folders, one folder per
        // release), which several unrelated roots would muddle.
        .fileImporter(isPresented: $showFolderPicker,
                      allowedContentTypes: [.folder],
                      allowsMultipleSelection: selectedCategory == .singles) { result in
            if case .success(let urls) = result, !urls.isEmpty {
                Task { await scanner.scan(folders: urls, category: selectedCategory) }
            }
        }
        .fileExporter(isPresented: $showCSVExporter,
                      document: csvDocument,
                      contentType: .commaSeparatedText,
                      defaultFilename: "CleanMyDigital Report") { _ in }
        .sheet(item: $metadataLookupFile) { file in
            MetadataLookupView(file: file, scanner: scanner, initialProvider: metadataLookupInitialProvider)
        }
        .sheet(isPresented: $showCategoryPrompt) {
            categoryPromptSheet
        }
        .onChange(of: selectedCategory) {
            // Guarded to the scanner actually having something to clear —
            // `categoryPromptSheet` also assigns `selectedCategory` (at
            // launch, before any scan), and without this guard the two
            // categories wouldn't behave consistently there: the default
            // is already `.albums`, so picking Albums at launch wouldn't
            // fire this change at all while picking Singles would. At
            // launch the scanner is idle and the empty state already
            // shows a prominent "Choose Folder…" button, so there's
            // nothing to lose either way.
            guard scanner.state != .idle else { return }
            scanner.reset()
            showFolderPicker = true
        }
        .navigationTitle("CleanMyDigital")
        .navigationSubtitle(navigationSubtitleText)
    }

    /// One folder shows its path; several show a count instead, since
    /// concatenating a handful of full paths into a window subtitle is
    /// unreadable. The folder list itself stays visible in the results.
    private var navigationSubtitleText: String {
        let folders = scanner.scannedFolders
        guard !folders.isEmpty else { return "" }
        let location = folders.count == 1
            ? folders[0].path(percentEncoded: false)
            : "\(folders.count) folders"
        guard let category = scanner.category else { return location }
        return "\(location) — \(category.rawValue)"
    }

    // MARK: - States

    /// Forces an explicit Singles/Albums/Compilations choice at launch,
    /// before the user can pick a folder — each category uses different
    /// scan rules and different Discogs/MusicBrainz search behavior, so
    /// silently defaulting to one was easy to miss.
    private var categoryPromptSheet: some View {
        VStack(spacing: 28) {
            VStack(spacing: 10) {
                Image(systemName: "waveform.badge.magnifyingglass")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
                Text("What are you scanning?")
                    .font(.title2.weight(.semibold))
                Text("Singles, Albums, and Compilations are checked against different rules and searched differently on Discogs and MusicBrainz.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 340)
            }

            VStack(spacing: 8) {
                ForEach(LibraryCategory.allCases) { category in
                    CategoryPromptOption(
                        title: category.rawValue,
                        systemImage: categoryPromptIcon(category),
                        description: categoryPromptDescription(category)
                    ) {
                        selectedCategory = category
                        showCategoryPrompt = false
                    }
                }
            }
            .frame(maxWidth: 380)
        }
        .padding(36)
        .frame(minWidth: 440, minHeight: 400)
        .interactiveDismissDisabled()
    }

    private func categoryPromptIcon(_ category: LibraryCategory) -> String {
        switch category {
        case .singles: "music.note"
        case .albums: "opticaldisc"
        case .compilations: "rectangle.stack"
        }
    }

    private func categoryPromptDescription(_ category: LibraryCategory) -> String {
        switch category {
        case .singles:
            "Individual tracks and maxi-singles. No track-number or artist-folder checks."
        case .albums:
            "Files organized as ArtistName/AlbumName/Track. Artist tag is checked against its folder."
        case .compilations:
            "Various-artist collections. No artist-folder check."
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Scan Your Audio Library", systemImage: "waveform.badge.magnifyingglass")
        } description: {
            Text("Choose a folder and CleanMyDigital will read every audio file's tags and flag the ones missing title, artist, album, or artwork.")
        } actions: {
            Button("Choose Folder…") { showFolderPicker = true }
                .buttonStyle(.borderedProminent)
        }
    }

    private var scanningState: some View {
        VStack(spacing: 12) {
            if scanner.state == .enumerating {
                ProgressView("Finding audio files…")
            } else {
                ProgressView(value: scanner.progress) {
                    Text("Reading metadata…")
                } currentValueLabel: {
                    Text("\(scanner.scannedCount) of \(scanner.totalCount)")
                }
                .frame(maxWidth: 360)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var resultsTable: some View {
        VStack(spacing: 0) {
            if let example = scanner.misrootedArtistFolderExample {
                Group {
                    misrootedFolderWarningBanner(example: example)
                    Divider()
                }
                .transition(.opacity)
            } else if scanner.artistOverrideAutoDetected, let artist = scanner.artistOverride {
                Group {
                    autoDetectedArtistFolderBanner(artist: artist)
                    Divider()
                }
                .transition(.opacity)
            }
            summaryBar
            Divider()
            if filteredFiles.isEmpty {
                ContentUnavailableView(
                    scanner.files.isEmpty ? "No audio files found" : "Nothing matches this filter",
                    systemImage: "music.note.list"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                table
            }
        }
        // The banner appears/disappears as a side effect of a rescan
        // completing, shifting every row below it — an instant pop reads as
        // a layout glitch, a quick fade reads as "something just finished".
        .consistentAnimation(scanner.misrootedArtistFolderExample)
        .consistentAnimation(scanner.artistOverrideAutoDetected)
    }

    /// Warns when the scanned folder looks like it was rooted one level too
    /// deep — e.g. `/Volumes/Albums/2Pac/` (an artist's own album folder)
    /// scanned directly instead of its parent `/Volumes/Albums/`. Recomputed
    /// live from `scanner.misrootedArtistFolderExample`, so it disappears on
    /// its own once a correct rescan replaces `scanner.files` — no dismiss
    /// button needed. The "Treat as the artist" button is the one-click fix
    /// for exactly this scenario: it re-scans the same folder with
    /// `artistOverride` set to the folder's own name, which also makes this
    /// banner stop showing (`possibleArtistFolderMismatch` reads false once
    /// an override is set).
    private func misrootedFolderWarningBanner(example: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 6) {
                Text("This scan's expected artist folder (\"\(example)\") looks like an album name, not an artist name — you may have scanned an album folder directly instead of its parent. Try rescanning one level up.")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                if let folder = scanner.scannedFolder {
                    Button("Treat \"\(folder.lastPathComponent)\" as the Artist") {
                        treatScannedFolderAsArtist(folder)
                    }
                    .controlSize(.small)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.yellow.opacity(0.15))
    }

    /// Passive, low-key confirmation that `scan(folder:category:artistOverride:)`
    /// detected this scan as "one artist's own folder, containing albums
    /// directly" on its own and already applied the artist-folder override
    /// — see `LibraryScanner.artistOverrideAutoDetected`. Deliberately
    /// quieter than `misrootedFolderWarningBanner`: this is confirming
    /// something already handled, not asking the user to do anything, so no
    /// yellow background, no warning icon, no button — just a note the user
    /// can glance at or ignore. Mutually exclusive with that banner: once
    /// detection fires, `possibleArtistFolderMismatch` reads false, so only
    /// one of the two ever shows for a given scan.
    private func autoDetectedArtistFolderBanner(artist: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(.secondary)
                .imageScale(.small)
            Text("Detected \"\(artist)\" as the artist for this scan.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func treatScannedFolderAsArtist(_ folder: URL) {
        let category = scanner.category ?? selectedCategory
        Task {
            await scanner.scan(folder: folder, category: category, artistOverride: folder.lastPathComponent)
        }
    }

    /// The summary bar and the filter control used to state the same
    /// taxonomy twice — "Total/With issues/No metadata/Complete" as plain
    /// counts, "All/Missing Metadata/No Metadata at All/Complete/Found" as
    /// a separate segmented control right next to them, eating roughly
    /// half the window's width on the long "No Metadata at All" label.
    /// Merged here: each stat *is* the filter control, so there's one
    /// taxonomy, shown once, and clicking a count is the same action as
    /// picking it from a menu used to be.
    private var summaryBar: some View {
        HStack(spacing: 6) {
            ForEach(Self.filterStats(files: scanner.files, lookupResults: scanner.lookupResults)) { item in
                FilterStatButton(item: item, isSelected: filter == item.filter) { filter = item.filter }
            }
            Spacer()
            if scanner.isLookingUp {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Looking up \(scanner.lookupCompletedCount) of \(scanner.lookupTotalCount)…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if scanner.isAnalyzingSpectrum {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Analyzing \(scanner.spectralCompletedCount) of \(scanner.spectralTotalCount)…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }


    @ViewBuilder
    private func artworkThumbnailView(for file: AudioFile) -> some View {
        if let thumbnail = file.artworkThumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 24, height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .accessibilityLabel("Has artwork")
        } else {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.gray.opacity(0.2))
                .frame(width: 24, height: 24)
                .overlay {
                    Image(systemName: "music.note")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                // The placeholder means "no artwork", which is a real
                // finding rather than decoration — so it's labelled
                // rather than hidden from assistive technology.
                .accessibilityLabel("No artwork")
        }
    }

    @ViewBuilder
    private func lookupBadge(for file: AudioFile) -> some View {
        switch scanner.lookupResults[file.url] {
        case .found(let provider, _, _):
            Text("Found")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.green)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.green.opacity(0.15), in: Capsule())
                .help("Found via \(provider.rawValue)")
                // Which provider matched is only in the tooltip, so it's
                // folded into the spoken label rather than lost.
                .accessibilityLabel("Match found via \(provider.rawValue)")
                .transition(.opacity)
        case .noMatch:
            Text("No match")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.gray.opacity(0.15), in: Capsule())
                .transition(.opacity)
        case nil:
            EmptyView()
        }
    }

    /// Frequencies still real above this are "full range" — below it,
    /// mirrors the well-known ~16kHz ceiling a 128kbps lossy encode
    /// leaves behind even after being re-encoded into something that
    /// claims to be higher quality.
    private static let suspiciousCutoffThresholdHz = 17000.0

    @ViewBuilder
    private func spectralCutoffCell(for file: AudioFile) -> some View {
        switch scanner.spectralResults[file.url] {
        case .measured(let hz):
            let isLow = hz < Self.suspiciousCutoffThresholdHz
            qualityBadge(String(format: "%.1f kHz", hz / 1000), color: isLow ? .qualityWarning : .qualityGood,
                         tooltip: isLow
                            ? "Frequencies above ~\(Int(hz / 1000))kHz are missing — likely re-encoded from a lower-bitrate source"
                            : "Full-range audio up to ~\(Int(hz / 1000))kHz")
                // Suspicious vs. full-range is carried by colour alone in
                // the badge; the label states it outright.
                .accessibilityLabel(
                    String(format: "Cutoff %.1f kilohertz, %@", hz / 1000,
                           isLow ? "likely transcoded" : "full range"))
        case .inconclusive:
            Text("–").foregroundStyle(.tertiary).help("Too short or quiet to measure")
                .accessibilityLabel("Cutoff not measurable — too short or quiet")
        case .failed(let message):
            Image(systemName: "questionmark.circle")
                .foregroundStyle(.secondary)
                .help(message)
                .accessibilityLabel("Cutoff measurement failed: \(message)")
        case nil:
            Text("–").foregroundStyle(.tertiary)
                .accessibilityLabel("Cutoff not measured")
        }
    }

    @TableColumnBuilder<AudioFile, KeyPathComparator<AudioFile>>
    private var metadataColumns: some TableColumnContent<AudioFile, KeyPathComparator<AudioFile>> {
        TableColumn("Title", value: \.title.orDash)
        TableColumn("Artist", value: \.artist.orDash)
        if scanner.category == .albums {
            TableColumn("Expected Artist", value: \.expectedArtist.orDash)
        }
        TableColumn("Album", value: \.album.orDash)
        TableColumn("Year", value: \.year.orDash).width(50)
        TableColumn("Genre", value: \.genre.orDash)
        if scanner.category != .singles {
            TableColumn("Track", value: \.trackNumber.orDash).width(50)
        }
    }

    private var table: some View {
        Table(filteredFiles, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Artwork") { file in
                artworkThumbnailView(for: file)
            }
            .width(32)

            TableColumn("") { file in
                Image(systemName: statusSymbol(for: file))
                    .foregroundStyle(statusColor(for: file))
                    .help(file.isReadable
                          ? file.issues.map(\.label).joined(separator: ", ")
                          : "Could not read this file")
                    .accessibilityLabel("Status: \(statusLabel(for: file))")
            }
            .width(24)

            // Files in one folder commonly share a long identical prefix
            // and differ only at the end (e.g. "Arrested Development - "
            // followed by "(Dubb Mix)", "(For DJ's Only)", "(Remix)") — tail
            // truncation would cut exactly the part that tells rows apart,
            // so this truncates from the middle instead. It's also the only
            // column below with no width constraint, which otherwise loses
            // every fight for space against the fixed-width columns.
            TableColumn("File", value: \.fileName) { file in
                Text(file.fileName)
                    .truncationMode(.middle)
                    .help(file.url.path(percentEncoded: false))
            }
            .width(min: 160, ideal: 260)

            metadataColumns

            TableColumn("Issues") { file in
                if file.issues.isEmpty {
                    Text("–").foregroundStyle(.tertiary)
                } else {
                    HStack(spacing: 4) {
                        ForEach(file.issues) { issue in
                            Text(issue.label)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(issue.isArtistMismatch ? Color.red.opacity(0.2) : Color.orange.opacity(0.2),
                                            in: Capsule())
                        }
                    }
                }
            }
            // A single-issue file (the common case) only needs room for one
            // small pill — this used to reserve 180pt regardless, the
            // second-widest column in the table to show one badge. `ideal`
            // still gives it room to grow for a file missing everything.
            .width(min: 70, ideal: 130)

            // Lookup and Cutoff only ever hold data once "Find All
            // Metadata" / "Check for Transcodes" has actually run — until
            // then they're blank space (Lookup empty, Cutoff four em-dashes)
            // reserved at the File column's expense. Shown only once there's
            // something to show; see `showsLookupColumn`/`showsCutoffColumn`.
            if Self.showsLookupColumn(lookupResults: scanner.lookupResults) {
                TableColumn("Lookup") { file in
                    lookupBadge(for: file)
                        // Badges fill in one at a time as a batch lookup
                        // runs — an instant pop reads as flicker, a quick
                        // fade reads as results arriving.
                        .consistentAnimation(scanner.lookupResults[file.url]?.isFound)
                }
                .width(72)
            }

            TableColumn("Bitrate", value: \.bitrateSortKey) { file in
                if let kbps = file.bitrateKbps {
                    qualityBadge("\(kbps.formatted()) kbps", color: bitrateColor(for: file),
                                 tooltip: "Real encoded bitrate, read from the audio stream itself")
                } else {
                    Text("–").foregroundStyle(.tertiary)
                }
            }
            .width(82)

            if Self.showsCutoffColumn(spectralResults: scanner.spectralResults) {
                TableColumn("Cutoff") { file in
                    spectralCutoffCell(for: file)
                }
                .width(82)
            }
            TableColumn("Length", value: \.formattedDuration).width(60)
            TableColumn("Size", value: \.formattedSize).width(80)
        }
        .contextMenu(forSelectionType: AudioFile.ID.self) { ids in
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting(Array(ids))
            }
            if ids.count == 1, let id = ids.first,
               let file = scanner.files.first(where: { $0.id == id }) {
                Button("Find Metadata…") {
                    metadataLookupInitialProvider = scanner.lookupResults[file.url]?.provider ?? .discogs
                    metadataLookupFile = file
                }
            }
        } primaryAction: { ids in
            NSWorkspace.shared.activateFileViewerSelecting(Array(ids))
        }
    }

    private func statusSymbol(for file: AudioFile) -> String {
        if !file.isReadable { return "exclamationmark.triangle.fill" }
        if file.hasNoMetadata { return "xmark.circle.fill" }
        if file.hasIssues { return "exclamationmark.circle.fill" }
        return "checkmark.circle.fill"
    }

    /// Spoken equivalent of `statusSymbol` + `statusColor`. That column
    /// has an empty header and its cell is a bare SF Symbol, so without
    /// this VoiceOver announces an unlabelled image in an unnamed column
    /// — and the status is otherwise carried by shape and colour alone.
    private func statusLabel(for file: AudioFile) -> String {
        if !file.isReadable { return "Unreadable" }
        if file.hasNoMetadata { return "No metadata at all" }
        if file.hasIssues {
            return "Missing \(file.issues.map(\.label).joined(separator: ", "))"
        }
        return "Complete"
    }

    private func statusColor(for file: AudioFile) -> Color {
        if !file.isReadable { return .yellow }
        if file.hasNoMetadata { return .red }
        if file.hasIssues { return .orange }
        return .green
    }

    /// Rough quality tiers for the real computed bitrate — 256kbps+ (and
    /// every lossless file, which naturally lands far above that) reads as
    /// high quality; below the ~128kbps historical "acceptable" floor for
    /// lossy audio reads as low quality.
    private func bitrateColor(for file: AudioFile) -> Color {
        guard let kbps = file.bitrateKbps else { return .secondary }
        if kbps >= 256 { return .qualityGood }
        if kbps >= 128 { return .qualityWarning }
        return .qualityBad
    }

    /// A small colored pill — same treatment as the "Found"/"No match"
    /// lookup badges — for a quality reading that's actually available.
    /// Text uses a deepened shade of `color` rather than the base hue: a
    /// plain system color on its own light tint (e.g. `.green` text on
    /// `.green.opacity(0.15)`) doesn't have enough contrast to read well.
    private func qualityBadge(_ text: String, color: Color, tooltip: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .help(tooltip)
    }

    // MARK: - Toolbar

    /// Four groups rather than one flat row of thirteen buttons. Those
    /// thirteen weren't peers: four of them are a workflow — choose a
    /// folder, scan it, search for what's missing, apply what was found —
    /// and the rest are occasional tools. Flat and equally weighted, the
    /// row overflowed, macOS dropped the labels, and the primary action
    /// became genuinely hard to find.
    ///
    /// Grouping gets it to seven items, so every one keeps its text
    /// label. The menus are named for what they do rather than a generic
    /// "Tools": everything under Organize *moves or renames files on
    /// disk*, everything under Check only *reads and reports* — which is
    /// exactly what someone needs to know before opening an unfamiliar
    /// one.
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem {
            Picker("Library Type", selection: $selectedCategory) {
                ForEach(LibraryCategory.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .help("Tag the folder you're about to scan as Singles, Albums, or Compilations")
        }

        ToolbarItemGroup {
            Button("Choose Folder…", systemImage: "folder") {
                showFolderPicker = true
            }
            .help(selectedCategory == .singles
                  ? "Choose one or more folders to scan — Singles can span several artist folders"
                  : "Choose a folder to scan")
            rescanControl
        }

        ToolbarItemGroup {
            Button(scanner.isLookingUp ? "Stop" : "Find All Metadata",
                   systemImage: scanner.isLookingUp ? "stop.fill" : "magnifyingglass") {
                if scanner.isLookingUp {
                    scanner.cancelLookup()
                } else {
                    scanner.findAllMetadata(discogsToken: discogsToken, musicBrainzContact: musicBrainzContact)
                }
            }
            .disabled(!scanner.isLookingUp && !canFindAllMetadata)
            .help(findAllMetadataHelp)

            Button("Apply Found Matches…", systemImage: "checkmark.circle") {
                openWindow(id: "apply-found-matches")
            }
            .disabled(!canApplyFoundMatches)
            .help(applyFoundMatchesHelp)
        }

        ToolbarItemGroup {
            organizeMenu
            checkControl
            exportMenu
        }
    }

    /// "Treat This Folder as the Artist" *is* a rescan — the same
    /// operation with a different artist derivation — so it hangs off the
    /// Rescan button instead of sitting at the far end of the row looking
    /// like an unrelated feature. Albums-only, since the override it sets
    /// is ignored for every other category (see
    /// `expectedArtist(for:in:override:category:)`); outside Albums there's
    /// nothing to put in a menu, so this stays a plain button rather than
    /// a one-item dropdown.
    @ViewBuilder
    private var rescanControl: some View {
        if selectedCategory == .albums {
            Menu {
                Button("Rescan") { rescanCurrentFolders() }
                Button("Rescan Treating This Folder as the Artist") {
                    if let folder = scanner.scannedFolder { treatScannedFolderAsArtist(folder) }
                }
                .disabled(scanner.scannedFolder == nil)
                .help(treatAsArtistHelp)
            } label: {
                Label("Rescan", systemImage: "arrow.clockwise")
            } primaryAction: {
                rescanCurrentFolders()
            }
            .menuIndicator(.visible)
            .disabled(!canRescan)
            .help(needsScanHelp("Re-read the scanned folders from disk"))
        } else {
            Button("Rescan", systemImage: "arrow.clockwise") { rescanCurrentFolders() }
                .disabled(!canRescan)
                .help(needsScanHelp("Re-read the scanned folders from disk"))
        }
    }

    /// Everything here moves or renames files on disk. Each opens its own
    /// preview-then-apply window, so the menu commits to nothing itself.
    private var organizeMenu: some View {
        Menu {
            Button("Rename Files…") { openWindow(id: "rename-files") }
            if selectedCategory == .singles {
                Button("Collect into Folders…") { openWindow(id: "collect-into-folders") }
            }
            Button("Find Duplicates…") { openWindow(id: "find-duplicates") }
        } label: {
            Label("Organize", systemImage: "folder.badge.gearshape")
        }
        .disabled(scanner.files.isEmpty)
        .help(needsScanHelp("Rename, group, or de-duplicate the scanned files"))
    }

    /// Read-only checks — nothing here writes. Collapses to a direct Stop
    /// button while the spectral analysis runs: burying the stop for a
    /// long-running job inside a menu would hide the one control that
    /// matters while it's working.
    @ViewBuilder
    private var checkControl: some View {
        if scanner.isAnalyzingSpectrum {
            Button("Stop", systemImage: "stop.fill") { scanner.cancelSpectrumAnalysis() }
                .help("Stop the spectral analysis — cutoffs measured so far are kept")
        } else {
            Menu {
                if selectedCategory == .albums {
                    Button("Check Album Completeness…") { openWindow(id: "check-album-completeness") }
                }
                Button("Check for Transcodes") { scanner.analyzeSpectrum() }
            } label: {
                Label("Check", systemImage: "checklist")
            }
            .disabled(scanner.files.isEmpty)
            .help(needsScanHelp("Check the scanned files for missing tracks or transcoded audio"))
        }
    }

    private var exportMenu: some View {
        Menu {
            Button("Copy Report") { copyReport() }
            Button("Export CSV…") {
                csvDocument = CSVDocument(text: csvReport())
                showCSVExporter = true
            }
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
        }
        .disabled(scanner.files.isEmpty)
        .help(needsScanHelp("Copy the results as text, or export them as a CSV file"))
    }

    private var canRescan: Bool {
        scanner.hasScannedFolder && scanner.state != .scanning && scanner.state != .enumerating
    }

    /// Re-scans every root the current scan covers, not just the first —
    /// a Singles scan can span several folders.
    private func rescanCurrentFolders() {
        let folders = scanner.scannedFolders
        guard !folders.isEmpty else { return }
        Task {
            await scanner.scan(folders: folders, category: scanner.category ?? selectedCategory,
                                artistOverride: scanner.artistOverride)
        }
    }

    private var canFindAllMetadata: Bool {
        scanner.state == .finished
            && scanner.files.contains(where: \.hasIssues)
            && hasAnyProviderCredential
    }

    private var canApplyFoundMatches: Bool {
        scanner.lookupResults.values.contains { $0.isFound }
    }

    /// Discogs needs a token and MusicBrainz needs a contact email; with
    /// neither, every lookup path is dead. See `findAllMetadataHelp` for
    /// why this is called out separately from the other preconditions.
    private var hasAnyProviderCredential: Bool {
        !discogsToken.isEmpty || !musicBrainzContact.isEmpty
    }

    // MARK: - Help text
    //
    // A disabled control that doesn't say *why* it's disabled is a dead
    // end — especially for the app's primary action, where a tester with
    // no Discogs token saw a greyed-out button and a tooltip describing
    // what it would have done. These name the blocker that's actually in
    // effect, and only fall back to describing the action once it's
    // genuinely available.

    private var findAllMetadataHelp: String {
        if scanner.isLookingUp {
            return "Stop the batch lookup — matches found so far are kept"
        }
        if !hasAnyProviderCredential {
            return "Add a Discogs token or a MusicBrainz contact email in Settings to search for missing metadata"
        }
        if scanner.state != .finished {
            return "Scan a folder first, then search for the missing metadata it finds"
        }
        if !scanner.files.contains(where: \.hasIssues) {
            return "Nothing to look up — no scanned file is missing metadata"
        }
        return "Search Discogs and MusicBrainz for every flagged file's missing metadata"
    }

    private var applyFoundMatchesHelp: String {
        guard canApplyFoundMatches else {
            return "Run \"Find All Metadata\" first — this applies what that search found"
        }
        return "Review each file's found match, then write the Artist/Album/Year/Genre/Artwork fields it fills"
    }

    private var treatAsArtistHelp: String {
        guard scanner.hasScannedFolder else {
            return "Scan a folder first — this rescans it using its own name as the artist"
        }
        guard scanner.scannedFolder != nil else {
            return "Only available when one folder was scanned — this treats that folder's name as the artist"
        }
        return "Rescan the current folder using its own name as the artist — for scanning a single artist's folder directly instead of a parent folder containing many artists"
    }

    /// Used by every toolbar action that simply needs a completed scan.
    private func needsScanHelp(_ whenAvailable: String) -> String {
        scanner.files.isEmpty ? "Scan a folder first" : whenAvailable
    }

    private func copyReport() {
        let flagged = scanner.files.filter(\.hasIssues)
        var lines = ["CleanMyDigital report — \(pluralized(flagged.count, "file")) with issues"]
        for file in flagged {
            let issues = file.isReadable
                ? file.issues.map(\.label).joined(separator: ", ")
                : "unreadable file"
            lines.append("[\(file.category.rawValue)] \(file.url.path(percentEncoded: false)) — issues: \(issues)")
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }

    private func csvReport() -> String {
        let includeSinglesOnlyFields = scanner.category != .singles

        var header = ["Full Path", "File Name", "Category", "Title", "Artist"]
        if includeSinglesOnlyFields { header.append("Expected Artist") }
        header.append("Album")
        header.append("Year")
        header.append("Genre")
        if includeSinglesOnlyFields { header.append("Track Number") }
        header.append("Issues")
        header.append("Bitrate (kbps)")
        header.append("Duration")
        header.append("Size")

        var lines = [header.map(csvField).joined(separator: ",")]
        for file in scanner.files {
            let issues = file.isReadable
                ? file.issues.map(\.label).joined(separator: "; ")
                : "unreadable file"
            var row = [
                file.url.path(percentEncoded: false),
                file.fileName,
                file.category.rawValue,
                file.title ?? "",
                file.artist ?? "",
            ]
            if includeSinglesOnlyFields { row.append(file.expectedArtist ?? "") }
            row.append(file.album ?? "")
            row.append(file.year ?? "")
            row.append(file.genre ?? "")
            if includeSinglesOnlyFields { row.append(file.trackNumber ?? "") }
            row.append(issues)
            row.append(file.bitrateKbps.map(String.init) ?? "")
            row.append(file.formattedDuration)
            row.append(file.formattedSize)
            lines.append(row.map(csvField).joined(separator: ","))
        }
        return lines.joined(separator: "\r\n")
    }

    private func csvField(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") else {
            return value
        }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

private struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    static var writableContentTypes: [UTType] { [.commaSeparatedText] }

    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        text = configuration.file.regularFileContents
            .flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

/// Deepened shades for badge text — legible on their own 15%-opacity tint,
/// unlike the flat system colors (`.green` text on `.green.opacity(0.15)`
/// reads as washed-out and low-contrast).
private extension Color {
    static let qualityGood = Color(red: 0.11, green: 0.50, blue: 0.18)
    static let qualityWarning = Color(red: 0.68, green: 0.40, blue: 0.02)
    static let qualityBad = Color(red: 0.68, green: 0.14, blue: 0.14)
}

private extension Optional where Wrapped == String {
    var orDash: String { self?.isEmpty == false ? self! : "–" }
}

/// One stat-as-filter-button. Selection state is a tint + outline in the
/// stat's own severity colour (rather than, say, the system accent colour)
/// so selection and severity reinforce each other instead of competing for
/// attention — the count itself always keeps its colour, selected or not,
/// so it stays legible as a plain-language stat even when you aren't using
/// it to filter. A subtle hover tint gives the same feedback a selected
/// state does, so the button reads as clickable before the first click.
private struct FilterStatButton: View {
    let item: ContentView.FilterStat
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text("\(item.count)")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(item.color)
                Text(item.label)
                    .font(.callout)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(item.color.opacity(0.15))
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(item.color.opacity(0.5), lineWidth: 1)
                } else if isHovering {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.primary.opacity(0.06))
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel("\(item.count) \(item.label)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityHint("Filters the results to \(item.label.lowercased())")
    }
}

/// One row in the launch category prompt — icon, title, description, and a
/// chevron, with a hover highlight so it reads as a selectable card rather
/// than a plain button.
private struct CategoryPromptOption: View {
    let title: String
    let systemImage: String
    let description: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(isHovering ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.05),
                        in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

#Preview {
    ContentView(scanner: LibraryScanner())
}
