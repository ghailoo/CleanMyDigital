//
//  ApplyFoundMatchesSheetView.swift
//  CleanMyDigital
//

import SwiftUI

/// Applies every file's "Find All Metadata" batch-lookup match at once —
/// no per-file review, since the search already computed exactly which
/// fields (`LookupOutcome.found`'s `fillableFields`) each candidate can
/// fill. Writes sequentially via `scanner.applyTagChanges`, same as every
/// other batch write action in this codebase (`AlbumComparisonView.applyToAlbum()`,
/// `CollectSheetView`, `DuplicatesSheetView`) — never parallelized.
///
/// Discogs matches here never fill Title/Track Number — Discogs search
/// results are release-level only (see `DiscogsRelease.fillableFields`'s
/// own doc comment). That's an existing, accepted limitation; the per-file
/// "Find Metadata…" flow's tracklist-match step remains the way to fill
/// those for a Discogs match.
struct ApplyFoundMatchesSheetView: View {
    let scanner: LibraryScanner

    @Environment(\.dismissWindow) private var dismissWindow
    @AppStorage("discogsToken") private var discogsToken = ""
    @AppStorage("backupOriginalsBeforeWriting") private var backupOriginalsBeforeWriting = true

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

    /// Every scanned file with a `.found` batch-lookup outcome, in table
    /// order. Recomputed live, so a file drops off this list the moment
    /// it's applied (`applyTagChanges` clears its `lookupResults` entry).
    private var targets: [AudioFile] {
        scanner.files.filter { scanner.lookupResults[$0.url]?.isFound == true }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 640, idealWidth: 760, maxWidth: .infinity,
               minHeight: 440, idealHeight: 560, maxHeight: .infinity)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Apply Found Matches").font(.headline)
                Text("Writes the Artist/Album/Year/Genre/Artwork fields each file's batch lookup already found. Title and Track Number for Discogs matches still need the per-file tracklist match.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Done") { dismissWindow(id: "apply-found-matches") }
        }
        .padding()
    }

    @ViewBuilder
    private var content: some View {
        if targets.isEmpty {
            ContentUnavailableView {
                Label("No Found Matches", systemImage: "magnifyingglass")
            } description: {
                Text("Run \"Find All Metadata\" first, then come back here to apply what it found.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(targets) { file in
                fileRow(file)
            }
            .listStyle(.inset)
        }
    }

    private func fileRow(_ file: AudioFile) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(file.fileName).lineLimit(1)
                if let provider = scanner.lookupResults[file.url]?.provider {
                    Text("Found via \(provider.rawValue)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            outcomeLabel(for: file)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func outcomeLabel(for file: AudioFile) -> some View {
        switch outcomesByURL[file.url] {
        case nil:
            EmptyView()
        case .applied:
            Label("Applied", systemImage: "checkmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(.green)
        case .appliedWithoutBackup(let message):
            Label("Applied, but backup failed — \(message)", systemImage: "exclamationmark.triangle")
                .font(.caption2)
                .foregroundStyle(.orange)
        case .alreadyComplete:
            Label("Already complete", systemImage: "checkmark.circle")
                .font(.caption2)
                .foregroundStyle(.secondary)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(.red)
        }
    }

    private var footer: some View {
        HStack {
            Text("\(targets.count) file(s) with a found match")
                .font(.callout)
                .foregroundStyle(.secondary)
            if let applySummary {
                Text(applySummary).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if isApplying { ProgressView().controlSize(.small) }
            Button("Apply All Found Matches") { Task { await applyAll() } }
                .buttonStyle(.borderedProminent)
                .disabled(targets.isEmpty || isApplying)
        }
        .padding()
    }

    private func applyAll() async {
        isApplying = true
        defer { isApplying = false }
        outcomesByURL = [:]

        let files = targets
        var appliedCount = 0
        var appliedWithoutBackupCount = 0
        var alreadyCompleteCount = 0
        var failedCount = 0

        for file in files {
            guard case .found(_, let candidate, let fillable) = scanner.lookupResults[file.url] else { continue }

            do {
                let changes = try await candidate.buildChanges(fillable: fillable, discogsToken: discogsToken)
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
    }

    /// "Applied to X of Y file(s)" plus whichever of
    /// without-backup/already-complete/failed counts are nonzero — same
    /// wording pattern as `AlbumComparisonView.applySummaryText`.
    private static func summaryText(
        applied: Int, appliedWithoutBackup: Int, alreadyComplete: Int, failed: Int, total: Int
    ) -> String {
        var parts = ["Applied to \(applied) of \(total) file(s)"]
        if appliedWithoutBackup > 0 { parts.append("\(appliedWithoutBackup) without a backup") }
        if alreadyComplete > 0 { parts.append("\(alreadyComplete) already complete") }
        if failed > 0 { parts.append("\(failed) failed") }
        return parts.joined(separator: ", ") + "."
    }
}
