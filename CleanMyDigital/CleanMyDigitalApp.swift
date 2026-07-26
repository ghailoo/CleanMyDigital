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

        Settings {
            SettingsView()
        }
    }
}
