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
        switch filter {
        case .all: break
        case .issues: result = result.filter(\.hasIssues)
        case .noMetadata: result = result.filter(\.hasNoMetadata)
        case .complete: result = result.filter { !$0.hasIssues }
        case .found: result = result.filter { scanner.lookupResults[$0.url]?.isFound == true }
        }
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
        .frame(minWidth: 800, minHeight: 500)
        .toolbar { toolbarContent }
        .searchable(text: $searchText, prompt: "Search file, title, artist, album")
        .fileImporter(isPresented: $showFolderPicker,
                      allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                Task { await scanner.scan(folder: url, category: selectedCategory) }
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
        .navigationTitle("CleanMyDigital")
        .navigationSubtitle(navigationSubtitleText)
    }

    private var navigationSubtitleText: String {
        guard let scannedFolder = scanner.scannedFolder else { return "" }
        let path = scannedFolder.path(percentEncoded: false)
        guard let category = scanner.category else { return path }
        return "\(path) — \(category.rawValue)"
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
                misrootedFolderWarningBanner(example: example)
                Divider()
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

    private func treatScannedFolderAsArtist(_ folder: URL) {
        let category = scanner.category ?? selectedCategory
        Task {
            await scanner.scan(folder: folder, category: category, artistOverride: folder.lastPathComponent)
        }
    }

    private var summaryBar: some View {
        HStack(spacing: 20) {
            stat("Total", scanner.files.count, color: .secondary)
            stat("With issues", scanner.files.count(where: \.hasIssues), color: .orange)
            stat("No metadata", scanner.files.count(where: \.hasNoMetadata), color: .red)
            stat("Complete", scanner.files.count { !$0.hasIssues }, color: .green)
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
            Picker("Filter", selection: $filter) {
                ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func stat(_ label: String, _ value: Int, color: Color) -> some View {
        HStack(spacing: 6) {
            Text("\(value)").font(.title3.weight(.semibold)).foregroundStyle(color)
            Text(label).font(.callout).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func artworkThumbnailView(for file: AudioFile) -> some View {
        if let thumbnail = file.artworkThumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 24, height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 3))
        } else {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.gray.opacity(0.2))
                .frame(width: 24, height: 24)
                .overlay {
                    Image(systemName: "music.note")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
        case .noMatch:
            Text("No match")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.gray.opacity(0.15), in: Capsule())
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
        case .inconclusive:
            Text("–").foregroundStyle(.tertiary).help("Too short or quiet to measure")
        case .failed(let message):
            Image(systemName: "questionmark.circle")
                .foregroundStyle(.secondary)
                .help(message)
        case nil:
            Text("–").foregroundStyle(.tertiary)
        }
    }

    @TableColumnBuilder<AudioFile, KeyPathComparator<AudioFile>>
    private var metadataColumns: some TableColumnContent<AudioFile, KeyPathComparator<AudioFile>> {
        TableColumn("Title", value: \.title.orDash)
        TableColumn("Artist", value: \.artist.orDash)
        if scanner.category != .singles {
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
            }
            .width(24)

            TableColumn("File", value: \.fileName) { file in
                Text(file.fileName).help(file.url.path(percentEncoded: false))
            }

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
            .width(min: 180)

            TableColumn("Lookup") { file in
                lookupBadge(for: file)
            }
            .width(72)

            TableColumn("Bitrate", value: \.bitrateSortKey) { file in
                if let kbps = file.bitrateKbps {
                    qualityBadge("\(kbps.formatted()) kbps", color: bitrateColor(for: file),
                                 tooltip: "Real encoded bitrate, read from the audio stream itself")
                } else {
                    Text("–").foregroundStyle(.tertiary)
                }
            }
            .width(82)
            TableColumn("Cutoff") { file in
                spectralCutoffCell(for: file)
            }
            .width(82)
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
        ToolbarItem {
            Button("Choose Folder…", systemImage: "folder") {
                showFolderPicker = true
            }
        }
        ToolbarItem {
            Button("Rescan", systemImage: "arrow.clockwise") {
                if let folder = scanner.scannedFolder {
                    Task {
                        await scanner.scan(folder: folder, category: scanner.category ?? selectedCategory,
                                            artistOverride: scanner.artistOverride)
                    }
                }
            }
            .disabled(scanner.scannedFolder == nil
                      || scanner.state == .scanning || scanner.state == .enumerating)
        }
        ToolbarItem {
            Button("Copy Report", systemImage: "doc.on.clipboard") {
                copyReport()
            }
            .disabled(scanner.files.isEmpty)
            .help("Copy the list of files with missing metadata to the clipboard")
        }
        ToolbarItem {
            Button("Export CSV…", systemImage: "square.and.arrow.up") {
                csvDocument = CSVDocument(text: csvReport())
                showCSVExporter = true
            }
            .disabled(scanner.files.isEmpty)
            .help("Export every scanned file's metadata as a CSV file")
        }
        ToolbarItem {
            Button(scanner.isLookingUp ? "Stop" : "Find All Metadata",
                   systemImage: scanner.isLookingUp ? "stop.fill" : "magnifyingglass") {
                if scanner.isLookingUp {
                    scanner.cancelLookup()
                } else {
                    scanner.findAllMetadata(discogsToken: discogsToken, musicBrainzContact: musicBrainzContact)
                }
            }
            .disabled(!scanner.isLookingUp && !canFindAllMetadata)
            .help(scanner.isLookingUp
                  ? "Stop the batch lookup — matches found so far are kept"
                  : "Search Discogs and MusicBrainz for every flagged file's missing metadata")
        }
        ToolbarItem {
            Button("Rename Files…", systemImage: "textformat") {
                openWindow(id: "rename-files")
            }
            .disabled(scanner.files.isEmpty)
            .help("Rename files to \"Artist - Title\" using their tags")
        }
        ToolbarItem {
            Button("Collect into Folders…", systemImage: "folder.badge.plus") {
                openWindow(id: "collect-into-folders")
            }
            .disabled(scanner.files.isEmpty)
            .help("Group each Singles track's mixes into a subfolder named after the release")
        }
        Group {
            ToolbarItem {
                Button("Find Duplicates…", systemImage: "doc.on.doc") {
                    openWindow(id: "find-duplicates")
                }
                .disabled(scanner.files.isEmpty)
                .help("Find files sharing the same Artist and Title, and move the lower-quality copy aside")
            }
            ToolbarItem {
                Button("Check Album Completeness…", systemImage: "checklist") {
                    openWindow(id: "check-album-completeness")
                }
                .disabled(scanner.files.isEmpty || scanner.category != .albums)
                .help("Check whether each scanned album folder has its full tracklist")
            }
            ToolbarItem {
                Button(scanner.isAnalyzingSpectrum ? "Stop" : "Check for Transcodes",
                       systemImage: scanner.isAnalyzingSpectrum ? "stop.fill" : "waveform.badge.exclamationmark") {
                    if scanner.isAnalyzingSpectrum {
                        scanner.cancelSpectrumAnalysis()
                    } else {
                        scanner.analyzeSpectrum()
                    }
                }
                .disabled(!scanner.isAnalyzingSpectrum && scanner.files.isEmpty)
                .help(scanner.isAnalyzingSpectrum
                      ? "Stop the spectral analysis — cutoffs measured so far are kept"
                      : "Measure each file's real frequency cutoff to flag likely transcoded/fake-quality files")
            }
        }
    }

    private var canFindAllMetadata: Bool {
        scanner.state == .finished
            && scanner.files.contains(where: \.hasIssues)
            && (!discogsToken.isEmpty || !musicBrainzContact.isEmpty)
    }

    private func copyReport() {
        let flagged = scanner.files.filter(\.hasIssues)
        var lines = ["CleanMyDigital report — \(flagged.count) file(s) with issues"]
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
