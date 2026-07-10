//
//  DiscogsLookupView.swift
//  CleanMyDigital
//

import AppKit
import SwiftUI

struct DiscogsLookupView: View {
    let file: AudioFile

    @AppStorage("discogsToken") private var discogsToken = ""
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openSettings) private var openSettings

    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var results: [DiscogsRelease] = []
    @State private var selectedRelease: DiscogsRelease?

    private var query: DiscogsQuery { DiscogsQuery(for: file) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(minWidth: 480, minHeight: 420)
        .task(id: file.id) {
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
            }
            Spacer()
            if selectedRelease != nil {
                Button("Back to Results") { selectedRelease = nil }
            }
            Button("Done") { dismiss() }
        }
        .padding()
    }

    @ViewBuilder
    private var content: some View {
        if let selectedRelease {
            ComparisonView(file: file, release: selectedRelease)
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
                    DiscogsResultRow(release: release)
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
            results = try await DiscogsClient.search(artist: query.artist, track: query.track, token: discogsToken)
        } catch {
            errorMessage = error.localizedDescription
            results = []
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
    }
}

private struct ComparisonView: View {
    let file: AudioFile
    let release: DiscogsRelease

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
                if let label = release.label?.first {
                    Text(label).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    private var actions: some View {
        HStack {
            Button("Copy as Text") { copyAsText() }
            if let url = release.releasePageURL {
                Link("Open on Discogs.com", destination: url)
            }
            Spacer()
        }
    }

    private func comparisonRow(field: MetadataField, current: String?, discogs: String?, note: String? = nil) -> some View {
        HStack(alignment: .top) {
            Text(field.rawValue)
                .font(.subheadline.weight(.medium))
                .frame(width: 100, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(current?.isEmpty == false ? current! : "–")
                    .foregroundStyle(.secondary)
                Text("Current").font(.caption2).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(discogs ?? note ?? "–")
                    .foregroundStyle(discogs == nil ? .tertiary : .primary)
                Text("Discogs").font(.caption2).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if fillable.contains(field) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .help("This would fill a flagged field")
            } else {
                Color.clear.frame(width: 16, height: 16)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
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
            if fillable.contains(.artwork) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .help("This would fill a flagged field")
            } else {
                Color.clear.frame(width: 16, height: 16)
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
