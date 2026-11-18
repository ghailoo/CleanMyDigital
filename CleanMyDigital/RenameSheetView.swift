//
//  RenameSheetView.swift
//  CleanMyDigital
//

import SwiftUI

struct RenameSheetView: View {
    let scanner: LibraryScanner

    /// Opt-in: also rewrite the Title tag to drop whatever a ripper glued
    /// on after the mix name (Beatport's trailing BPM) — the same trim the
    /// proposed filename gets. One of the few deliberate exceptions to
    /// "only fill empty fields", so it stays off until asked for.
    @AppStorage("cleanTitleTagOnRename") private var cleanTitleTag = false
    @AppStorage("backupOriginalsBeforeWriting") private var backupOriginalsBeforeWriting = true

    @State private var proposals: [RenameProposal] = []
    @State private var selection: Set<URL> = []
    @State private var isBusy = false
    @State private var errorsByURL: [URL: String] = [:]
    @State private var lastRunSummary: String?

    var body: some View {
        SheetWindowContainer(
            title: "Rename Files",
            subtitle: "Renames files to \"Artist - Title\" (Albums/Compilations get a leading track number) using their tags.",
            windowID: "rename-files"
        ) {
            content
        } footer: {
            footer
        }
        .onAppear { rebuildPlan() }
    }

    private var content: some View {
        Group {
            if proposals.isEmpty {
                ContentUnavailableView {
                    Label("Nothing to Rename", systemImage: "checkmark.circle")
                } description: {
                    Text("Every file either already matches the naming convention, or is missing an Artist or Title tag.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                table
            }
        }
        .consistentAnimation(proposals.isEmpty)
    }

    private var table: some View {
        Table(proposals) {
            TableColumn("") { proposal in
                Toggle("", isOn: selectionBinding(for: proposal.id))
                    .labelsHidden()
                    .accessibilityLabel("Select \(proposal.currentName)")
            }
            .width(24)

            TableColumn("Current Name") { proposal in
                Text(proposal.currentName).lineLimit(1).help(proposal.currentName)
            }

            TableColumn("Proposed Name") { proposal in
                VStack(alignment: .leading, spacing: 2) {
                    Text(proposal.proposedName).lineLimit(1).help(proposal.proposedName)
                    if let error = errorsByURL[proposal.id] {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    } else if proposal.isCaseOnlyChange {
                        Text("Case only").font(.caption2).foregroundStyle(.secondary)
                    }
                    if cleanTitleTag, let cleaned = RenamePlanner.cleanedTitleTag(for: proposal.file) {
                        Text("Title tag → \(cleaned)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("\(selection.count) of \(proposals.count) selected")
                .font(.callout)
                .foregroundStyle(.secondary)
            if let lastRunSummary {
                Text(lastRunSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
            Spacer()
            Toggle("Clean the Title tag too", isOn: $cleanTitleTag)
                .toggleStyle(.checkbox)
                .help("Also rewrites the Title tag to drop anything after the mix name — a Beatport rip's trailing BPM, for example. Each change shows in the list before you rename.")
                .disabled(isBusy)
            if scanner.canUndoLastFileOperation {
                Button("Undo Last Change") { Task { await undo() } }
                    .accessibilityHint("Reverts the most recent rename, move, or collect")
                    .disabled(isBusy)
            }
            if isBusy { ProgressView().controlSize(.small) }
            Button("Rename Selected") { Task { await rename() } }
                .accessibilityHint("Renames the selected files on disk to their proposed names")
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(selection.isEmpty || isBusy)
        }
        .padding()
        // Appears once a rename/undo batch finishes — a fade reads as
        // "done", an instant pop reads as a layout glitch.
        .consistentAnimation(lastRunSummary)
    }

    private func selectionBinding(for id: URL) -> Binding<Bool> {
        Binding(
            get: { selection.contains(id) },
            set: { isOn in
                if isOn { selection.insert(id) } else { selection.remove(id) }
            }
        )
    }

    private func rebuildPlan() {
        proposals = RenamePlanner.plan(for: scanner.files)
        selection = Set(proposals.map(\.id))
        errorsByURL = [:]
    }

    private func rename() async {
        isBusy = true
        defer { isBusy = false }

        let selected = proposals.filter { selection.contains($0.id) }
        // Tags first, files second: both act on the pre-rename URL, and the
        // proposed names were already derived from the trimmed title, so
        // the resulting filenames are the same either way.
        let titlesCleaned = cleanTitleTag ? await cleanTitleTags(of: selected) : 0
        let outcomes = await scanner.renameFiles(selected)

        var newErrors: [URL: String] = [:]
        var succeededCount = 0
        var failedCount = 0
        for outcome in outcomes {
            if outcome.succeeded {
                succeededCount += 1
            } else {
                failedCount += 1
                newErrors[outcome.originalURL] = outcome.errorDescription
            }
        }
        errorsByURL = newErrors

        let succeededURLs = Set(outcomes.filter(\.succeeded).map(\.originalURL))
        proposals.removeAll { succeededURLs.contains($0.id) }
        selection.subtract(succeededURLs)

        let renamed = failedCount == 0
            ? "Renamed \(pluralized(succeededCount, "file"))."
            : "Renamed \(succeededCount), \(failedCount) failed."
        lastRunSummary = titlesCleaned == 0
            ? renamed
            : renamed + " Cleaned \(pluralized(titlesCleaned, "Title tag"))."
    }

    /// Writes the trimmed Title back to every selected file that needs it.
    /// A failure here is deliberately not surfaced per row: the rename is
    /// the action the user asked for, and it still runs.
    private func cleanTitleTags(of selected: [RenameProposal]) async -> Int {
        var cleaned = 0
        for proposal in selected {
            guard let title = RenamePlanner.cleanedTitleTag(for: proposal.file) else { continue }
            var changes = TagChanges()
            changes.title = title
            changes.replacing = [.title]
            do {
                _ = try await scanner.applyTagChanges(
                    changes, to: proposal.file, backupFirst: backupOriginalsBeforeWriting)
                cleaned += 1
            } catch {
                continue
            }
        }
        return cleaned
    }

    private func undo() async {
        isBusy = true
        defer { isBusy = false }

        let outcomes = await scanner.undoLastFileOperation()
        let failedCount = outcomes.count(where: { !$0.succeeded })
        lastRunSummary = failedCount == 0
            ? "Undid \(pluralized(outcomes.count, "rename"))."
            : "Undid \(outcomes.count - failedCount), \(failedCount) failed."
        rebuildPlan()
    }
}
