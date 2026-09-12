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

    @State private var groups: [AlbumGroup] = []
    @State private var albumLookupGroup: AlbumGroup?
    @State private var folderRenameProposals: [URL: AlbumFolderRenameProposal] = [:]
    @State private var pendingRenameProposal: AlbumFolderRenameProposal?
    @State private var isRenamingFolder = false
    @State private var renameErrorsByFolder: [URL: String] = [:]
    @State private var lastFolderChangeSummary: String?

    var body: some View {
        SheetWindowContainer(
            title: "Check Album Completeness",
            subtitle: "Groups Albums-category tracks by folder and checks each one's track-number tag for a stated total — check Discogs for albums the tags can't confirm.",
            windowID: "check-album-completeness"
        ) {
            content
        } footer: {
            footer
        }
        .onAppear { rebuild() }
        .sheet(item: $albumLookupGroup) { group in
            AlbumMetadataLookupView(group: group, scanner: scanner)
                .onDisappear { rebuild() }
        }
        .confirmationDialog(
            "Rename Folder?",
            isPresented: Binding(get: { pendingRenameProposal != nil }, set: { if !$0 { pendingRenameProposal = nil } }),
            presenting: pendingRenameProposal
        ) { proposal in
            Button("Rename") { Task { await renameFolder(proposal) } }
            Button("Cancel", role: .cancel) { pendingRenameProposal = nil }
        } message: { proposal in
            Text("\"\(proposal.currentFolderName)\" will be renamed to \"\(proposal.proposedFolderName)\".")
        }
    }

    private var content: some View {
        Group {
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
        .consistentAnimation(groups.isEmpty)
    }

    private func albumRow(_ group: AlbumGroup) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(group.albumTitle ?? group.folderURL.lastPathComponent)
                    .font(.body.weight(.medium))
                Text(group.artist ?? "Unknown Artist")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let proposal = folderRenameProposals[group.folderURL] {
                    renameFolderControl(for: proposal)
                }
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

    /// An online (Discogs) result, once one's been recorded for this
    /// folder, always wins over the local tag-based status — it reflects
    /// an actual confirmed comparison, not just a guess from track-number
    /// tags. Falls back to `localStatusView` only when there's no online
    /// result yet.
    @ViewBuilder
    private func statusView(for group: AlbumGroup) -> some View {
        if let onlineResult = scanner.albumCompletenessResults[group.folderURL] {
            onlineStatusView(onlineResult, for: group)
        } else {
            localStatusView(for: group)
        }
    }

    @ViewBuilder
    private func onlineStatusView(_ result: AlbumCompletenessOnlineResult, for group: AlbumGroup) -> some View {
        switch result {
        case .confirmedComplete:
            badge("Complete (confirmed via Discogs)", color: .green)
        case .missingTracks(let titles):
            VStack(alignment: .leading, spacing: 4) {
                badge(missingTracksLabel(titles), color: .orange)
                checkOnlineButton(group)
            }
        }
    }

    @ViewBuilder
    private func localStatusView(for group: AlbumGroup) -> some View {
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

    /// A rename proposal shown per-row, folder rename feeling more
    /// consequential than a per-file tag edit — clicking opens a
    /// preview-then-confirm dialog (see the `.confirmationDialog` on
    /// `body`) rather than renaming immediately.
    private func renameFolderControl(for proposal: AlbumFolderRenameProposal) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Button("Rename Folder to \"\(proposal.proposedFolderName)\"…") {
                pendingRenameProposal = proposal
            }
            .buttonStyle(.link)
            .font(.caption2)
            .disabled(isRenamingFolder)
            if let error = renameErrorsByFolder[proposal.group.folderURL] {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
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
        guard !positions.isEmpty else { return "Missing \(pluralized(count, "track"))" }
        let list = positions.map(String.init).joined(separator: ", ")
        return "Missing \(pluralWord(count, "track")) \(list)"
    }

    private func missingTracksLabel(_ titles: [String]) -> String {
        guard !titles.isEmpty else { return "Missing tracks" }
        return "Missing: \(titles.joined(separator: ", "))"
    }

    private var footer: some View {
        HStack {
            Text(pluralized(groups.count, "album"))
                .font(.callout)
                .foregroundStyle(.secondary)
            if let lastFolderChangeSummary {
                Text(lastFolderChangeSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
            Spacer()
            if scanner.canUndoLastFileOperation {
                Button("Undo Last Change") { Task { await undo() } }
                    .disabled(isRenamingFolder)
            }
        }
        .padding()
        // Appears once a folder rename/undo finishes — same reasoning as
        // RenameSheetView's footer.
        .consistentAnimation(lastFolderChangeSummary)
    }

    private func rebuild() {
        groups = AlbumCompletenessChecker.groups(for: scanner.files)
        folderRenameProposals = Dictionary(
            uniqueKeysWithValues: AlbumFolderRenamePlanner.plan(for: groups).map { ($0.group.folderURL, $0) })
        renameErrorsByFolder = [:]
    }

    private func renameFolder(_ proposal: AlbumFolderRenameProposal) async {
        pendingRenameProposal = nil
        isRenamingFolder = true
        defer { isRenamingFolder = false }

        let outcomes = await scanner.renameAlbumFolders([proposal])
        guard let outcome = outcomes.first else { return }
        if outcome.succeeded {
            lastFolderChangeSummary = "Renamed \"\(proposal.currentFolderName)\" to \"\(proposal.proposedFolderName)\"."
            rebuild()
        } else {
            renameErrorsByFolder[proposal.group.folderURL] = outcome.errorDescription
        }
    }

    private func undo() async {
        isRenamingFolder = true
        defer { isRenamingFolder = false }

        let outcomes = await scanner.undoLastFileOperation()
        let failedCount = outcomes.count(where: { !$0.succeeded })
        lastFolderChangeSummary = failedCount == 0
            ? "Undid \(pluralized(outcomes.count, "change"))."
            : "Undid \(outcomes.count - failedCount), \(failedCount) failed."
        rebuild()
    }
}
