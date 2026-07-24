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

        Settings {
            SettingsView()
        }
    }
}
