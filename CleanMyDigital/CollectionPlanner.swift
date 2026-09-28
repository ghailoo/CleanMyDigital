//
//  CollectionPlanner.swift
//  CleanMyDigital
//

import Foundation

/// One track's move within a "Collect into Folders" run — from wherever it
/// currently sits under an artist folder into
/// `Artist/Song Title/Pressing/file` (or straight into the song folder when
/// there's no distinguishing pressing name).
struct CollectionProposal: Identifiable, Sendable {
    let file: AudioFile
    let songTitle: String
    let pressingName: String?
    /// The file's name after any rule-6 collision disambiguation — usually
    /// unchanged.
    let proposedFileName: String
    /// Path relative to the artist root: "Song/Pressing/file" or "Song/file".
    let proposedRelativePath: String
    /// True for a "...ape.flac"-style leftover double extension — flagged in
    /// the preview; still moved like any other track.
    let hasOddExtension: Bool

    var id: URL { file.url }
}

/// Every proposal for one scanned artist folder, plus the top-level source
/// folders that become completely empty once all of them apply. This is the
/// unit the preview and its per-artist checkbox operate on.
struct ArtistCollectionPlan: Identifiable, Sendable {
    let artistFolderName: String
    let artistRoot: URL
    let proposals: [CollectionProposal]
    let sourceFoldersToClean: [URL]

    var id: URL { artistRoot }
}

/// Derives a plan for organizing Singles into `Artist/Song Title/Pressing` —
/// every mix and every pressing of the same track ends up under one song
/// folder, subdivided by pressing only where the source folder actually
/// carries a distinguishing descriptor. Pure and filesystem-free, like
/// `RenamePlanner`; the caller (`LibraryScanner`) does the actual I/O.
enum CollectionPlanner {
    /// Builds one plan per scanned artist folder, skipping artists where
    /// every file is already exactly where this scheme would put it — the
    /// idempotency guarantee: running this again on an organized folder
    /// proposes nothing.
    static func plan(for files: [AudioFile]) -> [ArtistCollectionPlan] {
        let singles = files.filter { $0.category == .singles }
        let byRoot = Dictionary(grouping: singles, by: artistRootURL(for:))

        return byRoot.compactMap { root, artistFiles -> ArtistCollectionPlan? in
            let (proposals, cleanFolders) = collectionProposals(for: artistFiles, artistRoot: root)
            guard !proposals.isEmpty else { return nil }
            return ArtistCollectionPlan(
                artistFolderName: root.lastPathComponent, artistRoot: root,
                proposals: proposals, sourceFoldersToClean: cleanFolders)
        }
        .sorted { $0.artistFolderName.localizedStandardCompare($1.artistFolderName) == .orderedAscending }
    }

    // MARK: - Per-artist grouping and A-side resolution

    /// One file's destination before rule-6 collision handling is applied.
    private struct Planned {
        let file: AudioFile
        let songTitle: String
        let pressingName: String?
        let topFolderName: String?
    }

    private static func collectionProposals(
        for artistFiles: [AudioFile], artistRoot: URL
    ) -> (proposals: [CollectionProposal], sourceFoldersToClean: [URL]) {
        // Group by the file's current top-level folder under the artist —
        // nil means the file is loose, directly in the artist folder.
        let bySourceFolder = Dictionary(grouping: artistFiles, by: \.expectedArtist)

        var planned: [Planned] = []

        var cleanFolders: [URL] = []

        for (topFolderName, groupFiles) in bySourceFolder {
            let titled: [(file: AudioFile, title: String)] = groupFiles.compactMap { file in
                guard let title = songTitle(for: file) else { return nil }
                return (file, title)
            }
            guard !titled.isEmpty else { continue }

            // Rule 3: a folder with several distinct songs (an A-side plus
            // B-sides) stays together under one song folder — picked by
            // whichever title the original folder name names, since that's
            // the release's actual A-side.
            // An album or compilation, not a single's pressings: leave it alone.
            let distinctSongs = Set(titled.map { songKey($0.title) })
            guard distinctSongs.count <= maxDistinctSongsPerRelease else { continue }

            let distinctTitles = Array(Set(titled.map(\.title)))
            let groupSongTitle: String
            if distinctTitles.count == 1 {
                groupSongTitle = distinctTitles[0]
            } else if let topFolderName,
                      let matched = distinctTitles.first(where: { topFolderName.localizedCaseInsensitiveContains($0) }) {
                groupSongTitle = matched
            } else {
                // No folder-name hint to pick the A-side by — fall back to
                // whichever file was scanned first, deterministically.
                groupSongTitle = titled[0].title
            }

            guard let topFolderName else {
                // Loose tracks go directly in the song folder (rule 2).
                // Each by its OWN title — loose files aren't one release, so the
                // A-side/B-side grouping above doesn't apply to them.
                for (file, title) in titled {
                    planned.append(Planned(file: file, songTitle: title, pressingName: nil, topFolderName: nil))
                }
                continue
            }

            // If the current top-level folder already *is* the song folder
            // (sanitized, case-insensitive), this group is already organized
            // to at least the song level — keep whatever pressing name is
            // already there rather than re-deriving one, and don't propose
            // cleaning up the song folder itself.
            let alreadyAtSongLevel = (RenamePlanner.sanitized(topFolderName) ?? topFolderName)
                .caseInsensitiveCompare(RenamePlanner.sanitized(groupSongTitle) ?? groupSongTitle) == .orderedSame

            if !alreadyAtSongLevel {
                cleanFolders.append(artistRoot.appendingPathComponent(topFolderName))
            }

            for (file, _) in titled {
                let pressing: String?
                if alreadyAtSongLevel {
                    pressing = currentPressingName(for: file, artistRoot: artistRoot, topFolderName: topFolderName)
                    // Anything nested below Song/Pressing (earlier runs' repeated
                    // folders, or a leftover "Close To You" subfolder) gets its
                    // covers moved up and is removed once empty.
                    let pressingFolder = artistRoot.appendingPathComponent(topFolderName)
                        .appendingPathComponent(pressing ?? "")
                    let depth = pressingFolder.standardizedFileURL.pathComponents.count
                    let fileComponents = file.url.standardizedFileURL.pathComponents
                    if pressing != nil, fileComponents.count > depth + 1 {
                        let nested = pressingFolder.appendingPathComponent(fileComponents[depth])
                        if !cleanFolders.contains(nested) { cleanFolders.append(nested) }
                    }
                } else {
                    pressing = pressingFolderName(
                        topFolderName: topFolderName,
                        artist: artistName(for: file) ?? "",
                        song: groupSongTitle)
                }
                planned.append(Planned(file: file, songTitle: groupSongTitle, pressingName: pressing, topFolderName: topFolderName))
            }
        }

        planned = canonicalizingSongTitles(planned)
        return (finalizedProposals(for: planned, artistRoot: artistRoot), cleanFolders.sorted { $0.path < $1.path })
    }

    /// Above this many genuinely different songs, a folder is an album or a
    /// compilation rather than one single's pressings, so it's skipped whole.
    /// ponytail: a plain count; no tracklist/duration analysis.
    private static let maxDistinctSongsPerRelease = 4

    /// Title spellings that differ only in case, punctuation, accents or
    /// "&" vs "and" are the same song: "Justified & Ancient" /
    /// "Justified And Ancient", "What Time Is Love?" / "What Time Is Love".
    static func songKey(_ title: String) -> String {
        let folded = title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: "&", with: " and ")
        let kept = folded.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        return String(kept).split(separator: " ").joined(separator: " ")
    }

    /// One folder per song, however each file spells it: every variant of a
    /// song key gets the same folder name. An existing song-level folder
    /// wins (so re-runs don't rename it); otherwise the most common
    /// spelling, then the shortest, then alphabetical — deterministic, so
    /// the same library always produces the same folder.
    private static func canonicalizingSongTitles(_ planned: [Planned]) -> [Planned] {
        var existingFolderName: [String: String] = [:]
        for entry in planned where entry.topFolderName != nil {
            let key = songKey(entry.songTitle)
            // Exact match only: a folder that merely *reduces* to the same key
            // ("Common Song -") isn't an organized song folder.
            if let top = entry.topFolderName, top == entry.songTitle, existingFolderName[key] == nil {
                existingFolderName[key] = top
            }
        }

        var counts: [String: [String: Int]] = [:]
        for entry in planned {
            counts[songKey(entry.songTitle), default: [:]][entry.songTitle, default: 0] += 1
        }

        var canonical: [String: String] = [:]
        for (key, variants) in counts {
            if let existing = existingFolderName[key] {
                canonical[key] = existing
                continue
            }
            canonical[key] = variants.sorted {
                if $0.value != $1.value { return $0.value > $1.value }
                if $0.key.count != $1.key.count { return $0.key.count < $1.key.count }
                return $0.key < $1.key
            }.first?.key
        }

        return planned.map { entry in
            guard let name = canonical[songKey(entry.songTitle)], name != entry.songTitle else { return entry }
            return Planned(file: entry.file, songTitle: name,
                           pressingName: entry.pressingName, topFolderName: entry.topFolderName)
        }
    }

    /// Resolves destinations and rule 6 (never overwrite — append the
    /// pressing name, or its best available stand-in, on a name clash).
    private static func finalizedProposals(for planned: [Planned], artistRoot: URL) -> [CollectionProposal] {
        // Every moving file vacates its own current spot up front, so
        // ordering never makes one about-to-move file look like it's
        // blocking another.
        var occupied = Set(planned.map { $0.file.url })

        var proposals: [CollectionProposal] = []
        for entry in planned.sorted(by: { $0.file.url.path < $1.file.url.path }) {
            let songFolder = RenamePlanner.sanitized(entry.songTitle) ?? entry.songTitle
            var destinationFolder = artistRoot.appendingPathComponent(songFolder)
            if let pressing = entry.pressingName, !pressing.isEmpty {
                destinationFolder.appendPathComponent(pressing)
            }

            var fileName = entry.file.fileName
            var destinationURL = destinationFolder.appendingPathComponent(fileName)
            if occupied.contains(destinationURL), destinationURL != entry.file.url {
                let suffix = entry.pressingName ?? entry.topFolderName ?? "2"
                fileName = disambiguated(fileName: fileName, appending: suffix)
                destinationURL = destinationFolder.appendingPathComponent(fileName)
            }
            occupied.insert(destinationURL)

            guard destinationURL != entry.file.url else { continue }

            let rootComponents = artistRoot.standardizedFileURL.pathComponents
            let relativePath = destinationURL.standardizedFileURL.pathComponents
                .dropFirst(rootComponents.count)
                .joined(separator: "/")

            proposals.append(CollectionProposal(
                file: entry.file, songTitle: entry.songTitle, pressingName: entry.pressingName,
                proposedFileName: fileName, proposedRelativePath: relativePath,
                hasOddExtension: entry.file.fileName.lowercased().hasSuffix(".ape.flac")))
        }
        return proposals
    }

    // MARK: - Song title (rule 1)

    /// The A-side title: the Title tag with any trailing mix/version
    /// suffix stripped, or the cleaned filename when there's no Title tag.
    /// Nil if neither source yields anything to sanitize.
    private static func songTitle(for file: AudioFile) -> String? {
        let rawTitle = file.title?.isEmpty == false
            ? file.title!
            : MetadataQuery.cleanedTrackTitle(from: file.fileName, artist: artistName(for: file) ?? "", category: .singles)
        guard let title = RenamePlanner.sanitized(strippingMixSuffix(from: rawTitle)), !title.isEmpty else {
            return nil
        }
        return title
    }

    private static func artistName(for file: AudioFile) -> String? {
        if let artist = file.artist, !artist.isEmpty {
            return MetadataQuery.strippingFeaturedArtist(from: artist)
        }
        return MetadataQuery.artistParsedFromFileName(file.fileName)
    }

    /// Strips every trailing "(Club Mix)" / "[Wyclef Remix]" group — a title
    /// can carry both ("My Love Is Your Love (Radio Edit) [Wyclef Remix]").
    private static func strippingMixSuffix(from title: String) -> String {
        var result = title.trimmingCharacters(in: .whitespacesAndNewlines)
        while let range = result.range(of: #"\s*[\(\[][^()\[\]]*[\)\]]\s*$"#, options: .regularExpression) {
            let stripped = result.replacingCharacters(in: range, with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if stripped.isEmpty { return result }
            result = stripped
        }
        return result
    }

    // MARK: - Pressing name (rule 2)

    /// The file's existing top-level folder with the artist and song name
    /// removed, and the first remaining bracket group unwrapped:
    /// "1990 - Close To You [12'' Promo Single]" → "1990 - 12'' Promo Single"
    /// "Maxi Priest - Close To You (US CDS Promo) (1990) - PRCD2485" →
    /// "US CDS Promo (1990) - PRCD2485". Nil when nothing is left, so the
    /// file goes directly in the song folder instead.
    private static func pressingFolderName(topFolderName: String, artist: String, song: String) -> String? {
        var result = removingSubstring(song, from: topFolderName)
        if !artist.isEmpty {
            result = removingSubstring(artist, from: result)
        }
        result = trimmingSeparators(result)
        result = unwrappingFirstBracketGroup(in: result)
        result = trimmingSeparators(result)
        guard let sanitized = RenamePlanner.sanitized(result), !sanitized.isEmpty else { return nil }
        return sanitized
    }

    /// An already-organized file's pressing subfolder, kept as-is rather
    /// than re-derived — the second path component under the (already
    /// song-named) top-level folder, if the file is nested that deep.
    private static func currentPressingName(for file: AudioFile, artistRoot: URL, topFolderName: String) -> String? {
        let songFolderComponents = artistRoot.appendingPathComponent(topFolderName)
            .standardizedFileURL.pathComponents
        let fileComponents = file.url.standardizedFileURL.pathComponents
        guard fileComponents.count > songFolderComponents.count + 1 else { return nil }
        return fileComponents[songFolderComponents.count]
    }

    private static func removingSubstring(_ needle: String, from haystack: String) -> String {
        guard !needle.isEmpty, let range = haystack.range(of: needle, options: .caseInsensitive) else { return haystack }
        return haystack.replacingCharacters(in: range, with: "")
    }

    private static func trimmingSeparators(_ value: String) -> String {
        var result = value.replacingOccurrences(of: #"^[\s\-–—]+"#, with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: #"[\s\-–—]+$"#, with: "", options: .regularExpression)
        return result
    }

    /// Unwraps only the first "(...)"/"[...]" group found — leaves any
    /// other bracket group in the string untouched (e.g. a genuine year).
    private static func unwrappingFirstBracketGroup(in value: String) -> String {
        guard let match = value.range(of: #"[\(\[][^()\[\]]*[\)\]]"#, options: .regularExpression) else { return value }
        let inner = value[match].dropFirst().dropLast()
        return value.replacingCharacters(in: match, with: inner)
    }

    // MARK: - Rule 6: name clashes

    private static func disambiguated(fileName: String, appending suffix: String) -> String {
        let ext = (fileName as NSString).pathExtension
        let base = (fileName as NSString).deletingPathExtension
        let clean = RenamePlanner.sanitized(suffix) ?? suffix
        return ext.isEmpty ? "\(base) (\(clean))" : "\(base) (\(clean)).\(ext)"
    }

    // MARK: - Artist root resolution

    /// Walks up from the file to the folder named `expectedArtist` and
    /// returns its parent — the artist root, however deep the file is
    /// nested under it. Loose files (no `expectedArtist`) resolve to their
    /// own containing folder, which *is* the artist root for those.
    private static func artistRootURL(for file: AudioFile) -> URL {
        guard let expectedArtist = file.expectedArtist else {
            return file.url.deletingLastPathComponent()
        }
        // Take the OUTERMOST folder with that name, not the nearest: a song
        // folder can contain a same-named subfolder ("Close To You/US 12''/
        // Close To You/"), and stopping at the inner one put the root too
        // deep, nesting new Song/Pressing folders again on every run.
        var candidate = file.url.deletingLastPathComponent()
        var outermostMatch: URL?
        while candidate.pathComponents.count > 1 {
            if candidate.lastPathComponent == expectedArtist { outermostMatch = candidate }
            candidate = candidate.deletingLastPathComponent()
        }
        return outermostMatch?.deletingLastPathComponent() ?? file.url.deletingLastPathComponent()
    }
}
