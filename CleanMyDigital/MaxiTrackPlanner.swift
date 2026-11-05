//
//  MaxiTrackPlanner.swift
//  CleanMyDigital
//

import Foundation

/// How sure we are that a long file really is a maxi/extended version.
enum MaxiTrackCertainty: Sendable {
    /// Long *and* the name says so — "Maxi", "Extended", "12 Inch", …
    case nameAgrees
    /// Long, but the name gives no hint either way. Worth a look.
    case durationOnly

    var label: String { self == .nameAgrees ? "Name agrees" : "Length only" }
}

struct MaxiTrackProposal: Identifiable, Sendable {
    let file: AudioFile
    let certainty: MaxiTrackCertainty
    var id: URL { file.url }
}

/// Picks the files that should carry the "Maxi Track" grouping tag: longer
/// than four minutes, and not already grouped as something else.
///
/// Pure — no filesystem, no network — so the rules are testable on their own.
enum MaxiTrackPlanner {
    /// "Longer than 4 minutes", exclusive: a track of exactly 4:00 isn't one.
    static let minimumDuration: TimeInterval = 240
    static let groupingValue = "Maxi Track"

    /// What a maxi version calls itself. Matched case-insensitively against
    /// the filename and the Title tag.
    static let nameHints = [
        "maxi", "extended", "12 inch", "12inch", "12\"", "long version", "club mix",
    ]

    static func plan(for files: [AudioFile]) -> [MaxiTrackProposal] {
        files.compactMap { file in
            guard file.isReadable,
                  let duration = file.duration, duration > minimumDuration,
                  // Never overwrite a grouping someone already uses for
                  // something else — the one exception is a file already
                  // tagged by this very feature, which is simply skipped.
                  file.grouping?.isEmpty ?? true
            else { return nil }

            return MaxiTrackProposal(
                file: file,
                certainty: nameSuggestsMaxi(file) ? .nameAgrees : .durationOnly)
        }
    }

    static func nameSuggestsMaxi(_ file: AudioFile) -> Bool {
        let haystack = [file.fileName, file.title ?? ""].joined(separator: " ")
        return nameHints.contains { haystack.localizedCaseInsensitiveContains($0) }
    }

    /// The tag write for one proposal.
    static func changes(for proposal: MaxiTrackProposal) -> TagChanges {
        var changes = TagChanges()
        changes.grouping = groupingValue
        return changes
    }
}
