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

        var id: String { rawValue }
    }

    @State private var scanner = LibraryScanner()
    @State private var showFolderPicker = false
    @State private var showCSVExporter = false
    @State private var csvDocument = CSVDocument(text: "")
    @State private var filter: Filter = .issues
    @State private var searchText = ""
    @State private var sortOrder = [KeyPathComparator(\AudioFile.fileName)]
    @State private var selection: Set<AudioFile.ID> = []

    private var filteredFiles: [AudioFile] {
        var result = scanner.files
        switch filter {
        case .all: break
        case .issues: result = result.filter(\.hasIssues)
        case .noMetadata: result = result.filter(\.hasNoMetadata)
        case .complete: result = result.filter { !$0.hasIssues }
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
                Task { await scanner.scan(folder: url) }
            }
        }
        .fileExporter(isPresented: $showCSVExporter,
                      document: csvDocument,
                      contentType: .commaSeparatedText,
                      defaultFilename: "CleanMyDigital Report") { _ in }
        .navigationTitle("CleanMyDigital")
        .navigationSubtitle(scanner.scannedFolder?.path(percentEncoded: false) ?? "")
    }

    // MARK: - States

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

    private var summaryBar: some View {
        HStack(spacing: 20) {
            stat("Total", scanner.files.count, color: .secondary)
            stat("With issues", scanner.files.count(where: \.hasIssues), color: .orange)
            stat("No metadata", scanner.files.count(where: \.hasNoMetadata), color: .red)
            stat("Complete", scanner.files.count { !$0.hasIssues }, color: .green)
            Spacer()
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

    @TableColumnBuilder<AudioFile, KeyPathComparator<AudioFile>>
    private var metadataColumns: some TableColumnContent<AudioFile, KeyPathComparator<AudioFile>> {
        TableColumn("Title", value: \.title.orDash)
        TableColumn("Artist", value: \.artist.orDash)
        TableColumn("Album", value: \.album.orDash)
        TableColumn("Year", value: \.year.orDash).width(50)
        TableColumn("Genre", value: \.genre.orDash)
        TableColumn("Track", value: \.trackNumber.orDash).width(50)
    }

    private var table: some View {
        Table(filteredFiles, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("") { file in
                Image(systemName: statusSymbol(for: file))
                    .foregroundStyle(statusColor(for: file))
                    .help(file.isReadable
                          ? file.missingFields.map(\.rawValue).joined(separator: ", ")
                          : "Could not read this file")
            }
            .width(24)

            TableColumn("File", value: \.fileName) { file in
                Text(file.fileName).help(file.url.path(percentEncoded: false))
            }

            metadataColumns

            TableColumn("Missing") { file in
                if file.missingFields.isEmpty {
                    Text("–").foregroundStyle(.tertiary)
                } else {
                    HStack(spacing: 4) {
                        ForEach(file.missingFields) { field in
                            Text(field.rawValue)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.orange.opacity(0.2), in: Capsule())
                        }
                    }
                }
            }
            .width(min: 180)

            TableColumn("Length", value: \.formattedDuration).width(60)
            TableColumn("Size", value: \.formattedSize).width(80)
        }
        .contextMenu(forSelectionType: AudioFile.ID.self) { ids in
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting(Array(ids))
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

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem {
            Button("Choose Folder…", systemImage: "folder") {
                showFolderPicker = true
            }
        }
        ToolbarItem {
            Button("Rescan", systemImage: "arrow.clockwise") {
                if let folder = scanner.scannedFolder {
                    Task { await scanner.scan(folder: folder) }
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
    }

    private func copyReport() {
        let flagged = scanner.files.filter(\.hasIssues)
        var lines = ["CleanMyDigital report — \(flagged.count) file(s) with missing metadata"]
        for file in flagged {
            let missing = file.isReadable
                ? file.missingFields.map(\.rawValue).joined(separator: ", ")
                : "unreadable file"
            lines.append("\(file.url.path(percentEncoded: false)) — missing: \(missing)")
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }

    private func csvReport() -> String {
        let header = ["Full Path", "File Name", "Title", "Artist", "Album", "Year", "Genre",
                       "Track Number", "Missing Fields", "Duration", "Size"]
        var lines = [header.map(csvField).joined(separator: ",")]
        for file in scanner.files {
            let missing = file.isReadable
                ? file.missingFields.map(\.rawValue).joined(separator: "; ")
                : "unreadable file"
            let row = [
                file.url.path(percentEncoded: false),
                file.fileName,
                file.title ?? "",
                file.artist ?? "",
                file.album ?? "",
                file.year ?? "",
                file.genre ?? "",
                file.trackNumber ?? "",
                missing,
                file.formattedDuration,
                file.formattedSize,
            ]
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

private extension Optional where Wrapped == String {
    var orDash: String { self?.isEmpty == false ? self! : "–" }
}

#Preview {
    ContentView()
}
