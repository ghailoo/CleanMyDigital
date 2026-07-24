//
//  RenamePlanner.swift
//  CleanMyDigital
//

import Foundation

/// One proposed rename: `file` currently at `currentName`, proposed to
/// become `proposedName` (same folder, extension unchanged in case).
struct RenameProposal: Identifiable, Sendable {
    let file: AudioFile
    let currentName: String
    let proposedName: String
    /// True when `proposedName` differs from `currentName` only by letter
    /// case — APFS is case-insensitive, so performing this rename needs a
    /// temporary intermediate name (`FileManager.moveItem` alone would see
    /// source and destination as the same path and no-op or fail).
    let isCaseOnlyChange: Bool

    var id: URL { file.url }
}

/// Derives a rename plan from a scanned file list. Pure and
/// filesystem-free (aside from reading the `AudioFile`s handed to it), so
/// it's fully unit-testable: no I/O, no security-scoped access, no async.
enum RenamePlanner {
    /// Builds proposals for every file across `files` that qualifies,
    /// grouped and collision-checked per folder (`files` don't need to be
    /// pre-filtered — only entries with both Artist and Title present ever
    /// get a proposal).
    static func plan(for files: [AudioFile]) -> [RenameProposal] {
        var proposals: [RenameProposal] = []
        let byFolder = Dictionary(grouping: files) { $0.url.deletingLastPathComponent() }
        for folderFiles in byFolder.values {
            proposals.append(contentsOf: planFolder(folderFiles))
        }
        return proposals
    }

    private struct Candidate {
        let file: AudioFile
        let baseName: String
        let ext: String
        let candidateName: String
        let willMove: Bool
    }

    private static func planFolder(_ folderFiles: [AudioFile]) -> [RenameProposal] {
        // Stable order so collision suffixes (" (2)", " (3)"…) are
        // deterministic run to run.
        let sortedFiles = folderFiles.sorted {
            $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending
        }

        let candidates: [Candidate] = sortedFiles.compactMap { file in
            guard !file.missingFields.contains(.artist), !file.missingFields.contains(.title),
                  let baseName = templatedBaseName(for: file)
            else { return nil }
            let ext = file.fileExtension.lowercased()
            let candidateName = "\(baseName).\(ext)"
            return Candidate(file: file, baseName: baseName, ext: ext,
                              candidateName: candidateName, willMove: candidateName != file.fileName)
        }

        // Every current filename in the folder is reserved by default —
        // including files that end up not moving (their proposed name
        // equals their current one) and non-candidate siblings. Only
        // vacate a name once we know that file is actually leaving it.
        var reserved = Set(folderFiles.map { $0.fileName.lowercased() })
        for candidate in candidates where candidate.willMove {
            reserved.remove(candidate.file.fileName.lowercased())
        }

        var proposals: [RenameProposal] = []
        for candidate in candidates where candidate.willMove {
            var finalName = candidate.candidateName
            var suffix = 2
            while reserved.contains(finalName.lowercased()) {
                finalName = "\(candidate.baseName) (\(suffix)).\(candidate.ext)"
                suffix += 1
            }
            reserved.insert(finalName.lowercased())

            let currentName = candidate.file.fileName
            let isCaseOnlyChange = finalName.lowercased() == currentName.lowercased()
            proposals.append(RenameProposal(
                file: candidate.file, currentName: currentName,
                proposedName: finalName, isCaseOnlyChange: isCaseOnlyChange))
        }
        return proposals
    }

    /// The proposed filename (without extension) for `file`, or nil if it
    /// doesn't qualify (Artist/Title missing, already excluded by the
    /// caller, but re-checked here defensively) or sanitizes to empty.
    private static func templatedBaseName(for file: AudioFile) -> String? {
        guard let artist = sanitized(file.artist), !artist.isEmpty,
              let title = sanitized(file.title), !title.isEmpty
        else { return nil }

        switch file.category {
        case .singles:
            let base = "\(artist) - \(title)"
            // The Title tag doesn't reliably carry the mix/version name —
            // a Discogs/MusicBrainz match can fill Title without it, which
            // would otherwise collapse a folder's many different mixes of
            // the same song down to the same proposed name (silently
            // losing the mix identifier to a meaningless " (2)", " (3)"
            // collision suffix). Pull it from the original filename
            // instead, which is why it's reliably there in this library.
            guard let mixSuffix = filenameMixSuffix(for: file),
                  !title.localizedCaseInsensitiveContains(mixSuffix)
            else { return base }
            return "\(base) \(mixSuffix)"
        case .albums, .compilations:
            if let trackNumber = file.trackNumber {
                let (part, _) = TagWriteHelpers.parseTrackPosition(trackNumber)
                if part > 0 {
                    return String(format: "%02d %@ - %@", part, artist, title)
                }
            }
            return "\(artist) - \(title)"
        }
    }

    /// The trailing parenthetical from the original filename — e.g. "(12"
    /// Mix)" — or nil if the filename doesn't end with one.
    private static func filenameMixSuffix(for file: AudioFile) -> String? {
        let baseName = (file.fileName as NSString).deletingPathExtension
        guard let range = baseName.range(of: #"\([^()]*\)\s*$"#, options: .regularExpression) else {
            return nil
        }
        return String(baseName[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Replaces path-hostile characters, collapses whitespace, and trims —
    /// safe to use directly as a macOS filename component. Shared with
    /// `CollectionPlanner`, which needs the same sanitization for release
    /// folder names.
    static func sanitized(_ value: String?) -> String? {
        guard let value else { return nil }
        var result = value.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        result = result.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return result
    }
}
