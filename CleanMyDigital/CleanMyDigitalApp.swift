//
//  CleanMyDigitalApp.swift
//  CleanMyDigital
//
//  Created by Ghailen Ben Othman on 09/07/2026.
//

import SwiftUI

@main
struct CleanMyDigitalApp: App {
    @State private var scanner = LibraryScanner()

    var body: some Scene {
        WindowGroup {
            ContentView(scanner: scanner)
        }
        .windowResizability(.contentMinSize)
        .commands { LibraryCommands() }

        WindowGroup("Rename Files", id: "rename-files") {
            RenameSheetView(scanner: scanner)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 760, height: 520)

        WindowGroup("Collect into Folders", id: "collect-into-folders") {
            CollectSheetView(scanner: scanner)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 760, height: 520)

        WindowGroup("Find Duplicates", id: "find-duplicates") {
            DuplicatesSheetView(scanner: scanner)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 820, height: 560)

        WindowGroup("Check Album Completeness", id: "check-album-completeness") {
            AlbumCompletenessSheetView(scanner: scanner)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 760, height: 520)

        WindowGroup("Tag Maxi Tracks", id: "tag-maxi-tracks") {
            MaxiTracksSheetView(scanner: scanner)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 760, height: 520)

        WindowGroup("Apply Found Matches", id: "apply-found-matches") {
            ApplyFoundMatchesSheetView(scanner: scanner)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 760, height: 520)

        Settings {
            SettingsView()
        }
    }
}

/// Menu-bar home for the main window's toolbar shortcuts, so ⌘O/⌘R/⌘I are
/// discoverable without hovering a toolbar button. The state stays in
/// `ContentView`, published per window via `.focusedSceneValue`.
extension FocusedValues {
    @Entry var chooseFolder: (() -> Void)?
    @Entry var rescan: (() -> Void)?
    @Entry var showInspector: Binding<Bool>?
}

struct LibraryCommands: Commands {
    @FocusedValue(\.chooseFolder) private var chooseFolder
    @FocusedValue(\.rescan) private var rescan
    @FocusedValue(\.showInspector) private var showInspector

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Choose Folder…") { chooseFolder?() }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(chooseFolder == nil)
            Button("Rescan") { rescan?() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(rescan == nil)
        }
        CommandGroup(after: .toolbar) {
            Button(showInspector?.wrappedValue == true ? "Hide Track Info" : "Show Track Info") {
                showInspector?.wrappedValue.toggle()
            }
            .keyboardShortcut("i", modifiers: .command)
            .disabled(showInspector == nil)
        }
    }
}
