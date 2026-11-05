//
//  TrackInspectorView.swift
//  CleanMyDigital
//

import AppKit
import SwiftUI

/// Pure logic behind the inspector, testable without SwiftUI: which value
/// the selected files share per field, and what a set of edits writes.
enum TrackInspector {
    static let editableFields: [MetadataField] = [.title, .artist, .album, .year, .genre, .trackNumber, .grouping]

    enum Shared: Equatable {
        case value(String)
        case mixed
    }

    static func value(of field: MetadataField, in file: AudioFile) -> String {
        let value: String? = switch field {
        case .title: file.title
        case .artist: file.artist
        case .album: file.album
        case .year: file.year
        case .genre: file.genre
        case .trackNumber: file.trackNumber
        case .grouping: file.grouping
        default: nil
        }
        return value ?? ""
    }

    /// The value every selected file has for `field`, or `.mixed`.
    static func shared(_ field: MetadataField, in files: [AudioFile]) -> Shared {
        let values = Set(files.map { value(of: field, in: $0) })
        return values.count == 1 ? .value(values.first!) : .mixed
    }

    /// A manual edit is an explicit overwrite, so every edited field goes in
    /// `replacing`. Empty edits and unchanged values are skipped — the
    /// writers can't clear a tag, and rewriting the same value is a no-op.
    static func changes(for file: AudioFile, edits: [MetadataField: String]) -> TagChanges {
        var changes = TagChanges()
        for (field, raw) in edits {
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, text != value(of: field, in: file) else { continue }
            switch field {
            case .title: changes.title = text
            case .artist: changes.artist = text
            case .album: changes.album = text
            case .year: changes.year = text
            case .genre: changes.genre = text
            case .trackNumber: changes.trackNumber = text
            case .grouping: changes.grouping = text
            default: continue
            }
            changes.replacing.insert(field)
        }
        return changes
    }
}

/// The side panel (⌘I): artwork, editable tags, and file details for the
/// selected track — or the values shared by several selected tracks, where
/// an edit applies to all of them.
struct TrackInspectorView: View {
    let files: [AudioFile]
    let scanner: LibraryScanner
    let findMetadata: (AudioFile) -> Void

    @AppStorage("backupOriginalsBeforeWriting") private var backupFirst = true
    @State private var edits: [MetadataField: String] = [:]
    @State private var artwork: NSImage?
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var hasEdits: Bool {
        files.contains { !TrackInspector.changes(for: $0, edits: edits).isEmpty }
    }

    var body: some View {
        Group {
            if files.isEmpty {
                ContentUnavailableView("No Selection", systemImage: "music.note",
                                       description: Text("Select a track to see its details."))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        artworkView
                        heading
                        tagEditor
                        if let file = files.first, files.count == 1 {
                            fileDetails(file)
                        }
                    }
                    .padding()
                }
            }
        }
        .task(id: files.map(\.id)) {
            edits = [:]
            errorMessage = nil
            artwork = files.first?.artworkThumbnail
            if let file = files.first, let full = await scanner.fullArtwork(for: file) {
                artwork = full
            }
        }
    }

    // MARK: - Artwork & heading

    private var artworkView: some View {
        Group {
            if let artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.quinary)
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        Image(systemName: "music.note").font(.largeTitle).foregroundStyle(.tertiary)
                    }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel(artwork == nil ? "No artwork" : "Artwork")
    }

    @ViewBuilder
    private var heading: some View {
        VStack(alignment: .leading, spacing: 2) {
            if files.count == 1, let file = files.first {
                Text(file.title ?? file.fileName).font(.headline).lineLimit(2)
                Text(file.artist ?? "Unknown Artist").font(.subheadline).foregroundStyle(.secondary)
            } else {
                Text(pluralized(files.count, "track")).font(.headline)
                Text("Edits apply to every selected track").font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Tags

    private var tagEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 8) {
                ForEach(TrackInspector.editableFields, id: \.self) { field in
                    GridRow {
                        Text(field.rawValue)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .gridColumnAlignment(.trailing)
                        TextField(field.rawValue, text: binding(for: field), prompt: prompt(for: field))
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                            .onSubmit { Task { await save() } }
                    }
                }
            }

            HStack {
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.red).lineLimit(2)
                }
                Spacer()
                if isSaving { ProgressView().controlSize(.small) }
                Button("Revert") { edits = [:] }
                    .disabled(!hasEdits || isSaving)
                Button("Save") { Task { await save() } }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(!hasEdits || isSaving)
                    .help(backupFirst ? "Write these tags — originals are backed up first" : "Write these tags")
            }
            .consistentAnimation(errorMessage)
        }
    }

    private func binding(for field: MetadataField) -> Binding<String> {
        Binding(
            get: {
                if let edit = edits[field] { return edit }
                if case .value(let value) = TrackInspector.shared(field, in: files) { return value }
                return ""
            },
            set: { edits[field] = $0 }
        )
    }

    private func prompt(for field: MetadataField) -> Text {
        TrackInspector.shared(field, in: files) == .mixed ? Text("Mixed") : Text("—")
    }

    private func save() async {
        guard hasEdits, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil
        for file in files {
            let changes = TrackInspector.changes(for: file, edits: edits)
            guard !changes.isEmpty else { continue }
            do {
                _ = try await scanner.applyTagChanges(changes, to: file, backupFirst: backupFirst)
            } catch {
                errorMessage = "\(file.fileName): \(error.localizedDescription)"
            }
        }
        if errorMessage == nil { edits = [:] }
    }

    // MARK: - File details (single track)

    private func fileDetails(_ file: AudioFile) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 6) {
                detailRow("Format", file.fileExtension.uppercased())
                detailRow("Bitrate", file.bitrateKbps.map { "\($0) kbps" } ?? "—")
                detailRow("Length", file.formattedDuration)
                detailRow("Size", file.formattedSize)
                detailRow("Quality", cutoffText(for: file))
                if case .measured(_, let verdict) = scanner.spectralResults[file.url] {
                    detailRow("Why", verdict.reason)
                }
                detailRow("Lookup", lookupText(for: file))
            }
            SpectrogramView(url: file.url, root: scanner.root(containing: file.url), cutoffHz: measuredCutoff(file))
            Text(file.url.deletingLastPathComponent().path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(3)
                .truncationMode(.middle)
            HStack {
                Button("Reveal in Finder", systemImage: "folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([file.url])
                }
                Button("Find Metadata…", systemImage: "magnifyingglass") { findMetadata(file) }
            }
            .controlSize(.small)
        }
    }

    private func measuredCutoff(_ file: AudioFile) -> Double? {
        if case .measured(let hz, _) = scanner.spectralResults[file.url] { return hz }
        return nil
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).font(.caption).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
            Text(value).font(.callout).textSelection(.enabled)
        }
    }

    private func cutoffText(for file: AudioFile) -> String {
        switch scanner.spectralResults[file.url] {
        case .measured(let hz, let verdict): String(format: "%@ · %.1f kHz", verdict.grade.label, hz / 1000)
        case .inconclusive: "Inconclusive"
        case .failed: "Couldn't measure"
        case nil: "Not checked"
        }
    }

    private func lookupText(for file: AudioFile) -> String {
        guard let outcome = scanner.lookupResults[file.url] else { return "Not searched" }
        switch outcome.confidence {
        case .confident: return "Match found"
        case .review: return "Match found — needs review"
        case .none: return "No match"
        }
    }
}
