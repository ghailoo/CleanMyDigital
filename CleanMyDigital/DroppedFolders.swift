//
//  DroppedFolders.swift
//  CleanMyDigital
//

import Foundation

/// Turns the URLs from a drop onto the window into the roots to scan.
///
/// Dropping a folder scans that folder; dropping audio files scans the
/// folder they sit in, since a scan is always rooted at a folder. Anything
/// else (a PDF, a disk image) is ignored rather than scanned by accident.
enum DroppedFolders {
    struct Resolution: Equatable {
        var roots: [URL] = []
        /// Folders beyond the first that the category can't take — Albums
        /// and Compilations read meaning from one root's own structure, so
        /// only Singles scan several at once (same rule as the folder picker).
        var ignoredFolders: [URL] = []
        /// Dropped items that aren't folders or audio files.
        var rejectedCount = 0

        var isEmpty: Bool { roots.isEmpty }

        /// What to tell the user about anything the drop couldn't use —
        /// nil when everything dropped is being scanned.
        func summary(category: LibraryCategory) -> String? {
            var notes: [String] = []
            if !ignoredFolders.isEmpty, let scanned = roots.first {
                notes.append("\(category.rawValue) scan one folder at a time, so only “\(scanned.lastPathComponent)” was scanned — \(pluralized(ignoredFolders.count, "other folder")) ignored.")
            }
            if rejectedCount > 0 {
                notes.append("Ignored \(pluralized(rejectedCount, "dropped item")): not a folder or audio file.")
            }
            return notes.isEmpty ? nil : notes.joined(separator: " ")
        }
    }

    static func isAudioFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return LibraryScanner.supportedExtensions.contains(ext)
            || LibraryScanner.nativeOnlyExtensions.contains(ext)
    }

    /// `isDirectory` is injected so this stays testable without touching
    /// disk; the default asks the filesystem rather than trusting the URL's
    /// trailing slash, which a dropped URL doesn't reliably carry.
    static func resolve(
        _ urls: [URL],
        category: LibraryCategory,
        isDirectory: (URL) -> Bool = {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
    ) -> Resolution {
        var resolution = Resolution()
        var seen = Set<String>()

        for url in urls {
            let folder: URL
            if isDirectory(url) {
                folder = url
            } else if isAudioFile(url) {
                folder = url.deletingLastPathComponent()
            } else {
                resolution.rejectedCount += 1
                continue
            }

            // Compared by path, not by URL: `deletingLastPathComponent()`
            // leaves a trailing slash that a dropped folder's own URL lacks,
            // so the two URLs differ while naming one folder.
            guard seen.insert(folder.standardizedFileURL.path).inserted else { continue }

            if resolution.roots.isEmpty || category.allowsMultipleFolders {
                resolution.roots.append(folder)
            } else {
                resolution.ignoredFolders.append(folder)
            }
        }
        return resolution
    }
}
