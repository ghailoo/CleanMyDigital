//
//  LibraryScanner.swift
//  CleanMyDigital
//

import AppKit
import Foundation
import AVFoundation
import ImageIO
import Observation

/// The outcome of one attempted rename (forward or undo).
struct RenameOperationResult: Identifiable, Sendable {
    let id = UUID()
    let originalURL: URL
    let currentName: String
    let proposedName: String
    let errorDescription: String?

    var succeeded: Bool { errorDescription == nil }
}

@Observable
final class LibraryScanner {
    enum State: Equatable {
        case idle
        case enumerating
        case scanning
        case finished
    }

    private struct RenameLogEntry: Sendable {
        let oldURL: URL
        let newURL: URL
        /// True when this entry moved a whole album folder (see
        /// `renameAlbumFolders`) rather than a single file — `oldURL`/
        /// `newURL` are folder paths, so reversing it in
        /// `undoLastFileOperation` has to update every file whose parent
        /// matches, not look for one exact-URL match like the other entries.
        let isFolderMove: Bool
    }

    private(set) var state: State = .idle
    private(set) var files: [AudioFile] = []
    private(set) var scannedCount = 0
    private(set) var totalCount = 0
    /// Every root the current scan covers, in the order they were chosen.
    /// Usually one, but a Singles scan can take several artist folders at
    /// once — so anything deriving a path *relative to a root* (backups,
    /// duplicate moves, expected artist) has to resolve the file's own
    /// root with `root(containing:)` rather than assume a single one.
    private(set) var scannedFolders: [URL] = []

    /// The one scanned root, for the callers that genuinely only make
    /// sense with a single folder — the "treat this folder as the artist"
    /// rescan, and the subtitle's folder path. Nil when a scan covers
    /// several folders, which is the honest answer there rather than
    /// silently picking the first.
    var scannedFolder: URL? { scannedFolders.count == 1 ? scannedFolders[0] : nil }

    /// Whether anything has been scanned at all — what toolbar actions
    /// gate on, since they work fine across several roots and shouldn't
    /// disable themselves just because `scannedFolder` is nil.
    var hasScannedFolder: Bool { !scannedFolders.isEmpty }

    private(set) var category: LibraryCategory?
    /// A fixed artist name to use for every file instead of computing it
    /// from folder depth — set via `scan(folder:category:artistOverride:)`
    /// for the "treat this folder as the artist" scan mode. Nil means
    /// `expectedArtist(for:in:)`'s normal folder-depth calculation applies.
    private(set) var artistOverride: String?

    /// True when the current `artistOverride` was set automatically by
    /// `scan(folder:category:artistOverride:)`'s own detection (see
    /// `detectArtistFolderOverride`) rather than by the caller passing one
    /// explicitly — i.e. the user never clicked "Treat This Folder as the
    /// Artist" or the banner's fix button for this scan. `ContentView` uses
    /// this to show a passive "here's what I detected" confirmation instead
    /// of nothing, while still only showing the reactive mismatch banner
    /// for cases detection didn't resolve. Always false when `artistOverride`
    /// is nil, and reset to false at the start of every scan.
    private(set) var artistOverrideAutoDetected = false

    /// Batch "Find All Metadata" results, keyed by file URL. Session-only —
    /// cleared whenever a new scan starts.
    private(set) var lookupResults: [URL: LookupOutcome] = [:]
    private(set) var isLookingUp = false
    private(set) var lookupCompletedCount = 0
    private(set) var lookupTotalCount = 0

    private var lookupTask: Task<Void, Never>?

    /// Batch "Check for Transcodes" results, keyed by file URL. Session-only
    /// — cleared whenever a new scan starts.
    private(set) var spectralResults: [URL: SpectralCutoffOutcome] = [:]
    private(set) var isAnalyzingSpectrum = false
    private(set) var spectralCompletedCount = 0
    private(set) var spectralTotalCount = 0

    private var spectralTask: Task<Void, Never>?

    /// Online (Discogs) completeness confirmations, keyed by album folder
    /// URL. Set via `recordAlbumCompletenessResult(_:for:)` once a
    /// release's tracklist has been compared against an album's local
    /// files, so `AlbumCompletenessSheetView` can show a confirmed result
    /// instead of "Unknown locally" forever.
    ///
    /// Unlike `lookupResults`/`spectralResults`, this deliberately
    /// survives across scans/rescans instead of being reset in `scan()` —
    /// it's a folder-level confirmation ("did I already check this album
    /// against Discogs"), not a per-file reading that could go stale the
    /// instant a file's tags change. Rescanning a large, otherwise-unchanged
    /// discography (e.g. just to pick up one tag fix) shouldn't force every
    /// other album's prior confirmation back to "Unknown locally." If an
    /// album genuinely does change after being confirmed, that's still
    /// correctable without any separate invalidation logic: revisiting
    /// "Check on Discogs" and running Apply again for that one album
    /// overwrites its stored result, since `recordAlbumCompletenessResult`
    /// already runs unconditionally at the end of `applyToAlbum()`, even
    /// when nothing new needed writing. Not cleared by `scan()` for that
    /// reason — but `reset()` *does* clear it, since that's used for a
    /// wholesale category change (a completely different scan context, not
    /// a rescan of the same folder) rather than quitting the app.
    private(set) var albumCompletenessResults: [URL: AlbumCompletenessOnlineResult] = [:]

    /// The most recent batch of file moves, oldest first — renames,
    /// "Collect into Folders" moves, duplicate moves, and album-folder
    /// renames all share this same slot, since every one of them is just a
    /// `FileManager.moveItem` under the hood (see `RenameLogEntry.isFolderMove`
    /// for how a folder-level entry differs from a single-file one when
    /// reversed). Session-only, cleared on a new scan. Powers "Undo Last
    /// Change".
    private var lastRenameBatch: [RenameLogEntry] = []
    var canUndoLastFileOperation: Bool { !lastRenameBatch.isEmpty }

    /// File extensions AVFoundation can read metadata from.
    nonisolated static let supportedExtensions: Set<String> = [
        "mp3", "m4a", "m4b", "m4p", "aac", "flac", "wav", "wave",
        "aif", "aiff", "aifc", "caf", "mp4", "alac", "ac3", "eac3",
    ]

    /// Formats with their own full native reader and writer, read entirely
    /// independently of AVFoundation — unlike `supportedExtensions`'
    /// native readers (FLAC/WAV/AIFF), which only supplement whatever
    /// AVFoundation already found, these have nothing to supplement:
    /// AVFoundation cannot open them at all (confirmed empirically for
    /// both DSF and WavPack — every `AVURLAsset.load()` call throws
    /// `AVFoundationErrorDomain` code -11828, "file format not
    /// recognized", not just for unusual files).
    nonisolated static let nativeOnlyExtensions: Set<String> = [
        "dsf", "wv",
    ]

    /// Audio formats we recognize but can't read at all yet —
    /// reported as unreadable so they still get flagged.
    ///
    /// `.ape` (Monkey's Audio) uses the same APEv2 tag format as WavPack
    /// (see `APEv2Tag.swift`, written format-agnostic for exactly this
    /// reason) — adding it here would mostly be container work (locating
    /// where its audio ends), not another tag parser.
    nonisolated static let unsupportedAudioExtensions: Set<String> = [
        "ogg", "oga", "opus", "wma", "ape", "mpc", "dff",
    ]

    var progress: Double {
        totalCount > 0 ? Double(scannedCount) / Double(totalCount) : 0
    }

    /// The scanned root `fileURL` came from. Backups, duplicate moves and
    /// expected-artist derivation are all defined relative to a root, and
    /// once several folders can be scanned together there's no single
    /// "the scanned folder" to measure against — each file has to be
    /// resolved to the one it actually came from.
    ///
    /// Picks the *longest* matching root, so selecting both a parent
    /// folder and something inside it resolves each file to its nearest
    /// enclosing root rather than whichever happened to be chosen first.
    func root(containing fileURL: URL) -> URL? {
        let fileComponents = fileURL.standardizedFileURL.pathComponents
        return scannedFolders
            .filter { root in
                let rootComponents = root.standardizedFileURL.pathComponents
                return fileComponents.count > rootComponents.count
                    && Array(fileComponents.prefix(rootComponents.count)) == rootComponents
            }
            .max { $0.standardizedFileURL.pathComponents.count < $1.standardizedFileURL.pathComponents.count }
    }

    /// Starts security-scoped access on every scanned root, returning the
    /// ones it acquired so the caller can release them. `fileImporter`
    /// scopes each selected folder separately, so a multi-folder scan
    /// holds one grant per folder and a write has to re-acquire all of
    /// them — taking only the first would let files in that folder write
    /// while every other folder failed.
    ///
    /// Returns nil if any root is unavailable, after releasing whatever
    /// it already took: a partial grant is worse than none, since it
    /// would half-apply a batch and report the rest as missing files.
    private func beginAccessToAllRoots() -> [URL]? {
        guard !scannedFolders.isEmpty else { return nil }
        var accessed: [URL] = []
        for root in scannedFolders {
            guard root.startAccessingSecurityScopedResource() else {
                for url in accessed { url.stopAccessingSecurityScopedResource() }
                return nil
            }
            accessed.append(root)
        }
        return accessed
    }

    private func endAccess(_ roots: [URL]) {
        for url in roots { url.stopAccessingSecurityScopedResource() }
    }

    /// Distinct expected-artist folder names among the current scan's
    /// files, in first-seen order.
    private var distinctExpectedArtists: [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for file in files {
            guard let expectedArtist = file.expectedArtist, seen.insert(expectedArtist).inserted else { continue }
            ordered.append(expectedArtist)
        }
        return ordered
    }

    /// True when at least one distinct expected-artist folder name in this
    /// Albums scan looks like an album name rather than an artist name
    /// (see `AudioFile.looksLikeAlbumFolderName`) — usually means the
    /// scanned folder was an artist's own album folder, scanned directly
    /// instead of its parent, so every file's `expectedArtist` came out as
    /// the album name instead of the real artist. Always false once
    /// `artistOverride` is set — the user has explicitly confirmed intent,
    /// so there's nothing left to warn about.
    var possibleArtistFolderMismatch: Bool {
        guard artistOverride == nil else { return false }
        return category == .albums && distinctExpectedArtists.contains { AudioFile.looksLikeAlbumFolderName($0) }
    }

    /// The first expected-artist folder name that triggered
    /// `possibleArtistFolderMismatch`, for the results banner's example
    /// text. Nil whenever that flag is false.
    var misrootedArtistFolderExample: String? {
        guard artistOverride == nil, category == .albums else { return nil }
        return distinctExpectedArtists.first { AudioFile.looksLikeAlbumFolderName($0) }
    }

    /// Scans `folder` for audio files. `artistOverride`, when non-nil and
    /// `category == .albums`, is used as every file's `expectedArtist`
    /// instead of the usual folder-depth calculation — for scanning an
    /// artist's own folder directly (`ArtistFolder/AlbumName/Track.ext`)
    /// rather than a parent folder containing multiple artist folders.
    ///
    /// When the caller passes `artistOverride: nil` (the normal case) and
    /// `category == .albums`, this also tries to detect that same situation
    /// on its own — see `detectArtistFolderOverride` — and applies it
    /// automatically, setting `artistOverrideAutoDetected` so callers can
    /// tell an automatic override apart from an explicitly requested one.
    /// An explicitly passed override always wins outright; detection only
    /// ever runs to fill in a nil.
    func scan(folder: URL, category: LibraryCategory, artistOverride: String? = nil) async {
        await scan(folders: [folder], category: category, artistOverride: artistOverride)
    }

    /// Scans several roots as one library — Singles can be spread across
    /// a folder per artist, and scanning their common parent instead
    /// would mean walking everything else under it too.
    ///
    /// Each file keeps the root it came from (see `root(containing:)`),
    /// so backups and duplicate moves land beside the file rather than
    /// all being forced under whichever folder happened to be first.
    ///
    /// `artistOverride` and its auto-detection stay single-folder only:
    /// both answer "which folder is the artist's own folder", which has
    /// no single answer across several roots, and neither applies to
    /// Singles in the first place.
    func scan(folders: [URL], category: LibraryCategory, artistOverride: String? = nil) async {
        let accessed = folders.filter { $0.startAccessingSecurityScopedResource() }
        defer { endAccess(accessed) }

        state = .enumerating
        files = []
        scannedCount = 0
        totalCount = 0
        scannedFolders = folders
        self.category = category
        self.artistOverride = artistOverride
        artistOverrideAutoDetected = false

        lookupTask?.cancel()
        lookupTask = nil
        lookupResults = [:]
        isLookingUp = false
        lookupCompletedCount = 0
        lookupTotalCount = 0

        spectralTask?.cancel()
        spectralTask = nil
        spectralResults = [:]
        isAnalyzingSpectrum = false
        spectralCompletedCount = 0
        spectralTotalCount = 0

        lastRenameBatch = []

        // Enumerated per root, keeping each file paired with the folder it
        // came from — `expectedArtist` is measured relative to that root,
        // so a multi-folder scan can't share one.
        let roots = folders
        let found = await Task.detached(priority: .userInitiated) {
            roots.flatMap { root in
                Self.audioFileURLs(in: root).map { (url: $0, root: root) }
            }
        }.value

        totalCount = found.count

        // Only try to auto-detect when the caller didn't already tell us —
        // an explicit override (including a rescan forwarding the stored
        // one) always wins outright, nothing to detect. Detection answers
        // "was a single artist's own folder scanned directly", which a
        // multi-folder scan doesn't pose, so it's skipped there.
        var effectiveArtistOverride = artistOverride
        if artistOverride == nil, category == .albums, let folder = folders.first, folders.count == 1,
           let detected = Self.detectArtistFolderOverride(urls: found.map(\.url), folder: folder) {
            effectiveArtistOverride = detected
            self.artistOverride = detected
            artistOverrideAutoDetected = true
        }

        state = .scanning

        // Read metadata with bounded concurrency so huge libraries stay responsive.
        let maxConcurrent = 8
        var results: [AudioFile] = []
        results.reserveCapacity(found.count)

        await withTaskGroup(of: AudioFile.self) { group in
            var iterator = found.makeIterator()
            var inFlight = 0

            while inFlight < maxConcurrent, let next = iterator.next() {
                let url = next.url
                let expected = Self.expectedArtist(
                    for: url, in: next.root, override: effectiveArtistOverride, category: category)
                group.addTask { await Self.inspect(url, expectedArtist: expected, category: category) }
                inFlight += 1
            }
            for await file in group {
                results.append(file)
                scannedCount += 1
                if let next = iterator.next() {
                    let url = next.url
                    let expected = Self.expectedArtist(
                        for: url, in: next.root, override: effectiveArtistOverride, category: category)
                    group.addTask { await Self.inspect(url, expectedArtist: expected, category: category) }
                }
            }
        }

        files = results.sorted {
            $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending
        }
        state = .finished
    }

    /// Returns the scanner to a genuinely fresh, pre-scan state — used
    /// when the category picker changes, so a stale scan (read under the
    /// *old* category's rules — different missing-field checks, different
    /// artist-folder handling) can't keep showing on screen mislabeled as
    /// if it matched the newly chosen one.
    ///
    /// Clears everything `scan(folder:category:artistOverride:)`'s own
    /// opening lines clear, plus `albumCompletenessResults` — which
    /// normally survives a rescan of the *same* folder (see its own doc
    /// comment) but has no reason to survive a category change, since
    /// that's a wholesale switch to a different scan context, not a
    /// rescan. In-flight lookup/spectral work is cancelled outright rather
    /// than left to finish, since it would just be racing to write results
    /// against a scan that's being discarded.
    func reset() {
        state = .idle
        files = []
        scannedCount = 0
        totalCount = 0
        scannedFolders = []
        category = nil
        artistOverride = nil
        artistOverrideAutoDetected = false

        lookupTask?.cancel()
        lookupTask = nil
        lookupResults = [:]
        isLookingUp = false
        lookupCompletedCount = 0
        lookupTotalCount = 0

        spectralTask?.cancel()
        spectralTask = nil
        spectralResults = [:]
        isAnalyzingSpectrum = false
        spectralCompletedCount = 0
        spectralTotalCount = 0

        albumCompletenessResults = [:]

        lastRenameBatch = []
    }

    /// Writes `changes` to `file`'s tags, backing up the original first if
    /// requested, then re-reads the file and updates `files` in place so
    /// the table reflects the change immediately.
    ///
    /// A failed backup does *not* abort the write — refusing a metadata fix
    /// the user actually wants over an unrelated backup problem (e.g. a
    /// permission quirk creating a new folder on a network volume) is worse
    /// than writing without a backup and telling them so. Returns the
    /// backup failure, if any, instead of throwing it, so the caller can
    /// still tell "applied, but not backed up" apart from "applied
    /// cleanly." Nil means backup succeeded or wasn't requested. A thrown
    /// error is always the tag write itself failing.
    ///
    /// `scan(folder:)` releases its security-scoped access to the folder as
    /// soon as the scan finishes, so writes re-acquire it for the duration
    /// of the operation — access extends to the whole subtree the folder
    /// covers, including this file.
    @discardableResult
    func applyTagChanges(_ changes: TagChanges, to file: AudioFile, backupFirst: Bool) async throws -> TagWriteError? {
        guard let fileRoot = root(containing: file.url) else {
            throw TagWriteError.underlying(CocoaError(.fileNoSuchFile))
        }

        guard let accessed = beginAccessToAllRoots() else {
            throw TagWriteError.folderAccessUnavailable
        }
        defer { endAccess(accessed) }

        var backupFailure: TagWriteError?
        if backupFirst {
            do {
                // Backed up under the file's *own* root, so a multi-folder
                // scan leaves each artist folder's backups beside it
                // instead of collecting them all under the first folder.
                try BackupManager.backupIfNeeded(fileURL: file.url, root: fileRoot)
            } catch {
                backupFailure = .backupFailed(error)
            }
        }

        try await TagWriterRouter.write(changes, to: file.url)

        let expected = Self.expectedArtist(
            for: file.url, in: fileRoot, override: artistOverride, category: file.category)
        let updated = await Self.inspect(file.url, expectedArtist: expected, category: file.category)
        if let index = files.firstIndex(where: { $0.url == file.url }) {
            files[index] = updated
        }
        lookupResults.removeValue(forKey: file.url)

        return backupFailure
    }

    /// Records the result of comparing a Discogs release's tracklist
    /// against `folderURL`'s scanned files. Called from
    /// `AlbumComparisonView.loadDetail()` once it's determined whether
    /// every track in the release was matched to a local file.
    func recordAlbumCompletenessResult(_ result: AlbumCompletenessOnlineResult, for folderURL: URL) {
        albumCompletenessResults[folderURL] = result
    }

    /// Renames each proposal's file via `FileManager.moveItem`, inside the
    /// scanned folder's security-scoped access (same pattern as
    /// `applyTagChanges`). Continues past per-file failures — a locked or
    /// missing file doesn't abort the rest of the batch — and records what
    /// succeeded so "Undo Last Rename" can reverse it.
    func renameFiles(_ proposals: [RenameProposal]) async -> [RenameOperationResult] {
        guard hasScannedFolder else {
            return proposals.map {
                RenameOperationResult(originalURL: $0.file.url, currentName: $0.currentName,
                                       proposedName: $0.proposedName,
                                       errorDescription: "No scanned folder to rename within.")
            }
        }

        guard let accessed = beginAccessToAllRoots() else {
            return proposals.map {
                RenameOperationResult(originalURL: $0.file.url, currentName: $0.currentName,
                                       proposedName: $0.proposedName,
                                       errorDescription: TagWriteError.folderAccessUnavailable.localizedDescription)
            }
        }
        defer { endAccess(accessed) }

        var results: [RenameOperationResult] = []
        var batch: [RenameLogEntry] = []

        for proposal in proposals {
            let oldURL = proposal.file.url
            let newURL = oldURL.deletingLastPathComponent().appendingPathComponent(proposal.proposedName)

            do {
                try performMove(from: oldURL, to: newURL)
                batch.append(RenameLogEntry(oldURL: oldURL, newURL: newURL, isFolderMove: false))
                if let index = files.firstIndex(where: { $0.url == oldURL }) {
                    files[index] = files[index].renamed(to: newURL)
                }
                if let outcome = lookupResults.removeValue(forKey: oldURL) {
                    lookupResults[newURL] = outcome
                }
                if let outcome = spectralResults.removeValue(forKey: oldURL) {
                    spectralResults[newURL] = outcome
                }
                results.append(RenameOperationResult(
                    originalURL: oldURL, currentName: proposal.currentName,
                    proposedName: proposal.proposedName, errorDescription: nil))
            } catch {
                results.append(RenameOperationResult(
                    originalURL: oldURL, currentName: proposal.currentName,
                    proposedName: proposal.proposedName, errorDescription: error.localizedDescription))
            }
        }

        if !batch.isEmpty {
            lastRenameBatch = batch
        }
        return results
    }

    /// Moves each proposal's file into its release subfolder (created if
    /// needed) via `FileManager.moveItem`, same access/error-handling
    /// pattern as `renameFiles` — and shares its undo batch, since both are
    /// just moves from one URL to another.
    func collectIntoFolders(_ proposals: [CollectionProposal]) async -> [RenameOperationResult] {
        guard hasScannedFolder else {
            return proposals.map {
                RenameOperationResult(originalURL: $0.file.url, currentName: $0.file.fileName,
                                       proposedName: $0.proposedRelativePath,
                                       errorDescription: "No scanned folder to organize within.")
            }
        }

        guard let accessed = beginAccessToAllRoots() else {
            return proposals.map {
                RenameOperationResult(originalURL: $0.file.url, currentName: $0.file.fileName,
                                       proposedName: $0.proposedRelativePath,
                                       errorDescription: TagWriteError.folderAccessUnavailable.localizedDescription)
            }
        }
        defer { endAccess(accessed) }

        var results: [RenameOperationResult] = []
        var batch: [RenameLogEntry] = []

        for proposal in proposals {
            let oldURL = proposal.file.url
            let destinationFolder = oldURL.deletingLastPathComponent()
                .appendingPathComponent(proposal.releaseFolderName)
            let newURL = destinationFolder.appendingPathComponent(oldURL.lastPathComponent)

            do {
                try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
                try performMove(from: oldURL, to: newURL)
                batch.append(RenameLogEntry(oldURL: oldURL, newURL: newURL, isFolderMove: false))
                if let index = files.firstIndex(where: { $0.url == oldURL }) {
                    files[index] = files[index].renamed(to: newURL)
                }
                if let outcome = lookupResults.removeValue(forKey: oldURL) {
                    lookupResults[newURL] = outcome
                }
                if let outcome = spectralResults.removeValue(forKey: oldURL) {
                    spectralResults[newURL] = outcome
                }
                results.append(RenameOperationResult(
                    originalURL: oldURL, currentName: proposal.file.fileName,
                    proposedName: proposal.proposedRelativePath, errorDescription: nil))
            } catch {
                results.append(RenameOperationResult(
                    originalURL: oldURL, currentName: proposal.file.fileName,
                    proposedName: proposal.proposedRelativePath, errorDescription: error.localizedDescription))
            }
        }

        if !batch.isEmpty {
            lastRenameBatch = batch
        }
        return results
    }

    /// Moves each proposal's file into the "_CleanMyDigital Duplicates"
    /// review folder (mirroring its original relative path, created as
    /// needed), same pattern as `collectIntoFolders` — never deletes
    /// anything, and shares the same undo batch.
    func moveDuplicates(_ proposals: [DuplicateMoveProposal]) async -> [RenameOperationResult] {
        guard hasScannedFolder else {
            return proposals.map {
                RenameOperationResult(originalURL: $0.file.url, currentName: $0.file.fileName,
                                       proposedName: $0.proposedRelativePath,
                                       errorDescription: "No scanned folder to organize within.")
            }
        }

        guard let accessed = beginAccessToAllRoots() else {
            return proposals.map {
                RenameOperationResult(originalURL: $0.file.url, currentName: $0.file.fileName,
                                       proposedName: $0.proposedRelativePath,
                                       errorDescription: TagWriteError.folderAccessUnavailable.localizedDescription)
            }
        }
        defer { endAccess(accessed) }

        var results: [RenameOperationResult] = []
        var batch: [RenameLogEntry] = []

        for proposal in proposals {
            let oldURL = proposal.file.url
            // `proposedRelativePath` is relative to the file's own root
            // (see `DuplicatePlanner.plan(for:roots:)`), so a duplicate
            // moves into a "_CleanMyDigital Duplicates" folder inside the
            // artist folder it came from — not into whichever folder
            // happened to be selected first.
            guard let fileRoot = root(containing: oldURL) else {
                results.append(RenameOperationResult(
                    originalURL: oldURL, currentName: proposal.file.fileName,
                    proposedName: proposal.proposedRelativePath,
                    errorDescription: "This file isn't inside any scanned folder."))
                continue
            }
            let newURL = fileRoot.appendingPathComponent(proposal.proposedRelativePath)
            let destinationFolder = newURL.deletingLastPathComponent()

            do {
                try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
                try performMove(from: oldURL, to: newURL)
                batch.append(RenameLogEntry(oldURL: oldURL, newURL: newURL, isFolderMove: false))
                if let index = files.firstIndex(where: { $0.url == oldURL }) {
                    files[index] = files[index].renamed(to: newURL)
                }
                if let outcome = lookupResults.removeValue(forKey: oldURL) {
                    lookupResults[newURL] = outcome
                }
                if let outcome = spectralResults.removeValue(forKey: oldURL) {
                    spectralResults[newURL] = outcome
                }
                results.append(RenameOperationResult(
                    originalURL: oldURL, currentName: proposal.file.fileName,
                    proposedName: proposal.proposedRelativePath, errorDescription: nil))
            } catch {
                results.append(RenameOperationResult(
                    originalURL: oldURL, currentName: proposal.file.fileName,
                    proposedName: proposal.proposedRelativePath, errorDescription: error.localizedDescription))
            }
        }

        if !batch.isEmpty {
            lastRenameBatch = batch
        }
        return results
    }

    /// Renames an album's containing folder to "Album Title (Year)"
    /// (`proposal.proposedFolderName`, from `AlbumFolderRenamePlanner`),
    /// then updates every file inside to reflect the new parent path.
    ///
    /// Structurally different from `renameFiles`/`collectIntoFolders`/
    /// `moveDuplicates`, which each relocate one `AudioFile.url` at a time:
    /// this moves the *folder* itself in a single `performMove` call, which
    /// carries every file (and any non-audio sibling, e.g. cover art) along
    /// with it on disk automatically — only the URL bookkeeping for files
    /// already tracked in `files` needs updating afterward, by swapping
    /// each one's parent folder for the new one and keeping its own
    /// filename. `proposal.group.files` (captured when the proposal was
    /// built) gives the exact set of files to update, rather than having to
    /// re-derive "which files are under this folder" from `files` itself.
    ///
    /// Participates in the same `lastRenameBatch`/"Undo Last Change"
    /// mechanism as the other move methods, via a folder-level
    /// `RenameLogEntry` (`isFolderMove: true`) — reversing a folder move
    /// isn't a single-file match like the others, so `undoLastFileOperation`
    /// branches on that flag to update every file under the folder instead
    /// of looking for one exact URL.
    func renameAlbumFolders(_ proposals: [AlbumFolderRenameProposal]) async -> [RenameOperationResult] {
        guard hasScannedFolder else {
            return proposals.map {
                RenameOperationResult(originalURL: $0.group.folderURL, currentName: $0.currentFolderName,
                                       proposedName: $0.proposedFolderName,
                                       errorDescription: "No scanned folder to rename within.")
            }
        }

        guard let accessed = beginAccessToAllRoots() else {
            return proposals.map {
                RenameOperationResult(originalURL: $0.group.folderURL, currentName: $0.currentFolderName,
                                       proposedName: $0.proposedFolderName,
                                       errorDescription: TagWriteError.folderAccessUnavailable.localizedDescription)
            }
        }
        defer { endAccess(accessed) }

        var results: [RenameOperationResult] = []
        var batch: [RenameLogEntry] = []

        for proposal in proposals {
            let oldFolderURL = proposal.group.folderURL
            let newFolderURL = oldFolderURL.deletingLastPathComponent()
                .appendingPathComponent(proposal.proposedFolderName)

            do {
                try performMove(from: oldFolderURL, to: newFolderURL)
                batch.append(RenameLogEntry(oldURL: oldFolderURL, newURL: newFolderURL, isFolderMove: true))
                for groupFile in proposal.group.files {
                    let oldFileURL = groupFile.url
                    let newFileURL = newFolderURL.appendingPathComponent(oldFileURL.lastPathComponent)
                    if let index = files.firstIndex(where: { $0.url == oldFileURL }) {
                        files[index] = files[index].renamed(to: newFileURL)
                    }
                    if let outcome = lookupResults.removeValue(forKey: oldFileURL) {
                        lookupResults[newFileURL] = outcome
                    }
                    if let outcome = spectralResults.removeValue(forKey: oldFileURL) {
                        spectralResults[newFileURL] = outcome
                    }
                }
                results.append(RenameOperationResult(
                    originalURL: oldFolderURL, currentName: proposal.currentFolderName,
                    proposedName: proposal.proposedFolderName, errorDescription: nil))
            } catch {
                results.append(RenameOperationResult(
                    originalURL: oldFolderURL, currentName: proposal.currentFolderName,
                    proposedName: proposal.proposedFolderName, errorDescription: error.localizedDescription))
            }
        }

        if !batch.isEmpty {
            lastRenameBatch = batch
        }
        return results
    }

    /// Reverses the most recent move batch (a rename, a "Collect into
    /// Folders" run, a duplicate move, or an album-folder rename),
    /// most-recent-first so any collision-avoidance ordering unwinds
    /// correctly. A folder-level entry (`isFolderMove`) updates every file
    /// whose parent folder is the moved folder, since there's no single
    /// file URL to match against like the other entry kinds.
    func undoLastFileOperation() async -> [RenameOperationResult] {
        guard hasScannedFolder, !lastRenameBatch.isEmpty else { return [] }

        guard let accessed = beginAccessToAllRoots() else {
            return lastRenameBatch.map {
                RenameOperationResult(originalURL: $0.newURL, currentName: $0.newURL.lastPathComponent,
                                       proposedName: $0.oldURL.lastPathComponent,
                                       errorDescription: TagWriteError.folderAccessUnavailable.localizedDescription)
            }
        }
        defer { endAccess(accessed) }

        var results: [RenameOperationResult] = []
        for entry in lastRenameBatch.reversed() {
            do {
                try performMove(from: entry.newURL, to: entry.oldURL)
                if entry.isFolderMove {
                    for index in files.indices where files[index].url.deletingLastPathComponent() == entry.newURL {
                        let oldFileURL = files[index].url
                        let restoredURL = entry.oldURL.appendingPathComponent(oldFileURL.lastPathComponent)
                        files[index] = files[index].renamed(to: restoredURL)
                        if let outcome = lookupResults.removeValue(forKey: oldFileURL) {
                            lookupResults[restoredURL] = outcome
                        }
                        if let outcome = spectralResults.removeValue(forKey: oldFileURL) {
                            spectralResults[restoredURL] = outcome
                        }
                    }
                } else if let index = files.firstIndex(where: { $0.url == entry.newURL }) {
                    files[index] = files[index].renamed(to: entry.oldURL)
                    if let outcome = lookupResults.removeValue(forKey: entry.newURL) {
                        lookupResults[entry.oldURL] = outcome
                    }
                    if let outcome = spectralResults.removeValue(forKey: entry.newURL) {
                        spectralResults[entry.oldURL] = outcome
                    }
                }
                results.append(RenameOperationResult(
                    originalURL: entry.newURL, currentName: entry.newURL.lastPathComponent,
                    proposedName: entry.oldURL.lastPathComponent, errorDescription: nil))
            } catch {
                results.append(RenameOperationResult(
                    originalURL: entry.newURL, currentName: entry.newURL.lastPathComponent,
                    proposedName: entry.oldURL.lastPathComponent, errorDescription: error.localizedDescription))
            }
        }
        lastRenameBatch = []
        return results
    }

    /// Moves `source` to `destination`, going through a temporary name
    /// first when the two differ only by letter case — APFS is
    /// case-insensitive, so a direct rename between such paths doesn't
    /// reliably take effect.
    private func performMove(from source: URL, to destination: URL) throws {
        let sourceName = source.lastPathComponent
        let destinationName = destination.lastPathComponent
        guard sourceName != destinationName, sourceName.lowercased() == destinationName.lowercased() else {
            try FileManager.default.moveItem(at: source, to: destination)
            return
        }

        let tempURL = destination.deletingLastPathComponent()
            .appendingPathComponent(".cleanmydigital-rename-\(UUID().uuidString)")
        try FileManager.default.moveItem(at: source, to: tempURL)
        do {
            try FileManager.default.moveItem(at: tempURL, to: destination)
        } catch {
            try? FileManager.default.moveItem(at: tempURL, to: source)
            throw error
        }
    }

    /// Looks up every flagged file against Discogs, then MusicBrainz, one at
    /// a time — both clients pace their own requests, so this just needs to
    /// stay sequential and stop promptly on cancellation.
    func findAllMetadata(discogsToken: String, musicBrainzContact: String) {
        guard !isLookingUp else { return }
        let targets = files.filter(\.hasIssues)
        guard !targets.isEmpty else { return }

        lookupCompletedCount = 0
        lookupTotalCount = targets.count
        isLookingUp = true

        lookupTask = Task {
            for file in targets {
                if Task.isCancelled { break }
                let outcome = await Self.lookupOutcome(
                    for: file, discogsToken: discogsToken, musicBrainzContact: musicBrainzContact)
                if Task.isCancelled { break }
                lookupResults[file.url] = outcome
                lookupCompletedCount += 1
            }
            isLookingUp = false
            lookupTask = nil
        }
    }

    /// Stops the batch lookup after the in-flight request finishes —
    /// whatever was already found stays in `lookupResults`.
    func cancelLookup() {
        lookupTask?.cancel()
    }

    /// Measures a "spectral cutoff" — the highest frequency still carrying
    /// real signal energy — for every readable file, the same signature a
    /// spectrogram viewer like Spek shows visually as a hard ceiling. Runs
    /// with bounded concurrency like the initial scan, since this is
    /// CPU-bound decode+FFT work rather than a rate-limited network call.
    func analyzeSpectrum() {
        guard !isAnalyzingSpectrum, hasScannedFolder else { return }
        let targets = files.filter(\.isReadable)
        guard !targets.isEmpty else { return }

        spectralCompletedCount = 0
        spectralTotalCount = targets.count
        isAnalyzingSpectrum = true

        spectralTask = Task {
            // Held for the whole batch, unlike the synchronous file-write
            // methods' `defer` — this Task outlives the function that
            // launched it, so access has to be released only once every
            // file has actually been read, not when `analyzeSpectrum()`
            // itself returns (immediately, after just starting the Task).
            guard let accessed = beginAccessToAllRoots() else {
                let message = TagWriteError.folderAccessUnavailable.localizedDescription
                for file in targets {
                    spectralResults[file.url] = .failed(message)
                }
                spectralCompletedCount = targets.count
                isAnalyzingSpectrum = false
                spectralTask = nil
                return
            }
            defer { endAccess(accessed) }

            let maxConcurrent = 4
            await withTaskGroup(of: (URL, SpectralCutoffOutcome).self) { group in
                var iterator = targets.makeIterator()

                func addNext() {
                    guard let file = iterator.next() else { return }
                    group.addTask {
                        let outcome: SpectralCutoffOutcome
                        do {
                            outcome = try await SpectralCutoffReader.analyze(url: file.url)
                        } catch {
                            outcome = .failed(error.localizedDescription)
                        }
                        return (file.url, outcome)
                    }
                }

                for _ in 0..<maxConcurrent { addNext() }

                for await (url, outcome) in group {
                    if Task.isCancelled {
                        group.cancelAll()
                        break
                    }
                    spectralResults[url] = outcome
                    spectralCompletedCount += 1
                    addNext()
                }
            }
            isAnalyzingSpectrum = false
            spectralTask = nil
        }
    }

    /// Stops the batch spectral analysis after in-flight files finish —
    /// whatever was already measured stays in `spectralResults`.
    func cancelSpectrumAnalysis() {
        spectralTask?.cancel()
    }

    /// Searches Discogs first; only falls through to MusicBrainz if Discogs
    /// errored or its top candidate wouldn't fill any of this file's
    /// missing fields.
    nonisolated private static func lookupOutcome(
        for file: AudioFile, discogsToken: String, musicBrainzContact: String
    ) async -> LookupOutcome {
        let missing = file.missingFields
        guard !missing.isEmpty else { return .noMatch }

        if !discogsToken.isEmpty {
            let query = DiscogsQuery(for: file)
            // allowArtistOnlyFallback: false — this path picks `releases.first`
            // and applies its Genre/Year/Artwork with no human review, so a
            // broader "any of this artist's releases" result set risks
            // confidently applying the wrong release's data instead of just
            // finding nothing. See DiscogsClient.search's doc comment.
            //
            // `album` has to be passed through here — for `.compilations`,
            // `query.artist` is just "Various" (see `DiscogsQuery`'s doc
            // comment), so `album`/`release_title` is doing most of the
            // narrowing there alongside the track term.
            //
            // Compilations go through `searchCompilation` instead of
            // `search` directly — it retries once without the track term
            // on zero results (narrower, and therefore still safe for this
            // no-human-review path, unlike the general artist-only
            // fallback `allowArtistOnlyFallback: false` is guarding
            // against below) — see its own doc comment.
            let releases: [DiscogsRelease]?
            if file.category == .compilations {
                releases = try? await DiscogsClient.searchCompilation(
                    artist: query.artist, track: query.track, album: query.album, token: discogsToken
                ).releases
            } else {
                releases = try? await DiscogsClient.search(
                    artist: query.artist, track: query.track, album: query.album,
                    token: discogsToken, allowArtistOnlyFallback: false)
            }
            if let releases, let top = releases.first {
                let fillable = top.fillableFields(missing: missing)
                if !fillable.isEmpty {
                    return .found(provider: .discogs, candidate: .discogs(top), fillableFields: fillable)
                }
            }
        }

        if !musicBrainzContact.isEmpty {
            let query = MusicBrainzQuery(for: file)
            if let recordings = try? await MusicBrainzClient.searchRecordings(
                artist: query.artist, recording: query.recording, contactEmail: musicBrainzContact),
               let top = recordings.first {
                let fillable = top.fillableFields(missing: missing)
                if !fillable.isEmpty {
                    return .found(provider: .musicBrainz, candidate: .musicBrainz(top), fillableFields: fillable)
                }
            }
        }

        return .noMatch
    }

    nonisolated private static func audioFileURLs(in folder: URL) -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var urls: [URL] = []
        for case let url as URL in enumerator {
            if url.lastPathComponent == BackupManager.backupFolderName {
                enumerator.skipDescendants()
                continue
            }
            let ext = url.pathExtension.lowercased()
            guard supportedExtensions.contains(ext) || nativeOnlyExtensions.contains(ext)
                    || unsupportedAudioExtensions.contains(ext),
                  (try? url.resourceValues(forKeys: Set(keys)).isRegularFile) == true
            else { continue }
            urls.append(url)
        }
        return urls
    }

    /// The first path component of `url` under `folder` — the "ArtistName"
    /// folder Singles & Albums are organized by. Nil if `url` sits directly
    /// in `folder` with no intervening subfolder.
    ///
    /// When `override` is non-nil and `category == .albums`, it's returned
    /// directly instead — the "treat this folder as the artist" scan mode,
    /// for scanning an artist's own folder (`ArtistFolder/AlbumName/Track`)
    /// where the folder-depth calculation below would otherwise mistake the
    /// first album subfolder for the artist.
    nonisolated private static func expectedArtist(
        for url: URL, in folder: URL, override: String?, category: LibraryCategory
    ) -> String? {
        if category == .albums, let override { return override }
        return firstLevelFolderName(for: url, in: folder)
    }

    /// The first path component of `url` under `folder`, with no override
    /// applied — the raw folder-depth calculation `expectedArtist(for:in:
    /// override:category:)` falls back to, and what `detectArtistFolderOverride`
    /// inspects directly (before any override exists to short-circuit it).
    nonisolated private static func firstLevelFolderName(for url: URL, in folder: URL) -> String? {
        let rootComponents = folder.standardizedFileURL.pathComponents
        let fileComponents = url.standardizedFileURL.pathComponents
        guard fileComponents.count > rootComponents.count + 1,
              Array(fileComponents.prefix(rootComponents.count)) == rootComponents
        else { return nil }
        return fileComponents[rootComponents.count]
    }

    /// Auto-detects the "treat this folder as the artist" override for a
    /// plain Albums scan, so the common case — scanning one artist's own
    /// folder, which directly contains that artist's album subfolders —
    /// doesn't need the user to notice `possibleArtistFolderMismatch`'s
    /// banner and click its fix button every time. Uses only `urls` (the
    /// just-enumerated file paths), not metadata, so it's cheap enough to
    /// run before the metadata-reading pass starts.
    ///
    /// Same signal as the reactive banner: for each distinct first-level
    /// folder name under `folder` (ignoring files that sit directly in
    /// `folder` with no subfolder — nothing to detect from those), checks
    /// how many look like an album name per `AudioFile.looksLikeAlbumFolderName`
    /// rather than an artist name.
    ///
    /// Requires *both*:
    /// - at least 2 distinct folder names. A single subfolder is genuinely
    ///   ambiguous — indistinguishable, from folder names alone, between
    ///   "artist folder containing exactly one album" and any other
    ///   one-off folder that happens to match the album-name heuristic —
    ///   so it isn't enough evidence for a pattern. That ambiguous case is
    ///   left to the reactive banner and the manual toolbar button, exactly
    ///   as before.
    /// - at least two-thirds of those distinct names look like album names.
    ///   Two-thirds (rather than unanimous) tolerates the realistic wrinkle
    ///   of one or two oddly-named folders sitting alongside genuine album
    ///   folders — a "Bonus", "Live", or "Artwork" folder — without that
    ///   alone blocking detection of what's overwhelmingly an artist folder
    ///   full of albums. It's still strict enough that an ordinary
    ///   multi-artist folder won't false-positive: getting two-thirds of a
    ///   folder's *artist* names to look like album names (a 4-digit year
    ///   and/or multiple " - "-separated parts) would take a very unusual
    ///   library.
    nonisolated private static func detectArtistFolderOverride(urls: [URL], folder: URL) -> String? {
        let distinctFolderNames = Set(urls.compactMap { firstLevelFolderName(for: $0, in: folder) })
        guard distinctFolderNames.count >= 2 else { return nil }

        let albumLikeCount = distinctFolderNames.filter { AudioFile.looksLikeAlbumFolderName($0) }.count
        guard albumLikeCount * 3 >= distinctFolderNames.count * 2 else { return nil }

        return folder.lastPathComponent
    }

    nonisolated private static func inspect(
        _ url: URL, expectedArtist: String?, category: LibraryCategory
    ) async -> AudioFile {
        let ext = url.pathExtension.lowercased()
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0

        func unreadable() -> AudioFile {
            AudioFile(url: url, fileName: url.lastPathComponent, fileExtension: ext,
                      sizeBytes: size, duration: nil, bitrateKbps: nil,
                      title: nil, artist: nil, album: nil,
                      artworkThumbnail: nil,
                      year: nil, genre: nil, trackNumber: nil,
                      category: category, expectedArtist: expectedArtist,
                      isReadable: false)
        }

        // DSF and WavPack each need a fully separate path — see
        // `nativeOnlyExtensions`'s doc comment. There's no partial
        // AVFoundation result to supplement here, unlike FLAC/WAV/AIFF's
        // native readers, so this skips constructing an `AVURLAsset`
        // entirely. The two formats share nothing beyond both landing
        // here — DSF's tags are ID3, WavPack's are APEv2 — so each has its
        // own reader, but both produce the same `duration`/`bitrateKbps`/
        // `NativeAudioMetadata` shape this merges into an `AudioFile`.
        if nativeOnlyExtensions.contains(ext) {
            let result: (metadata: NativeAudioMetadata, duration: TimeInterval?, bitrateKbps: Int?)?
            switch ext {
            case "dsf":
                if let r = try? DSFMetadataReader.read(contentsOf: url) {
                    result = (r.metadata, r.duration, r.bitrateKbps)
                } else {
                    result = nil
                }
            case "wv":
                if let r = try? WavPackMetadataReader.read(contentsOf: url) {
                    result = (r.metadata, r.duration, r.bitrateKbps)
                } else {
                    result = nil
                }
            default:
                result = nil
            }
            guard let result else { return unreadable() }

            var artwork: NSImage?
            if let artworkData = result.metadata.artworkData {
                artwork = downscaledImage(from: artworkData, maxPixelSize: thumbnailMaxPixelSize)
            }
            return AudioFile(
                url: url,
                fileName: url.lastPathComponent,
                fileExtension: ext,
                sizeBytes: size,
                duration: result.duration,
                bitrateKbps: result.bitrateKbps,
                title: result.metadata.title,
                artist: result.metadata.artist,
                album: result.metadata.album,
                artworkThumbnail: artwork,
                year: result.metadata.year,
                genre: result.metadata.genre,
                trackNumber: result.metadata.trackNumber,
                category: category,
                expectedArtist: expectedArtist,
                isReadable: true
            )
        }

        guard supportedExtensions.contains(ext) else { return unreadable() }

        let asset = AVURLAsset(url: url)
        do {
            // Merge common metadata with every format-specific block (ID3,
            // iTunes, …) so tags AVFoundation doesn't map to "common" still count.
            var items = try await asset.load(.commonMetadata)
            for format in try await asset.load(.availableMetadataFormats) {
                items += try await asset.loadMetadata(for: format)
            }

            let duration = try? await asset.load(.duration).seconds

            // AVFoundation's reading is incomplete/unreliable for some
            // container formats — it can't see anything for FLACs with a
            // nonstandard ID3v2 prefix (treats the whole file as ID3-only),
            // for WAV it translates LIST/INFO fields into an undocumented
            // identifier namespace scanning doesn't look for, and for AIFF
            // it can serve stale metadata when re-reading a URL it already
            // opened earlier in the same process (e.g. right after Apply
            // to File writes new tags). Read those natively and fall back
            // to them wherever AVFoundation came up empty, so scanning
            // (and post-write re-inspection) stays accurate for those files.
            let native: NativeAudioMetadata?
            switch ext {
            case "flac": native = try? FLACMetadataReader.read(contentsOf: url)
            case "wav", "wave": native = try? RIFFMetadataReader.read(contentsOf: url)
            case "aif", "aiff", "aifc": native = try? AIFFMetadataReader.read(contentsOf: url)
            default: native = nil
            }

            let bitrateKbps = await Self.audioBitrateKbps(
                for: asset, fallbackAudioDataSize: native?.audioDataSize, duration: duration)

            var artwork = await artworkThumbnail(in: items)
            if artwork == nil, let artworkData = native?.artworkData {
                artwork = downscaledImage(from: artworkData, maxPixelSize: thumbnailMaxPixelSize)
            }

            return AudioFile(
                url: url,
                fileName: url.lastPathComponent,
                fileExtension: ext,
                sizeBytes: size,
                duration: duration,
                bitrateKbps: bitrateKbps,
                title: mergedValue(
                    avFoundation: await stringValue(in: items, common: .commonIdentifierTitle,
                                                     keys: ["TIT2", "TT2", "©nam", "title", "TITLE"]),
                    native: native?.title),
                artist: mergedValue(
                    avFoundation: await stringValue(in: items, common: .commonIdentifierArtist,
                                                     keys: ["TPE1", "TP1", "©ART", "artist", "ARTIST"]),
                    native: native?.artist),
                album: mergedValue(
                    avFoundation: await stringValue(in: items, common: .commonIdentifierAlbumName,
                                                     keys: ["TALB", "TAL", "©alb", "album", "ALBUM"]),
                    native: native?.album),
                artworkThumbnail: artwork,
                year: mergedValue(
                    avFoundation: await stringValue(in: items, common: .commonIdentifierCreationDate,
                                                     keys: ["TYER", "TDRC", "©day", "year", "YEAR"]),
                    native: native?.year),
                genre: mergedValue(
                    avFoundation: await stringValue(in: items, common: nil,
                                                     keys: ["TCON", "©gen", "gnre", "genre", "GENRE"]),
                    native: native?.genre),
                trackNumber: mergedTrackNumber(
                    avFoundation: await trackNumberValue(in: items),
                    native: native?.trackNumber),
                category: category,
                expectedArtist: expectedArtist,
                isReadable: true
            )
        } catch {
            return unreadable()
        }
    }

    /// The audio track's real encoded bitrate in kbps, read from the
    /// decoded audio stream itself rather than estimated from whole-file
    /// size ÷ duration — that naive estimate double-counts embedded
    /// artwork and tag bytes as if they were audio data, skewing short
    /// tracks with large cover images upward. Isolating the audio track
    /// (excluding any embedded artwork/video track) avoids that.
    ///
    /// `AVAssetTrack.estimatedDataRate` comes back unavailable for FLAC and
    /// WAV specifically (confirmed empirically, same AVFoundation gap
    /// documented above for tag reading) — `fallbackAudioDataSize`, the
    /// native readers' byte count for just the audio-sample chunk/block,
    /// covers those instead.
    nonisolated private static func audioBitrateKbps(
        for asset: AVURLAsset, fallbackAudioDataSize: Int64?, duration: Double?
    ) async -> Int? {
        if let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first,
           let rate = try? await audioTrack.load(.estimatedDataRate), rate > 0 {
            return Int((rate / 1000).rounded())
        }

        guard let fallbackAudioDataSize, fallbackAudioDataSize > 0,
              let duration, duration > 0
        else { return nil }
        return Int((Double(fallbackAudioDataSize) * 8 / duration / 1000).rounded())
    }

    /// AVFoundation's reading wins when it found something — a native
    /// reader only fills in what AVFoundation couldn't see at all.
    nonisolated private static func mergedValue(avFoundation: String?, native: String?) -> String? {
        if let avFoundation, !avFoundation.isEmpty { return avFoundation }
        if let native, !native.isEmpty { return native }
        return nil
    }

    /// Same precedence as `mergedValue`, except a native "x/y" reading (a
    /// position combined with a total count AVFoundation's own metadata
    /// doesn't carry — e.g. a FLAC's separate TRACKTOTAL comment) always
    /// wins, since it's strictly more complete than AVFoundation's
    /// position-only string.
    nonisolated private static func mergedTrackNumber(avFoundation: String?, native: String?) -> String? {
        if let native, native.contains("/") { return native }
        return mergedValue(avFoundation: avFoundation, native: native)
    }

    nonisolated private static func stringValue(
        in items: [AVMetadataItem],
        common identifier: AVMetadataIdentifier?,
        keys: [String]
    ) async -> String? {
        var candidates = identifier.map {
            AVMetadataItem.metadataItems(from: items, filteredByIdentifier: $0)
        } ?? []
        candidates += items.filter { item in
            guard let key = item.key else { return false }
            return keys.contains(String(describing: key))
        }
        for item in candidates {
            if let value = try? await item.load(.stringValue),
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }
        return nil
    }

    /// The `trkn` iTunes atom is packed binary (2 bytes padding, 2 bytes
    /// track number, 2 bytes total tracks, 2 bytes padding — see
    /// `M4ATagWriter`), so it doesn't reliably surface through
    /// `.stringValue` at all: confirmed empirically that AVFoundation
    /// reports this item's raw `.key` as a numeric FourCharCode rather than
    /// the string "trkn", so the generic key-string matching `stringValue`
    /// uses below never finds it, total or no total. Matched here by its
    /// `.iTunesMetadataTrackNumber` identifier instead, and decoded
    /// directly from `.dataValue`. Falls back to the string-based lookup
    /// for every other format (MP3's "x/y" TRCK text, FLAC/other trkn-less
    /// files).
    nonisolated private static func trackNumberValue(in items: [AVMetadataItem]) async -> String? {
        let trknItems = AVMetadataItem.metadataItems(from: items, filteredByIdentifier: .iTunesMetadataTrackNumber)
        for item in trknItems {
            if let data = try? await item.load(.dataValue), let decoded = decodeTrknAtom(data) {
                return decoded
            }
        }
        return await stringValue(in: items, common: nil,
                                  keys: ["TRCK", "trkn", "tracknumber", "TRACKNUMBER"])
    }

    /// Decodes a `trkn` atom into "x" or "x/y" depending on whether it
    /// carries a nonzero total. Nil only when there's no usable track
    /// number at all, so the caller falls back to the string-based reading.
    nonisolated private static func decodeTrknAtom(_ data: Data) -> String? {
        guard data.count >= 4 else { return nil }
        let bytes = [UInt8](data)
        let track = Int(bytes[2]) << 8 | Int(bytes[3])
        guard track > 0 else { return nil }
        guard data.count >= 6 else { return "\(track)" }
        let total = Int(bytes[4]) << 8 | Int(bytes[5])
        return total > 0 ? "\(track)/\(total)" : "\(track)"
    }

    /// Table thumbnails render at 24pt; 64px covers up to 3x Retina scaling
    /// while keeping the decoded bitmap tiny across large libraries.
    nonisolated private static let thumbnailMaxPixelSize = 64

    nonisolated private static func artworkThumbnail(in items: [AVMetadataItem]) async -> NSImage? {
        var candidates = AVMetadataItem.metadataItems(
            from: items, filteredByIdentifier: .commonIdentifierArtwork)
        candidates += items.filter { item in
            guard let key = item.key else { return false }
            return ["APIC", "PIC", "covr"].contains(String(describing: key))
        }
        for item in candidates {
            if let data = try? await item.load(.dataValue), !data.isEmpty,
               let thumbnail = downscaledImage(from: data, maxPixelSize: thumbnailMaxPixelSize) {
                return thumbnail
            }
        }
        return nil
    }

    nonisolated private static func downscaledImage(from data: Data, maxPixelSize: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}
