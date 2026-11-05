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
    /// Under this, a name that calls itself a radio edit or the original
    /// version is taken at its word and the file is left out altogether.
    /// Past it the clock disagrees too loudly to ignore, so the file stays
    /// in the list — unticked.
    static let shortFormGrace: TimeInterval = 300
    static let groupingValue = "Maxi Track"

    /// What a maxi version calls itself. A remix, a rework or a dub is
    /// almost always the long pressing, so it counts the same as "extended".
    static let nameHints = [
        "maxi", "extended", "remix", "rework", "dub", "long version",
        "club mix", "vocal mix", "dance mix", "12 inch", "12inch", "12\"",
    ]

    /// What a *short* version calls itself. Only consulted when nothing in
    /// the name says maxi, so "Original Extended Mix" still reads as a maxi.
    static let shortFormHints = [
        "radio", "edit", "original", "single version", "album version",
        "short", "7 inch", "7inch", "7\"",
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

            if nameSuggestsMaxi(file) {
                return MaxiTrackProposal(file: file, certainty: .nameAgrees)
            }
            if nameSuggestsShortForm(file), duration < shortFormGrace { return nil }
            return MaxiTrackProposal(file: file, certainty: .durationOnly)
        }
    }

    static func nameSuggestsMaxi(_ file: AudioFile) -> Bool {
        hint(nameHints, matches: file)
    }

    static func nameSuggestsShortForm(_ file: AudioFile) -> Bool {
        hint(shortFormHints, matches: file)
    }

    /// Whole words only, so "Dubfire" isn't a dub and "Editor" isn't an edit.
    private static func hint(_ hints: [String], matches file: AudioFile) -> Bool {
        let haystack = [file.fileName, file.title ?? ""].joined(separator: " ").lowercased()
        let separated = String(haystack.map { $0.isLetter || $0.isNumber || $0 == "\"" ? $0 : " " })
        let normalized = separated.split(separator: " ").joined(separator: " ")
        let padded = " \(normalized) "
        return hints.contains { padded.contains(" \($0) ") }
    }

    /// The tag write for one proposal.
    static func changes(for proposal: MaxiTrackProposal) -> TagChanges {
        var changes = TagChanges()
        changes.grouping = groupingValue
        return changes
    }
}
