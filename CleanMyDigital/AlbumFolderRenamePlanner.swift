//
//  AlbumFolderRenamePlanner.swift
//  CleanMyDigital
//

import Foundation

/// One proposed folder rename: `group`'s containing folder, currently named
/// `currentFolderName`, proposed to become `proposedFolderName` (same
/// parent folder).
struct AlbumFolderRenameProposal: Identifiable, Sendable {
    let group: AlbumGroup
    let currentFolderName: String
    let proposedFolderName: String

    var id: URL { group.folderURL }
}

/// Derives a plan for renaming each scanned album's containing folder to
/// "Album Title (Year)", built from the group's own files' tags rather than
/// guessed from the folder's existing (often messy) name. Pure and
/// filesystem-free, like `RenamePlanner`/`CollectionPlanner` — and reuses
/// `RenamePlanner.sanitized` for the same path-hostile-character handling
/// rather than duplicating it.
enum AlbumFolderRenamePlanner {
    /// Builds proposals for every group with both an Album and Year tag,
    /// grouped and collision-checked per parent folder — two sibling album
    /// folders (e.g. two pressings sharing the same title and year) that
    /// would otherwise collide on the same proposed name get a " (2)",
    /// " (3)"… suffix instead of one silently overwriting the other, same
    /// precedent as `RenamePlanner`'s per-folder collision handling. Groups
    /// with no proposal (missing Album/Year, or already named correctly)
    /// simply produce no entry.
    static func plan(for groups: [AlbumGroup]) -> [AlbumFolderRenameProposal] {
        var proposals: [AlbumFolderRenameProposal] = []
        let byParent = Dictionary(grouping: groups) { $0.folderURL.deletingLastPathComponent() }
        for parentGroups in byParent.values {
            proposals.append(contentsOf: planParent(parentGroups))
        }
        return proposals
    }

    private struct Candidate {
        let group: AlbumGroup
        let baseName: String
        let willMove: Bool
    }

    private static func planParent(_ parentGroups: [AlbumGroup]) -> [AlbumFolderRenameProposal] {
        // Stable order so collision suffixes (" (2)", " (3)"…) are
        // deterministic run to run.
        let sortedGroups = parentGroups.sorted {
            $0.folderURL.lastPathComponent.localizedStandardCompare($1.folderURL.lastPathComponent) == .orderedAscending
        }

        let candidates: [Candidate] = sortedGroups.compactMap { group in
            guard let baseName = templatedFolderName(for: group) else { return nil }
            let currentName = group.folderURL.lastPathComponent
            return Candidate(group: group, baseName: baseName, willMove: baseName != currentName)
        }

        // Every current folder name among these sibling album groups is
        // reserved by default — including groups that end up not moving.
        // Only vacate a name once we know that group is actually leaving it.
        var reserved = Set(parentGroups.map { $0.folderURL.lastPathComponent.lowercased() })
        for candidate in candidates where candidate.willMove {
            reserved.remove(candidate.group.folderURL.lastPathComponent.lowercased())
        }

        var proposals: [AlbumFolderRenameProposal] = []
        for candidate in candidates where candidate.willMove {
            var finalName = candidate.baseName
            var suffix = 2
            while reserved.contains(finalName.lowercased()) {
                finalName = "\(candidate.baseName) (\(suffix))"
                suffix += 1
            }
            reserved.insert(finalName.lowercased())

            proposals.append(AlbumFolderRenameProposal(
                group: candidate.group,
                currentFolderName: candidate.group.folderURL.lastPathComponent,
                proposedFolderName: finalName))
        }
        return proposals
    }

    /// "Album Title (Year)", sanitized — nil when either tag is missing (or
    /// sanitizes to empty), since there's nothing to build a name from.
    private static func templatedFolderName(for group: AlbumGroup) -> String? {
        guard let albumTitle = RenamePlanner.sanitized(group.albumTitle), !albumTitle.isEmpty,
              let year = RenamePlanner.sanitized(group.year), !year.isEmpty
        else { return nil }
        return "\(albumTitle) (\(year))"
    }
}
