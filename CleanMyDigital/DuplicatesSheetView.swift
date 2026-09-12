//
//  DuplicatesSheetView.swift
//  CleanMyDigital
//

import SwiftUI

struct DuplicatesSheetView: View {
    let scanner: LibraryScanner

    @State private var groups: [DuplicateGroup] = []
    @State private var selection: Set<URL> = []
    @State private var isBusy = false
    @State private var errorsByURL: [URL: String] = [:]
    @State private var lastRunSummary: String?

    var body: some View {
        // .wide — this table's five trailing numeric columns (extension,
        // bitrate, cutoff, size) genuinely need more room than the other
        // windows' simpler two-column lists.
        SheetWindowContainer(
            title: "Find Duplicates",
            subtitle: "Groups files sharing the same Artist and Title. The highest real quality — Cutoff first, then Bitrate — is kept; the rest are candidates to move aside.",
            windowID: "find-duplicates",
            size: .wide
        ) {
            content
        } footer: {
            footer
        }
        .onAppear { rebuildPlan() }
    }

    @ViewBuilder
    private var content: some View {
        if groups.isEmpty {
            ContentUnavailableView {
                Label("No Duplicates Found", systemImage: "checkmark.circle")
            } description: {
                Text("No two files share the same Artist and Title tags.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(groups) { group in
                    Section {
                        fileRow(group.keeper, isKeeper: true)
                        ForEach(group.extras) { file in
                            fileRow(file, isKeeper: false)
                        }
                    } header: {
                        Text("\(group.keeper.artist ?? "") – \(group.keeper.title ?? "")")
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    private func fileRow(_ file: AudioFile, isKeeper: Bool) -> some View {
        HStack(spacing: 8) {
            if isKeeper {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .frame(width: 20)
                    .help("Recommended to keep")
                    .accessibilityLabel("Recommended to keep")
            } else {
                Toggle("", isOn: selectionBinding(for: file.url))
                    .labelsHidden()
                    .frame(width: 20)
                    .accessibilityLabel("Select \(file.fileName)")
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(file.fileName).lineLimit(1)
                if let error = errorsByURL[file.url] {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }
            Spacer()
            Text(file.fileExtension.uppercased())
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
            Text(file.formattedBitrate)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .trailing)
            Text(cutoffText(for: file))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .trailing)
            Text(file.formattedSize)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }

    private func cutoffText(for file: AudioFile) -> String {
        if case .measured(let hz) = scanner.spectralResults[file.url] {
            return String(format: "%.1f kHz", hz / 1000)
        }
        return "–"
    }

    private var footer: some View {
        HStack {
            Text("\(selection.count) of \(totalExtrasCount) selected")
                .font(.callout)
                .foregroundStyle(.secondary)
            if let lastRunSummary {
                Text(lastRunSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if scanner.canUndoLastFileOperation {
                Button("Undo Last Change") { Task { await undo() } }
                    .disabled(isBusy)
            }
            Button("Move Selected to Review Folder") { Task { await moveSelected() } }
                .buttonStyle(.borderedProminent)
                .disabled(selection.isEmpty || isBusy)
        }
        .padding()
    }

    private var totalExtrasCount: Int {
        groups.reduce(0) { $0 + $1.extras.count }
    }

    private func selectionBinding(for url: URL) -> Binding<Bool> {
        Binding(
            get: { selection.contains(url) },
            set: { isOn in
                if isOn { selection.insert(url) } else { selection.remove(url) }
            }
        )
    }

    private func rebuildPlan() {
        var cutoffHz: [URL: Double] = [:]
        for (url, outcome) in scanner.spectralResults {
            if case .measured(let hz) = outcome { cutoffHz[url] = hz }
        }
        groups = DuplicatePlanner.groups(for: scanner.files, cutoffHz: cutoffHz)
        selection = Set(groups.flatMap { $0.extras.map(\.url) })
        errorsByURL = [:]
    }

    private func moveSelected() async {
        isBusy = true
        defer { isBusy = false }
        guard scanner.hasScannedFolder else { return }

        let allProposals = DuplicatePlanner.plan(for: groups, roots: scanner.scannedFolders)
        let selected = allProposals.filter { selection.contains($0.file.url) }
        let outcomes = await scanner.moveDuplicates(selected)

        let failedOutcomes = outcomes.filter { !$0.succeeded }
        errorsByURL = Dictionary(
            uniqueKeysWithValues: failedOutcomes.map { ($0.originalURL, $0.errorDescription ?? "Failed") })

        let succeededCount = outcomes.count - failedOutcomes.count
        lastRunSummary = failedOutcomes.isEmpty
            ? "Moved \(pluralized(succeededCount, "file"))."
            : "Moved \(succeededCount), \(failedOutcomes.count) failed."

        rebuildPlan()
    }

    private func undo() async {
        isBusy = true
        defer { isBusy = false }

        let outcomes = await scanner.undoLastFileOperation()
        let failedCount = outcomes.count(where: { !$0.succeeded })
        lastRunSummary = failedCount == 0
            ? "Undid \(pluralized(outcomes.count, "change"))."
            : "Undid \(outcomes.count - failedCount), \(failedCount) failed."
        rebuildPlan()
    }
}
