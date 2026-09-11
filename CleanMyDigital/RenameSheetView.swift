//
//  RenameSheetView.swift
//  CleanMyDigital
//

import SwiftUI

struct RenameSheetView: View {
    let scanner: LibraryScanner

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

    @ViewBuilder
    private var content: some View {
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

    private var table: some View {
        Table(proposals) {
            TableColumn("") { proposal in
                Toggle("", isOn: selectionBinding(for: proposal.id))
                    .labelsHidden()
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
            if scanner.canUndoLastFileOperation {
                Button("Undo Last Change") { Task { await undo() } }
                    .disabled(isBusy)
            }
            Button("Rename Selected") { Task { await rename() } }
                .buttonStyle(.borderedProminent)
                .disabled(selection.isEmpty || isBusy)
        }
        .padding()
        // Appears once a rename/undo batch finishes — a fade reads as
        // "done", an instant pop reads as a layout glitch.
        .animation(.easeOut(duration: 0.2), value: lastRunSummary)
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

        lastRunSummary = failedCount == 0
            ? "Renamed \(pluralized(succeededCount, "file"))."
            : "Renamed \(succeededCount), \(failedCount) failed."
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
