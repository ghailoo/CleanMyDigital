//
//  MaxiTracksSheetView.swift
//  CleanMyDigital
//

import SwiftUI

struct MaxiTracksSheetView: View {
    let scanner: LibraryScanner

    @AppStorage("backupOriginalsBeforeWriting") private var backupFirst = true
    @State private var proposals: [MaxiTrackProposal] = []
    @State private var selection: Set<URL> = []
    @State private var isBusy = false
    @State private var errorsByURL: [URL: String] = [:]
    @State private var lastRunSummary: String?

    var body: some View {
        SheetWindowContainer(
            title: "Tag Maxi Tracks",
            subtitle: "Writes \"\(MaxiTrackPlanner.groupingValue)\" into the Grouping tag of long tracks. Remixes, dubs and extended versions are ticked for you; radio edits and originals are left out.",
            windowID: "tag-maxi-tracks"
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
                    Label("No Maxi Tracks", systemImage: "timer")
                } description: {
                    Text("Nothing here runs past four minutes, or everything that does is already grouped.")
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
                    .accessibilityLabel("Select \(proposal.file.fileName)")
            }
            .width(24)

            TableColumn("File") { proposal in
                VStack(alignment: .leading, spacing: 2) {
                    Text(proposal.file.fileName).lineLimit(1).help(proposal.file.fileName)
                    if let error = errorsByURL[proposal.id] {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }
            }

            TableColumn("Length") { proposal in
                Text(proposal.file.formattedDuration).monospacedDigit()
            }
            .width(70)

            TableColumn("Confidence") { proposal in
                certaintyBadge(proposal.certainty)
            }
            .width(120)
        }
    }

    /// Green when the name backs the length up, yellow when only the clock
    /// says so — the yellows are the ones worth reading before applying.
    private func certaintyBadge(_ certainty: MaxiTrackCertainty) -> some View {
        let agrees = certainty == .nameAgrees
        return Label {
            Text(certainty.label)
        } icon: {
            Image(systemName: agrees ? "checkmark.circle.fill" : "questionmark.circle.fill")
        }
        .font(.caption)
        .foregroundStyle(agrees ? .green : .orange)
        .help(agrees
              ? "Longer than four minutes, and the name says so — a remix, dub or extended version"
              : "Longer than four minutes, but the name doesn't say either way")
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
            if isBusy { ProgressView().controlSize(.small) }
            Button("Tag Selected") { Task { await apply() } }
                .accessibilityHint("Writes the Maxi Track grouping tag into the selected files")
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(selection.isEmpty || isBusy)
                .help(backupFirst
                      ? "Writes the tag — originals are backed up first"
                      : "Writes the tag")
        }
        .padding()
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

    /// Only the ones whose name agrees start selected; a file that's merely
    /// long is left for the user to tick, same rule as an uncertain match in
    /// Apply Found Matches.
    private func rebuildPlan() {
        proposals = MaxiTrackPlanner.plan(for: scanner.files)
        selection = Set(proposals.filter { $0.certainty == .nameAgrees }.map(\.id))
        errorsByURL = [:]
    }

    private func apply() async {
        isBusy = true
        defer { isBusy = false }

        let selected = proposals.filter { selection.contains($0.id) }
        let outcomes = await scanner.tagMaxiTracks(selected, backupFirst: backupFirst)

        var newErrors: [URL: String] = [:]
        var taggedCount = 0
        for outcome in outcomes {
            if outcome.succeeded {
                taggedCount += 1
            } else {
                newErrors[outcome.originalURL] = outcome.errorDescription
            }
        }
        errorsByURL = newErrors

        let taggedURLs = Set(outcomes.filter(\.succeeded).map(\.originalURL))
        proposals.removeAll { taggedURLs.contains($0.id) }
        selection.subtract(taggedURLs)

        let failedCount = outcomes.count - taggedCount
        lastRunSummary = failedCount == 0
            ? "Tagged \(pluralized(taggedCount, "file"))."
            : "Tagged \(taggedCount), \(failedCount) failed."
    }
}
