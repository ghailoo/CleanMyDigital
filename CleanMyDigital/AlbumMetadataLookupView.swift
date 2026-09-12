//
//  AlbumMetadataLookupView.swift
//  CleanMyDigital
//

import AppKit
import SwiftUI

/// Searches Discogs for a whole album (an `AlbumGroup`'s files) at once,
/// lets the user compare candidate releases, then applies the chosen
/// release's tracklist per file — the album-level counterpart to
/// `MetadataLookupView`'s Discogs tab, reusing the same client calls and
/// apply plumbing.
struct AlbumMetadataLookupView: View {
    let group: AlbumGroup
    let scanner: LibraryScanner

    @AppStorage("discogsToken") private var discogsToken = ""
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openSettings) private var openSettings

    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var results: [DiscogsRelease] = []
    @State private var selectedRelease: DiscogsRelease?
    @State private var artistText = ""
    @State private var albumText = ""

    private var query: DiscogsAlbumQuery { DiscogsAlbumQuery(for: group) }

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
        .frame(minWidth: 560, idealWidth: 620, minHeight: 480, idealHeight: 560)
        .task {
            artistText = query.artist
            albumText = query.album
            await search()
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(selectedRelease == nil ? "Find Album on Discogs" : "Compare Album with Discogs")
                    .font(.headline)
                Text("\(group.albumTitle ?? group.folderURL.lastPathComponent) — \(pluralized(group.files.count, "file"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if selectedRelease != nil {
                Button("Back to Results") { selectedRelease = nil }
            }
            Button("Done") { dismiss() }
        }
        .padding()
    }

    /// Lets the user override the auto-derived artist/album terms and
    /// re-search — same "the automatic cleanup doesn't always guess right"
    /// affordance as the per-file Discogs tab.
    private var searchFieldsRow: some View {
        HStack(spacing: 8) {
            TextField("Artist", text: $artistText)
                .textFieldStyle(.roundedBorder)
                .onSubmit { Task { await search() } }
            TextField("Album", text: $albumText)
                .textFieldStyle(.roundedBorder)
                .onSubmit { Task { await search() } }
            Button("Search") { Task { await search() } }
                .disabled(discogsToken.isEmpty)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        if let selectedRelease {
            AlbumComparisonView(group: group, release: selectedRelease, scanner: scanner)
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
            List(results) { release in
                Button {
                    selectedRelease = release
                } label: {
                    AlbumDiscogsResultRow(release: release)
                }
                .buttonStyle(.plain)
            }
            .listStyle(.inset)
        }
    }

    private func search() async {
        guard !discogsToken.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            results = try await DiscogsClient.searchAlbum(
                artist: artistText.trimmingCharacters(in: .whitespacesAndNewlines),
                album: albumText.trimmingCharacters(in: .whitespacesAndNewlines),
                token: discogsToken)
        } catch {
            errorMessage = error.localizedDescription
            results = []
        }
    }
}

private struct AlbumDiscogsResultRow: View {
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
        // The cover thumbnail adds nothing the title/year/genre text
        // beside it doesn't already say — one combined VoiceOver stop
        // beats an unlabelled image plus separate text fragments.
        .accessibilityElement(children: .combine)
    }
}

private struct AlbumComparisonView: View {
    let group: AlbumGroup
    let release: DiscogsRelease
    let scanner: LibraryScanner

    @AppStorage("discogsToken") private var discogsToken = ""
    @AppStorage("backupOriginalsBeforeWriting") private var backupOriginalsBeforeWriting = true

    @State private var releaseDetail: DiscogsReleaseDetail?
    @State private var isLoadingDetail = false
    @State private var detailErrorMessage: String?
    @State private var matchedTracks: [URL: DiscogsTrack] = [:]

    /// The result of trying to apply changes to one file — distinguishes a
    /// file that failed to write from one that had nothing to write in the
    /// first place (every field this release would fill was already
    /// present), which "the write failed" would otherwise misreport. Also
    /// distinguishes a clean apply from one that wrote successfully but
    /// couldn't back up the original first (backup failures don't block
    /// the write — see `LibraryScanner.applyTagChanges`).
    enum ApplyOutcome {
        case applied
        case appliedWithoutBackup(String)
        case alreadyComplete
        case failed(String)
    }

    @State private var isApplying = false
    @State private var outcomesByURL: [URL: ApplyOutcome] = [:]
    @State private var applySummary: String?

    private var query: DiscogsAlbumQuery { DiscogsAlbumQuery(for: group) }

    /// How many of the group's files would actually gain `field` from this
    /// release — files can each already have some fields filled, so "would
    /// fill" is a per-group count rather than a single checkmark.
    private func fillableCount(_ field: MetadataField) -> Int {
        group.files.count { file in
            guard file.missingFields.contains(field) else { return false }
            switch field {
            case .artist: return release.parsedArtist != nil
            case .album: return release.parsedReleaseTitle != nil
            case .year: return release.year?.isEmpty == false
            case .genre: return !release.combinedGenre.isEmpty
            case .artwork: return release.coverImageURL != nil || release.thumbURL != nil
            case .title, .trackNumber: return matchedTracks[file.url] != nil
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerSection

                VStack(spacing: 0) {
                    sharedFieldRow(.artist, value: release.parsedArtist)
                    Divider()
                    sharedFieldRow(.album, value: release.parsedReleaseTitle)
                    Divider()
                    sharedFieldRow(.year, value: release.year)
                    Divider()
                    sharedFieldRow(.genre, value: release.combinedGenre.isEmpty ? nil : release.combinedGenre)
                    Divider()
                    sharedFieldRow(.artwork,
                                   value: (release.coverImageURL ?? release.thumbURL) != nil ? "Cover art available" : nil)
                }
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))

                trackMatchSection

                applySection

                actions
            }
            .padding()
        }
        .task(id: release.id) {
            await loadDetail()
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

    private func sharedFieldRow(_ field: MetadataField, value: String?) -> some View {
        HStack(alignment: .top) {
            Text(field.rawValue)
                .font(.subheadline.weight(.medium))
                .frame(width: 100, alignment: .leading)
            Text(value ?? "–")
                .foregroundStyle(value == nil ? .tertiary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            let count = fillableCount(field)
            if count > 0 {
                Text("Fills \(count) of \(group.files.count)")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.green)
            } else {
                Color.clear.frame(width: 16, height: 16).accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var trackMatchSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Track Matches — tap a file to reassign")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if isLoadingDetail {
                ProgressView().frame(maxWidth: .infinity)
            } else if let detailErrorMessage {
                Text(detailErrorMessage).font(.caption).foregroundStyle(.red)
            } else {
                VStack(spacing: 0) {
                    ForEach(group.files) { file in
                        trackMatchRow(for: file)
                        if file.id != group.files.last?.id { Divider() }
                    }
                }
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func trackMatchRow(for file: AudioFile) -> some View {
        let matched = matchedTracks[file.url]
        return Menu {
            ForEach(releaseDetail?.tracks ?? []) { track in
                Button("\(track.position)  \(track.title)") { matchedTracks[file.url] = track }
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.fileName).lineLimit(1)
                    Text(file.title?.isEmpty == false ? file.title! : "No title tag")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
                if let matched {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(matched.title).lineLimit(1)
                        Text(matched.position).font(.caption2).foregroundStyle(.tertiary)
                    }
                } else {
                    Text("No match — choose one").font(.caption).foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var applySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button("Apply to Album") { Task { await applyToAlbum() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(isApplying)
                if isApplying { ProgressView().controlSize(.small) }
            }
            if let applySummary {
                Text(applySummary).font(.caption).foregroundStyle(.secondary)
            }
            ForEach(group.files) { file in
                outcomeLabel(for: file)
            }
        }
    }

    @ViewBuilder
    private func outcomeLabel(for file: AudioFile) -> some View {
        switch outcomesByURL[file.url] {
        case .applied, nil:
            EmptyView()
        case .appliedWithoutBackup(let message):
            Label("\(file.fileName): applied, but backup failed — \(message)",
                  systemImage: "exclamationmark.triangle")
                .font(.caption2)
                .foregroundStyle(.orange)
        case .alreadyComplete:
            Label("\(file.fileName): already complete — nothing to fill", systemImage: "checkmark.circle")
                .font(.caption2)
                .foregroundStyle(.secondary)
        case .failed(let message):
            Label("\(file.fileName): \(message)", systemImage: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(.red)
        }
    }

    private var actions: some View {
        HStack {
            if let url = release.releasePageURL {
                Link("Open on Discogs.com", destination: url)
            }
            Spacer()
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
            var matches: [URL: DiscogsTrack] = [:]
            for file in group.files {
                let cleaned = MetadataQuery.cleanedTrackTitle(
                    from: file.fileName, artist: query.artist, category: group.category)
                if let matched = detail.autoMatchedTrack(for: cleaned) {
                    matches[file.url] = matched
                }
            }
            matchedTracks = matches
        } catch {
            detailErrorMessage = error.localizedDescription
        }
    }

    private func applyToAlbum() async {
        isApplying = true
        defer { isApplying = false }
        outcomesByURL = [:]

        var artworkData: Data?
        let needsArtwork = group.files.contains { $0.missingFields.contains(.artwork) }
        if needsArtwork, let url = release.coverImageURL ?? release.thumbURL {
            artworkData = try? await ArtworkDownloader.downloadJPEG(
                from: url, headers: ["Authorization": "Discogs token=\(discogsToken)"])
        }

        var appliedCount = 0
        var appliedWithoutBackupCount = 0
        var alreadyCompleteCount = 0
        var failedCount = 0

        for file in group.files {
            var changes = TagChanges()
            let missing = file.missingFields
            if missing.contains(.artist) { changes.artist = release.parsedArtist }
            if missing.contains(.album) { changes.album = release.parsedReleaseTitle }
            if missing.contains(.year) { changes.year = release.year }
            if missing.contains(.genre) {
                changes.genre = release.combinedGenre.isEmpty ? nil : release.combinedGenre
            }
            if missing.contains(.artwork), let artworkData {
                changes.artworkJPEG = artworkData
            }
            if let matched = matchedTracks[file.url] {
                if missing.contains(.title) { changes.title = matched.title }
                if missing.contains(.trackNumber) { changes.trackNumber = matched.position }
            }

            guard !changes.isEmpty else {
                outcomesByURL[file.url] = .alreadyComplete
                alreadyCompleteCount += 1
                continue
            }

            do {
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

        applySummary = Self.applySummaryText(
            applied: appliedCount, appliedWithoutBackup: appliedWithoutBackupCount,
            alreadyComplete: alreadyCompleteCount, failed: failedCount, total: group.files.count)

        recordAlbumCompletenessResult()
    }

    /// Records whether this release's tracklist fully covers the album's
    /// files. Deliberately only called from here, not from `loadDetail()` —
    /// merely viewing/comparing a candidate release shouldn't permanently
    /// mark the album confirmed if the user backs out without ever clicking
    /// Apply. A tracklist to compare against is required — an empty one
    /// just means Discogs has no track data for this release, not that the
    /// album is confirmed complete.
    ///
    /// Uses `allMatchedTracks(for:)` — every track each file plausibly
    /// covers, unioned across the whole album — rather than the one-to-one
    /// `matchedTracks` used for tag-filling/display. A single combined rip
    /// (e.g. "06 - Misterio - Interlude.flac") can legitimately cover more
    /// than one shorter track title concatenated into its name; `matchedTracks`
    /// can only ever hold one, which would falsely flag the other as missing.
    private func recordAlbumCompletenessResult() {
        guard let releaseDetail, !releaseDetail.tracks.isEmpty else { return }

        var coveredIDs: Set<String> = []
        for file in group.files {
            let cleaned = MetadataQuery.cleanedTrackTitle(
                from: file.fileName, artist: query.artist, category: group.category)
            coveredIDs.formUnion(releaseDetail.allMatchedTracks(for: cleaned).map(\.id))
        }

        let missingTitles = releaseDetail.tracks.missingTitles(matchedTrackIDs: coveredIDs)
        let onlineResult: AlbumCompletenessOnlineResult = missingTitles.isEmpty
            ? .confirmedComplete
            : .missingTracks(missingTitles)
        scanner.recordAlbumCompletenessResult(onlineResult, for: group.folderURL)
    }

    /// "Applied to X of Y file(s)" plus whichever of
    /// without-backup/already-complete/failed counts are nonzero — the base
    /// wording always distinguishes applied from not-applied; the
    /// append-on details cover *why* the rest weren't, or what's worth a
    /// second look even among the applied ones.
    private static func applySummaryText(
        applied: Int, appliedWithoutBackup: Int, alreadyComplete: Int, failed: Int, total: Int
    ) -> String {
        var parts = ["Applied to \(applied) of \(pluralized(total, "file"))"]
        if appliedWithoutBackup > 0 { parts.append("\(appliedWithoutBackup) without a backup") }
        if alreadyComplete > 0 { parts.append("\(alreadyComplete) already complete") }
        if failed > 0 { parts.append("\(failed) failed") }
        return parts.joined(separator: ", ") + "."
    }
}
