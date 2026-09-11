//
//  CollectSheetView.swift
//  CleanMyDigital
//

import SwiftUI

struct CollectSheetView: View {
    let scanner: LibraryScanner

    @State private var proposals: [CollectionProposal] = []
    @State private var selection: Set<URL> = []
    @State private var isBusy = false
    @State private var errorsByURL: [URL: String] = [:]
    @State private var lastRunSummary: String?

    var body: some View {
        SheetWindowContainer(
            title: "Collect into Folders",
            subtitle: "Groups each Singles track's different mixes into a subfolder named after the release, using the Title tag.",
            windowID: "collect-into-folders"
        ) {
            content
        } footer: {
            footer
        }
        .onAppear { rebuildPlan() }
    }

    @ViewBuilder
    private var content: some View {
        if proposals.isEmpty {
            ContentUnavailableView {
                Label("Nothing to Collect", systemImage: "checkmark.circle")
            } description: {
                Text("Every Singles file is already inside a folder matching its release name, or is missing a Title tag.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            table
        }
    }

    private var table: some View {
        Table(proposals) {
            TableColumn("") { proposal in
                Toggle("", isOn: selectionBinding(for: proposal.id))
                    .labelsHidden()
            }
            .width(24)

            TableColumn("File") { proposal in
                Text(proposal.file.fileName).lineLimit(1).help(proposal.file.fileName)
            }

            TableColumn("New Location") { proposal in
                VStack(alignment: .leading, spacing: 2) {
                    Text(proposal.proposedRelativePath).lineLimit(1).help(proposal.proposedRelativePath)
                    if let error = errorsByURL[proposal.id] {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.red)
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
            }
            Spacer()
            if scanner.canUndoLastFileOperation {
                Button("Undo Last Change") { Task { await undo() } }
                    .disabled(isBusy)
            }
            Button("Collect Selected") { Task { await collect() } }
                .buttonStyle(.borderedProminent)
                .disabled(selection.isEmpty || isBusy)
        }
        .padding()
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
        proposals = CollectionPlanner.plan(for: scanner.files)
        selection = Set(proposals.map(\.id))
        errorsByURL = [:]
    }

    private func collect() async {
        isBusy = true
        defer { isBusy = false }

        let selected = proposals.filter { selection.contains($0.id) }
        let outcomes = await scanner.collectIntoFolders(selected)

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

        lastRunSummary = failedCount == 0
            ? "Moved \(pluralized(succeededCount, "file"))."
            : "Moved \(succeededCount), \(failedCount) failed."
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
