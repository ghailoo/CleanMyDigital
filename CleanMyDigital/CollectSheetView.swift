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
    /// First-level folders that are artist folders, not releases — the
    /// scanned folder is a library root rather than one artist's folder.
    /// Collecting skips those entirely, so without this the window would
    /// just look empty for no stated reason.
    @State private var artistFolders: [String] = []
    /// Singles with no genre tag, which collecting by Genre leaves where
    /// they are — reported so they aren't silently skipped.
    @State private var withoutGenre: Int = 0

    /// Which scheme the top level of the collected layout uses. Remembered
    /// between launches, since whichever one you organize by is the one
    /// you'll keep organizing by.
    @AppStorage("collectGrouping") private var groupingRaw = CollectionPlanner.Grouping.artist.rawValue

    /// Albums and Compilations only have the Genre scheme — the artist one
    /// reads the first folder level as one single's pressings, which is
    /// meaningless for a release folder. Forced rather than merely
    /// disabled, so a stored "Artist" choice from a Singles session can't
    /// leak into an Albums scan.
    private var grouping: CollectionPlanner.Grouping {
        guard scannedCategory == .singles else { return .genre }
        return CollectionPlanner.Grouping(rawValue: groupingRaw) ?? .artist
    }

    private var canChooseGrouping: Bool { scannedCategory == .singles }

    /// The category this scan was run as. `LibraryScanner.category` is nil
    /// before the first scan; Singles is the harmless default, since an
    /// unscanned window has nothing to plan either way.
    private var scannedCategory: LibraryCategory { scanner.category ?? .singles }

    private var proposalCount: Int { plans.reduce(0) { $0 + $1.proposals.count } }
    private var selectedProposalCount: Int {
        plans.filter { selectedArtists.contains($0.artistRoot) }.reduce(0) { $0 + $1.proposals.count }
    }

    var body: some View {
        SheetWindowContainer(
            title: "Collect into Folders",
            subtitle: Self.subtitle(for: grouping, category: scannedCategory),
            windowID: "collect-into-folders"
        ) {
            content
        } footer: {
            footer
        }
        .onAppear { rebuildPlan() }
    }

    static func subtitle(
        for grouping: CollectionPlanner.Grouping, category: LibraryCategory
    ) -> String {
        guard grouping == .genre else {
            return "Organizes each artist's Singles into Song Title/Pressing subfolders, using the Title tag."
        }
        let layout = switch category {
        case .singles: "one flat folder per genre"
        case .albums: "Genre/Artist/Album folders, moving each album whole"
        case .compilations: "Genre folders, moving each compilation whole"
        }
        return "Moves \(category.rawValue) into \(layout), using the last value of the Genre tag."
    }

    private var content: some View {
        Group {
            if grouping == .artist, !artistFolders.isEmpty, plans.isEmpty {
                ContentUnavailableView {
                    Label("That Looks Like a Library Folder", systemImage: "folder.badge.questionmark")
                } description: {
                    Text("""
                        \(artistFolders.prefix(3).joined(separator: ", "))\
                        \(artistFolders.count > 3 ? " and \(artistFolders.count - 3) more" : "") \
                        \(artistFolders.count == 1 ? "is an artist's own folder" : "are artists' own folders"), \
                        not releases. Collecting organizes the inside of one artist's folder, so choose the \
                        artist folders themselves — you can select them all at once in Choose Folder…
                        """)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if plans.isEmpty {
                ContentUnavailableView {
                    Label("Nothing to Collect", systemImage: "checkmark.circle")
                } description: {
                    Text(grouping == .artist
                         ? "Every Singles folder is already organized, or its tracks are missing a Title tag."
                         : "Everything is already in its genre's folder, or nothing has a Genre tag. Run Find Metadata first to fill the genres in.")
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
            if canChooseGrouping {
                Picker("Collect by", selection: $groupingRaw) {
                    ForEach(CollectionPlanner.Grouping.allCases) { option in
                        Text(option.rawValue).tag(option.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .disabled(isBusy)
                .help("Artist builds Artist/Song/Pressing folders. Genre moves tracks into one flat folder per genre.")
                .onChange(of: groupingRaw) { rebuildPlan() }
            }

            Text("\(selectedProposalCount) of \(proposalCount) selected")
                .font(.callout)
                .foregroundStyle(.secondary)
            if grouping == .genre, withoutGenre > 0 {
                Text("\(withoutGenre) with no Genre tag staying put")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let lastRunSummary {
                Text(lastRunSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
            Spacer()
            if scanner.canUndoLastFileOperation {
                Button("Undo Last Change") { Task { await undo() } }
                    .accessibilityHint("Reverts the most recent rename, move, or collect")
                    .disabled(isBusy)
            }
            if isBusy { ProgressView().controlSize(.small) }
            Button("Collect Selected") { Task { await collect() } }
                .accessibilityHint(grouping == .artist
                                   ? "Moves the selected artists' loose files into per-release folders"
                                   : "Moves the selected genres' tracks into one folder per genre")
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
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
        plans = CollectionPlanner.plan(
            for: scanner.files, grouping: grouping, roots: scanner.scannedFolders)
        artistFolders = CollectionPlanner.artistFoldersMistakenForReleases(in: scanner.files)
        withoutGenre = CollectionPlanner.filesWithoutAGenre(in: scanner.files).count
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
