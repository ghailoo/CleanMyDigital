//
//  AlbumCompletenessSheetView.swift
//  CleanMyDigital
//

import SwiftUI

/// Reports which scanned Albums-category folders appear to be missing
/// tracks, purely from each file's own track-number tag. For albums the tags
/// can't confirm, "Check on Discogs" opens `AlbumMetadataLookupView` to
/// search, compare candidate releases, and apply the match.
struct AlbumCompletenessSheetView: View {
    let scanner: LibraryScanner

    @Environment(\.dismissWindow) private var dismissWindow

    @State private var groups: [AlbumGroup] = []
    @State private var albumLookupGroup: AlbumGroup?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 640, idealWidth: 760, maxWidth: .infinity,
               minHeight: 440, idealHeight: 520, maxHeight: .infinity)
        .onAppear { rebuild() }
        .sheet(item: $albumLookupGroup) { group in
            AlbumMetadataLookupView(group: group, scanner: scanner)
                .onDisappear { rebuild() }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Check Album Completeness").font(.headline)
                Text("Groups Albums-category tracks by folder and checks each one's track-number tag for a stated total — check Discogs for albums the tags can't confirm.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Done") { dismissWindow(id: "check-album-completeness") }
        }
        .padding()
    }

    @ViewBuilder
    private var content: some View {
        if groups.isEmpty {
            ContentUnavailableView {
                Label("No Albums Found", systemImage: "opticaldisc")
            } description: {
                Text("Scan a folder as Albums to check whether each one has its full tracklist.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(groups) { group in
                albumRow(group)
            }
            .listStyle(.inset)
        }
    }

    private func albumRow(_ group: AlbumGroup) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(group.albumTitle ?? group.folderURL.lastPathComponent)
                    .font(.body.weight(.medium))
                Text(group.artist ?? "Unknown Artist")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(tracksFoundText(for: group))
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .trailing)
            statusView(for: group)
                .frame(width: 220, alignment: .leading)
        }
        .padding(.vertical, 4)
    }

    private func tracksFoundText(for group: AlbumGroup) -> String {
        if let total = group.expectedTotalFromTags {
            return "\(group.files.count) / \(total)"
        }
        return "\(group.files.count) / ?"
    }

    @ViewBuilder
    private func statusView(for group: AlbumGroup) -> some View {
        switch group.localStatus {
        case .completeLocally:
            badge("Complete", color: .green)
        case .incompleteLocally(let missingCount, let missingPositions):
            VStack(alignment: .leading, spacing: 4) {
                badge(missingLabel(count: missingCount, positions: missingPositions), color: .orange)
                checkOnlineButton(group)
            }
        case .unknownLocally:
            VStack(alignment: .leading, spacing: 4) {
                badge("Unknown locally", color: .secondary)
                checkOnlineButton(group)
            }
        }
    }

    private func checkOnlineButton(_ group: AlbumGroup) -> some View {
        Button("Check on Discogs") { albumLookupGroup = group }
            .buttonStyle(.link)
            .font(.caption2)
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
    }

    private func missingLabel(count: Int, positions: [Int]) -> String {
        guard !positions.isEmpty else { return "Missing \(count) track(s)" }
        let list = positions.map(String.init).joined(separator: ", ")
        return "Missing track\(count == 1 ? "" : "s") \(list)"
    }

    private var footer: some View {
        HStack {
            Text("\(groups.count) album(s)")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
    }

    private func rebuild() {
        groups = AlbumCompletenessChecker.groups(for: scanner.files)
    }
}
