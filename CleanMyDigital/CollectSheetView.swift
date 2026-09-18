//
//  CollectSheetView.swift
//  CleanMyDigital
//

import SwiftUI

struct CollectSheetView: View {
    let scanner: LibraryScanner

    @State private var plans: [ArtistCollectionPlan] = []
    @State private var selectedArtists: Set<URL> = []
    @State private var isBusy = false
    @State private var errorsByURL: [URL: String] = [:]
    @State private var lastRunSummary: String?

    private var proposalCount: Int { plans.reduce(0) { $0 + $1.proposals.count } }
    private var selectedProposalCount: Int {
        plans.filter { selectedArtists.contains($0.artistRoot) }.reduce(0) { $0 + $1.proposals.count }
    }

    var body: some View {
        SheetWindowContainer(
            title: "Collect into Folders",
            subtitle: "Organizes each artist's Singles into Song Title/Pressing subfolders, using the Title tag.",
            windowID: "collect-into-folders"
        ) {
            content
        } footer: {
            footer
        }
        .onAppear { rebuildPlan() }
    }

    private var content: some View {
        Group {
            if plans.isEmpty {
                ContentUnavailableView {
                    Label("Nothing to Collect", systemImage: "checkmark.circle")
                } description: {
                    Text("Every Singles folder is already organized, or its tracks are missing a Title tag.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                list
            }
        }
        .consistentAnimation(plans.isEmpty)
    }

    private var list: some View {
        List {
            ForEach(plans) { plan in
                Section {
                    ForEach(plan.proposals) { proposal in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text(proposal.file.fileName).lineLimit(1)
                                Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.secondary)
                                Text(proposal.proposedRelativePath).lineLimit(1).foregroundStyle(.secondary)
                            }
                            .help("\(proposal.file.fileName) → \(proposal.proposedRelativePath)")

                            if proposal.hasOddExtension {
                                Label("Unusual file extension — check this file", systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                            if let error = errorsByURL[proposal.id] {
                                Label(error, systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                } header: {
                    Toggle(isOn: artistSelectionBinding(for: plan.artistRoot)) {
                        Text(plan.artistFolderName)
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("\(selectedProposalCount) of \(proposalCount) selected")
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
            Button("Collect Selected") { Task { await collect() } }
                .buttonStyle(.borderedProminent)
                .disabled(selectedArtists.isEmpty || isBusy)
        }
        .padding()
        // Appears once a collect/undo batch finishes — same reasoning as
        // RenameSheetView's footer.
        .consistentAnimation(lastRunSummary)
    }

    private func artistSelectionBinding(for artistRoot: URL) -> Binding<Bool> {
        Binding(
            get: { selectedArtists.contains(artistRoot) },
            set: { isOn in
                if isOn { selectedArtists.insert(artistRoot) } else { selectedArtists.remove(artistRoot) }
            }
        )
    }

    private func rebuildPlan() {
        plans = CollectionPlanner.plan(for: scanner.files)
        selectedArtists = Set(plans.map(\.artistRoot))
        errorsByURL = [:]
    }

    private func collect() async {
        isBusy = true
        defer { isBusy = false }

        let selectedPlans = plans.filter { selectedArtists.contains($0.artistRoot) }
        let outcomes = await scanner.collectIntoFolders(selectedPlans)

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

        lastRunSummary = failedCount == 0
            ? "Moved \(pluralized(succeededCount, "file"))."
            : "Moved \(succeededCount), \(failedCount) failed."

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
