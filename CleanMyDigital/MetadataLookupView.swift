//
//  MetadataLookupView.swift
//  CleanMyDigital
//

import AppKit
import SwiftUI

struct MetadataLookupView: View {
    let file: AudioFile
    let scanner: LibraryScanner

    @State private var provider: MetadataProvider

    init(file: AudioFile, scanner: LibraryScanner, initialProvider: MetadataProvider = .discogs) {
        self.file = file
        self.scanner = scanner
        _provider = State(initialValue: initialProvider)
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Provider", selection: $provider) {
                ForEach(MetadataProvider.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding()

            Divider()

            content
        }
        .frame(minWidth: 480, minHeight: 460)
    }

    @ViewBuilder
    private var content: some View {
        switch provider {
        case .discogs:
            DiscogsTabView(file: file, scanner: scanner)
        case .musicBrainz:
            MusicBrainzTabView(file: file, scanner: scanner)
        }
    }
}

/// Shared "Apply to File" affordance used by both comparison views. Writes
/// only the fields the candidate would fill (never anything already
/// present), backing up the original first if that setting is on, then
/// re-inspects the file so the results table refreshes immediately.
private struct ApplyToFileSection: View {
    let file: AudioFile
    let scanner: LibraryScanner
    let fillable: Set<MetadataField>
    let buildChanges: () async throws -> TagChanges

    @AppStorage("backupOriginalsBeforeWriting") private var backupOriginalsBeforeWriting = true
    @State private var isApplying = false
    @State private var outcome: Result<Set<MetadataField>, Error>?
    /// Set alongside a `.success` outcome when the write went through but
    /// its backup didn't — backup failures don't block the write (see
    /// `LibraryScanner.applyTagChanges`), so this is reported separately
    /// rather than as a write failure.
    @State private var backupFailureMessage: String?

    private var canWriteFormat: Bool { TagWriterRouter.canWrite(fileExtension: file.fileExtension) }
    private var isApplied: Bool {
        if case .success = outcome { return true }
        return false
    }

    /// Names whichever blocker is actually in effect, same pattern as
    /// `ContentView.findAllMetadataHelp` — a disabled button that only
    /// described its own action left a tester staring at a greyed-out
    /// "Apply to File" with no way to tell why.
    private var applyHelp: String {
        if isApplied { return "Already applied to this file" }
        if isApplying { return "Applying…" }
        if !canWriteFormat { return "This format can't be written yet" }
        if fillable.isEmpty { return "Nothing to fill — every fillable field already has a value" }
        return "Write this match's fields to the file's tags"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button("Apply to File") { Task { await apply() } }
                    .disabled(fillable.isEmpty || !canWriteFormat || isApplying || isApplied)
                    .help(applyHelp)
                if isApplying { ProgressView().controlSize(.small) }
            }
            if !canWriteFormat {
                Text("This format can't be written yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let outcome {
                switch outcome {
                case .success(let filled):
                    Label("Applied: \(filled.map(\.rawValue).sorted().joined(separator: ", "))",
                          systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                case .failure(let error):
                    Label(error.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            if let backupFailureMessage {
                Label("Backup failed, so the original wasn't saved: \(backupFailureMessage)",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func apply() async {
        isApplying = true
        defer { isApplying = false }
        do {
            let changes = try await buildChanges()
            let backupFailure = try await scanner.applyTagChanges(
                changes, to: file, backupFirst: backupOriginalsBeforeWriting)
            outcome = .success(fillable)
            backupFailureMessage = backupFailure?.localizedDescription
        } catch {
            outcome = .failure(error)
        }
    }
}

// MARK: - Discogs

private struct DiscogsTabView: View {
    let file: AudioFile
    let scanner: LibraryScanner

    @AppStorage("discogsToken") private var discogsToken = ""
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openSettings) private var openSettings

    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var results: [DiscogsRelease] = []
    /// True when `results` came from `DiscogsClient.searchTrack`'s broader
    /// retry with no artist term at all — `resultsList` says so rather than
    /// let a pick here read as a confirmed artist+title match.
    @State private var usedTitleOnlyFallback = false
    @State private var selectedRelease: DiscogsRelease?
    @State private var artistText = ""
    @State private var trackText = ""
    @State private var albumText = ""

    private var query: DiscogsQuery { DiscogsQuery(for: file) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if selectedRelease == nil {
                searchFieldsRow
                Divider()
            }
            content
        }
        .task(id: file.id) {
            artistText = query.artist
            trackText = query.track
            albumText = query.album
            await search()
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(selectedRelease == nil ? "Find on Discogs" : "Compare with Discogs")
                    .font(.headline)
                Text(file.fileName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                // The Artist search field above is blank for a compilation
                // (see `DiscogsQuery`'s doc comment) — the track's own real
                // artist would otherwise be invisible in this sheet, even
                // though it's what tells a user the right track is searched.
                if file.category == .compilations, let trackArtist = file.artist, !trackArtist.isEmpty {
                    Text("Track artist (tag): \(trackArtist)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if selectedRelease != nil {
                Button("Back to Results") { selectedRelease = nil }
            }
            Button("Done") { dismiss() }
        }
        .padding()
    }

    /// Lets the user override the auto-derived artist/track terms and
    /// re-search — the automatic cleanup (stripping "Artist - " prefixes,
    /// mix names) doesn't always guess right, and there was previously no
    /// way to correct it short of renaming the file.
    private var searchFieldsRow: some View {
        HStack(spacing: 8) {
            TextField("Artist", text: $artistText)
                .textFieldStyle(.roundedBorder)
                .onSubmit { Task { await search() } }
            TextField("Track", text: $trackText)
                .textFieldStyle(.roundedBorder)
                .onSubmit { Task { await search() } }
            if file.category != .singles {
                TextField("Album", text: $albumText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await search() } }
            }
            Button("Search") { Task { await search() } }
                .disabled(discogsToken.isEmpty)
                .help(discogsToken.isEmpty
                      ? "Add a Discogs personal access token in Settings to search"
                      : "Search Discogs again using the terms above")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        if let selectedRelease {
            ComparisonView(file: file, release: selectedRelease, scanner: scanner)
        } else {
            resultsList
        }
    }

    @ViewBuilder
    private var resultsList: some View {
        if discogsToken.isEmpty {
            ContentUnavailableView {
                Label("No Discogs Token", systemImage: "key.slash")
            } description: {
                Text("Add a Discogs personal access token in Settings to search for releases.")
            } actions: {
                Button("Open Settings…") { openSettings() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if isLoading {
            ProgressView("Searching Discogs…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage {
            ContentUnavailableView {
                Label("Search Failed", systemImage: "exclamationmark.triangle")
            } description: {
                Text(errorMessage)
            } actions: {
                Button("Try Again") { Task { await search() } }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if results.isEmpty {
            ContentUnavailableView.search
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                if usedTitleOnlyFallback {
                    Label("No match with the artist included — these releases matched on title only.",
                          systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(.horizontal)
                        .padding(.top, 6)
                }
                List(results) { release in
                    Button {
                        selectedRelease = release
                    } label: {
                        DiscogsResultRow(release: release)
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.inset)
            }
        }
    }

    private func search() async {
        guard !discogsToken.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        let artist = artistText.trimmingCharacters(in: .whitespacesAndNewlines)
        let track = trackText.trimmingCharacters(in: .whitespacesAndNewlines)
        let album = albumText.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if file.category == .compilations {
                // Album title only; the track is matched against the picked
                // release's tracklist in `ComparisonView.loadDetail`.
                results = try await DiscogsClient.searchCompilation(
                    artist: artist, track: track, album: album, token: discogsToken)
                usedTitleOnlyFallback = false
            } else {
                // `album` isn't sent here — see `DiscogsClient.searchTrack`'s
                // doc comment on why a per-file search sends free-text `q=`
                // (artist+track combined) with no `release_title` alongside it.
                let outcome = try await DiscogsClient.searchTrack(artist: artist, track: track, token: discogsToken)
                results = outcome.releases
                usedTitleOnlyFallback = outcome.usedBroaderTitleOnlyFallback
            }
        } catch {
            errorMessage = error.localizedDescription
            results = []
            usedTitleOnlyFallback = false
        }
    }
}

private struct DiscogsResultRow: View {
    let release: DiscogsRelease

    var body: some View {
        HStack(spacing: 10) {
            AsyncImage(url: release.thumbURL) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle().fill(Color.gray.opacity(0.2))
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 2) {
                Text(release.title).font(.body).lineLimit(1)
                HStack(spacing: 6) {
                    if let year = release.year { Text(year) }
                    if !release.combinedGenre.isEmpty { Text(release.combinedGenre) }
                    if !release.formattedFormat.isEmpty { Text(release.formattedFormat) }
                    if let label = release.label?.first { Text(label) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer()
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        // The cover thumbnail carries no information the title/year/genre
        // text beside it doesn't already say — combining into one element
        // reads as "Title, year, genre, format, label" in one VoiceOver
        // stop instead of an unlabelled image plus separate text fragments.
        .accessibilityElement(children: .combine)
    }
}

private struct ComparisonView: View {
    let file: AudioFile
    let release: DiscogsRelease
    let scanner: LibraryScanner

    @AppStorage("discogsToken") private var discogsToken = ""

    @State private var releaseDetail: DiscogsReleaseDetail?
    @State private var isLoadingDetail = false
    @State private var detailErrorMessage: String?
    @State private var matchedTrack: DiscogsTrack?

    private var fillable: Set<MetadataField> {
        var result = release.fillableFields(missing: file.missingFields)
        if let matchedTrack {
            if file.missingFields.contains(.title), !matchedTrack.title.isEmpty {
                result.insert(.title)
            }
            if file.missingFields.contains(.trackNumber), !matchedTrack.position.isEmpty {
                result.insert(.trackNumber)
            }
        }
        return result
    }

    /// Why the Title/Track Number rows have no Discogs value yet.
    private var trackNote: String? {
        if matchedTrack != nil { return nil }
        if isLoadingDetail { return "Loading tracklist…" }
        if let detailErrorMessage { return detailErrorMessage }
        if let releaseDetail {
            return releaseDetail.tracks.isEmpty ? "No tracklist available" : "Pick a track below"
        }
        return nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerSection

                VStack(spacing: 0) {
                    comparisonRow(field: .artist, current: file.artist, discogs: release.parsedArtist)
                    Divider()
                    comparisonRow(field: .album, current: file.album, discogs: release.parsedReleaseTitle)
                    Divider()
                    comparisonRow(field: .year, current: file.year, discogs: release.year)
                    Divider()
                    comparisonRow(field: .genre, current: file.genre,
                                  discogs: release.combinedGenre.isEmpty ? nil : release.combinedGenre)
                    Divider()
                    artworkComparisonRow
                    Divider()
                    comparisonRow(field: .title, current: file.title, discogs: matchedTrack?.title, note: trackNote)
                    Divider()
                    comparisonRow(field: .trackNumber, current: file.trackNumber,
                                  discogs: matchedTrack?.position, note: trackNote)
                }
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))

                if let releaseDetail, !releaseDetail.tracks.isEmpty {
                    trackSection(releaseDetail)
                }

                ApplyToFileSection(file: file, scanner: scanner, fillable: fillable) {
                    var changes = try await LookupCandidate.discogs(release)
                        .buildChanges(fillable: fillable, discogsToken: discogsToken)
                    // Title/Track Number need this view's own tracklist match —
                    // the shared mapping never fills them for Discogs candidates.
                    if fillable.contains(.title) { changes.title = matchedTrack?.title }
                    if fillable.contains(.trackNumber) { changes.trackNumber = matchedTrack?.position }
                    return changes
                }

                actions
            }
            .padding()
        }
        .task(id: release.id) {
            await loadDetail()
        }
    }

    private func trackSection(_ detail: DiscogsReleaseDetail) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tracklist — tap to match")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(detail.tracks) { track in
                        Button {
                            matchedTrack = track
                        } label: {
                            HStack {
                                Text(track.position)
                                    .frame(width: 32, alignment: .leading)
                                    .foregroundStyle(.secondary)
                                Text(track.title)
                                Spacer()
                                if let duration = track.duration {
                                    Text(duration).foregroundStyle(.secondary)
                                }
                                if matchedTrack?.id == track.id {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                        .accessibilityLabel("Currently matched")
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(matchedTrack?.id == track.id ? Color.accentColor.opacity(0.12) : .clear)
                        if track.id != detail.tracks.last?.id { Divider() }
                    }
                }
            }
            .frame(maxHeight: 160)
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func loadDetail() async {
        guard !discogsToken.isEmpty else { return }
        isLoadingDetail = true
        detailErrorMessage = nil
        defer { isLoadingDetail = false }
        do {
            let detail = try await DiscogsClient.releaseDetail(id: release.id, token: discogsToken)
            releaseDetail = detail
            matchedTrack = detail.autoMatchedTrack(for: DiscogsQuery(for: file).track)
        } catch {
            detailErrorMessage = error.localizedDescription
        }
    }

    private var headerSection: some View {
        HStack(spacing: 12) {
            AsyncImage(url: release.coverImageURL ?? release.thumbURL) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle().fill(Color.gray.opacity(0.2))
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(release.title).font(.headline)
                if !release.formattedFormat.isEmpty {
                    Text(release.formattedFormat).font(.caption).foregroundStyle(.secondary)
                }
                if let label = release.label?.first {
                    Text(label).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }

    private var actions: some View {
        HStack {
            Button("Copy as Text") { copyAsText() }
                .help("Copy this match's fields, including which would be filled, to the clipboard")
            if let url = release.releasePageURL {
                Link("Open on Discogs.com", destination: url).help(url.absoluteString)
            }
            Spacer()
        }
    }

    private func comparisonRow(field: MetadataField, current: String?, discogs: String?, note: String? = nil) -> some View {
        MetadataComparisonRow(
            fieldLabel: field.rawValue, currentValue: current, matchColumnLabel: "Discogs",
            matchValue: discogs, matchPlaceholder: note
        ) {
            if fillable.contains(field) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .help("This would fill a flagged field")
                    .accessibilityLabel("Would fill this field")
            } else {
                Color.clear.frame(width: 16, height: 16).accessibilityHidden(true)
            }
        }
    }

    private var artworkComparisonRow: some View {
        HStack(alignment: .top) {
            Text(MetadataField.artwork.rawValue)
                .font(.subheadline.weight(.medium))
                .frame(width: 100, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                if let thumbnail = file.artworkThumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    Text("–").foregroundStyle(.secondary)
                }
                Text("Current").font(.caption2).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // The thumbnail (or its absence) carries the real finding
            // here — same reasoning as ContentView's artwork column, whose
            // placeholder is labelled rather than left decorative.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(file.artworkThumbnail != nil ? "Current artwork: present" : "Current artwork: none")
            VStack(alignment: .leading, spacing: 2) {
                if let url = release.thumbURL ?? release.coverImageURL {
                    AsyncImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fit)
                    } placeholder: {
                        ProgressView()
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    Text("–").foregroundStyle(.tertiary)
                }
                Text("Discogs").font(.caption2).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel((release.thumbURL ?? release.coverImageURL) != nil ? "Discogs artwork: present" : "Discogs artwork: none")
            if fillable.contains(.artwork) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .help("This would fill a flagged field")
                    .accessibilityLabel("Would fill this field")
            } else {
                Color.clear.frame(width: 16, height: 16).accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private func copyAsText() {
        var lines = ["Discogs match for \(file.fileName)", release.title]
        if let artist = release.parsedArtist { lines.append("Artist: \(artist)") }
        if let album = release.parsedReleaseTitle { lines.append("Album: \(album)") }
        if let year = release.year { lines.append("Year: \(year)") }
        if !release.combinedGenre.isEmpty { lines.append("Genre: \(release.combinedGenre)") }
        if let label = release.label?.first { lines.append("Label: \(label)") }
        if let matchedTrack {
            lines.append("Title: \(matchedTrack.title)")
            lines.append("Track Number: \(matchedTrack.position)")
        }
        if let url = release.releasePageURL { lines.append(url.absoluteString) }
        if !fillable.isEmpty {
            lines.append("Would fill: " + fillable.map(\.rawValue).sorted().joined(separator: ", "))
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }
}

// MARK: - MusicBrainz

private struct MusicBrainzTabView: View {
    let file: AudioFile
    let scanner: LibraryScanner

    @AppStorage("musicBrainzContact") private var musicBrainzContact = ""
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openSettings) private var openSettings

    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var results: [MusicBrainzRecording] = []
    @State private var selectedRecording: MusicBrainzRecording?
    @State private var artistText = ""
    @State private var recordingText = ""
    @State private var albumText = ""

    private var query: MusicBrainzQuery { MusicBrainzQuery(for: file) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if selectedRecording == nil {
                searchFieldsRow
                Divider()
            }
            content
        }
        .task(id: file.id) {
            artistText = query.artist
            recordingText = query.recording
            albumText = query.album
            await search()
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(selectedRecording == nil ? "Find on MusicBrainz" : "Compare with MusicBrainz")
                    .font(.headline)
                Text(file.fileName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if selectedRecording != nil {
                Button("Back to Results") { selectedRecording = nil }
            }
            Button("Done") { dismiss() }
        }
        .padding()
    }

    /// Lets the user override the auto-derived artist/recording terms and
    /// re-search, same as the Discogs tab.
    private var searchFieldsRow: some View {
        HStack(spacing: 8) {
            TextField("Artist", text: $artistText)
                .textFieldStyle(.roundedBorder)
                .onSubmit { Task { await search() } }
            TextField("Recording", text: $recordingText)
                .textFieldStyle(.roundedBorder)
                .onSubmit { Task { await search() } }
            if file.category != .singles {
                TextField("Album", text: $albumText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await search() } }
            }
            Button("Search") { Task { await search() } }
                .disabled(musicBrainzContact.isEmpty)
                .help(musicBrainzContact.isEmpty
                      ? "Add a MusicBrainz contact email in Settings to search"
                      : "Search MusicBrainz again using the terms above")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        if let selectedRecording {
            MusicBrainzComparisonView(file: file, recording: selectedRecording, scanner: scanner)
        } else {
            resultsList
        }
    }

    @ViewBuilder
    private var resultsList: some View {
        if musicBrainzContact.isEmpty {
            ContentUnavailableView {
                Label("No Contact Email", systemImage: "envelope.badge")
            } description: {
                Text("Set your contact email in Settings — MusicBrainz requires one in the User-Agent header.")
            } actions: {
                Button("Open Settings…") { openSettings() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if isLoading {
            ProgressView("Searching MusicBrainz…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage {
            ContentUnavailableView {
                Label("Search Failed", systemImage: "exclamationmark.triangle")
            } description: {
                Text(errorMessage)
            } actions: {
                Button("Try Again") { Task { await search() } }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if results.isEmpty {
            ContentUnavailableView.search
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(results) { recording in
                Button {
                    selectedRecording = recording
                } label: {
                    MusicBrainzResultRow(recording: recording)
                }
                .buttonStyle(.plain)
            }
            .listStyle(.inset)
        }
    }

    private func search() async {
        guard !musicBrainzContact.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            results = try await MusicBrainzClient.searchRecordings(
                artist: artistText.trimmingCharacters(in: .whitespacesAndNewlines),
                recording: recordingText.trimmingCharacters(in: .whitespacesAndNewlines),
                album: albumText.trimmingCharacters(in: .whitespacesAndNewlines),
                contactEmail: musicBrainzContact)
        } catch {
            errorMessage = error.localizedDescription
            results = []
        }
    }
}

/// A thumbnail from the Cover Art Archive — it 404s for many releases, so
/// failures fall back to a plain gray placeholder instead of spinning forever.
private struct CoverArtThumbnail: View {
    let url: URL?
    var size: CGFloat = 44
    var onLoadResult: ((Bool) -> Void)?

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                            .onAppear { onLoadResult?(true) }
                    case .failure:
                        placeholder
                            .onAppear { onLoadResult?(false) }
                    case .empty:
                        ProgressView()
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
                    .onAppear { onLoadResult?(false) }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var placeholder: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.2))
            .overlay {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
                    .font(.caption2)
            }
    }
}

private struct MusicBrainzResultRow: View {
    let recording: MusicBrainzRecording

    var body: some View {
        HStack(spacing: 10) {
            CoverArtThumbnail(url: recording.coverArtURL, size: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(recording.title).font(.body).lineLimit(1)
                HStack(spacing: 6) {
                    if !recording.artistNames.isEmpty { Text(recording.artistNames) }
                    if let releaseTitle = recording.releaseTitle { Text(releaseTitle) }
                    if let date = recording.releaseDate { Text(date) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer()
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct MusicBrainzComparisonView: View {
    let file: AudioFile
    let recording: MusicBrainzRecording
    let scanner: LibraryScanner

    /// nil until the Cover Art Archive request resolves.
    @State private var coverArtAvailable: Bool?

    private var yearString: String? { recording.yearString }

    /// MusicBrainz recordings include the track title directly — unlike
    /// Discogs, no separate tracklist match is needed to fill Title. Track
    /// Number and Genre aren't part of this search response, so they stay
    /// unfillable here. Artwork is only counted once the Cover Art Archive
    /// request actually resolves, since it 404s for many releases.
    private var fillable: Set<MetadataField> {
        var result = recording.fillableFields(missing: file.missingFields)
        if file.missingFields.contains(.artwork), coverArtAvailable == true {
            result.insert(.artwork)
        }
        return result
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerSection

                VStack(spacing: 0) {
                    comparisonRow(field: .title, current: file.title,
                                  found: recording.title.isEmpty ? nil : recording.title)
                    Divider()
                    comparisonRow(field: .artist, current: file.artist,
                                  found: recording.artistNames.isEmpty ? nil : recording.artistNames)
                    Divider()
                    comparisonRow(field: .album, current: file.album, found: recording.releaseTitle)
                    Divider()
                    comparisonRow(field: .year, current: file.year, found: yearString)
                    Divider()
                    comparisonRow(field: .genre, current: file.genre, found: nil, note: "Not in search results")
                    Divider()
                    artworkComparisonRow
                    Divider()
                    comparisonRow(field: .trackNumber, current: file.trackNumber, found: nil,
                                  note: "Not in search results")
                }
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))

                ApplyToFileSection(file: file, scanner: scanner, fillable: fillable) {
                    try await LookupCandidate.musicBrainz(recording).buildChanges(fillable: fillable, discogsToken: "")
                }

                actions
            }
            .padding()
        }
    }

    private var headerSection: some View {
        HStack(spacing: 12) {
            CoverArtThumbnail(url: recording.coverArtURL, size: 64)

            VStack(alignment: .leading, spacing: 2) {
                Text(recording.title).font(.headline)
                if let releaseTitle = recording.releaseTitle {
                    Text(releaseTitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }

    private var actions: some View {
        HStack {
            Button("Copy as Text") { copyAsText() }
                .help("Copy this match's fields, including which would be filled, to the clipboard")
            if let url = URL(string: "https://musicbrainz.org/recording/\(recording.id)") {
                Link("Open on MusicBrainz.org", destination: url).help(url.absoluteString)
            }
            Spacer()
        }
    }

    private func comparisonRow(field: MetadataField, current: String?, found: String?, note: String? = nil) -> some View {
        MetadataComparisonRow(
            fieldLabel: field.rawValue, currentValue: current, matchColumnLabel: "MusicBrainz",
            matchValue: found, matchPlaceholder: note
        ) {
            if fillable.contains(field) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .help("This would fill a flagged field")
                    .accessibilityLabel("Would fill this field")
            } else {
                Color.clear.frame(width: 16, height: 16).accessibilityHidden(true)
            }
        }
    }

    private var artworkComparisonRow: some View {
        HStack(alignment: .top) {
            Text(MetadataField.artwork.rawValue)
                .font(.subheadline.weight(.medium))
                .frame(width: 100, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                if let thumbnail = file.artworkThumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    Text("–").foregroundStyle(.secondary)
                }
                Text("Current").font(.caption2).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // The thumbnail (or its absence) carries the real finding
            // here — same reasoning as ContentView's artwork column, whose
            // placeholder is labelled rather than left decorative.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(file.artworkThumbnail != nil ? "Current artwork: present" : "Current artwork: none")
            VStack(alignment: .leading, spacing: 2) {
                if recording.coverArtURL != nil {
                    CoverArtThumbnail(url: recording.coverArtURL, size: 40) { available in
                        coverArtAvailable = available
                    }
                } else {
                    Text("–").foregroundStyle(.tertiary)
                }
                Text("MusicBrainz").font(.caption2).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(coverArtAvailable == true ? "MusicBrainz artwork: present" : "MusicBrainz artwork: none")
            if fillable.contains(.artwork) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .help("This would fill a flagged field")
                    .accessibilityLabel("Would fill this field")
            } else {
                Color.clear.frame(width: 16, height: 16).accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private func copyAsText() {
        var lines = ["MusicBrainz match for \(file.fileName)", recording.title]
        if !recording.artistNames.isEmpty { lines.append("Artist: \(recording.artistNames)") }
        if let releaseTitle = recording.releaseTitle { lines.append("Album: \(releaseTitle)") }
        if let yearString { lines.append("Year: \(yearString)") }
        if let url = URL(string: "https://musicbrainz.org/recording/\(recording.id)") {
            lines.append(url.absoluteString)
        }
        if !fillable.isEmpty {
            lines.append("Would fill: " + fillable.map(\.rawValue).sorted().joined(separator: ", "))
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }
}
