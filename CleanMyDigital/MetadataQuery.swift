//
//  MetadataQuery.swift
//  CleanMyDigital
//

import Foundation

/// Shared search-term derivation for metadata providers (Discogs,
/// MusicBrainz) so every provider builds its query from the same cleaned
/// filename instead of each re-implementing its own heuristics.
enum MetadataQuery {
    static func artist(for file: AudioFile) -> String {
        file.expectedArtist ?? file.artist ?? ""
    }

    /// Strips a leading track number ("01 - ", "3.", "07_", "12)", or the
    /// same wrapped in parentheses — "(01) "), a leading "[Artist Name] "
    /// prefix when it fuzzily matches the known artist, and for Singles
    /// also strips an "Artist - " prefix, since maxi-single files are
    /// typically named "Artist - Title (Mix)" and sending the whole name
    /// (artist included) as the track query returns zero results from both
    /// providers. Albums and Compilations skip that split — legitimate
    /// track titles can contain " - " (e.g. "Track - Reprise").
    static func cleanedTrackTitle(from fileName: String, artist: String, category: LibraryCategory) -> String {
        var name = (fileName as NSString).deletingPathExtension
        if let range = name.range(of: #"^\s*\(?\d{1,3}[\s._\-)]+"#, options: .regularExpression) {
            name.removeSubrange(range)
        }

        // Unlike the Singles-only " - " split below, square brackets are an
        // unambiguous delimiter — a real track title essentially never
        // legitimately contains "[Artist Name]" the way it might contain a
        // bare " - " — so this applies for every category. Anchored to the
        // very start (after the track number above) rather than matched
        // anywhere, so a legitimate bracketed suffix elsewhere in the title
        // (e.g. "Track Title [Live]") is left alone.
        if let bracketRange = name.range(of: #"^\s*\[[^\[\]]+\]\s*"#, options: .regularExpression) {
            let bracketed = String(name[bracketRange])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .dropFirst().dropLast()
            let trimmedArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)

            if !trimmedArtist.isEmpty,
               bracketed.localizedCaseInsensitiveContains(trimmedArtist)
                    || trimmedArtist.localizedCaseInsensitiveContains(bracketed) {
                name.removeSubrange(bracketRange)
            }
        }

        if category == .singles, let dashRange = name.range(of: " - ") {
            let left = String(name[name.startIndex..<dashRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let right = String(name[dashRange.upperBound...])
            let trimmedArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmedArtist.isEmpty {
                // No artist to compare against — this library's filenames
                // all follow the "Artist - Title" convention, so still
                // prefer the part after the dash.
                name = right
            } else if left.localizedCaseInsensitiveContains(trimmedArtist)
                        || trimmedArtist.localizedCaseInsensitiveContains(left) {
                // Covers collaborations like "808 State & Ub40" or
                // "808 State : Ub40" filed under the "808 State" folder.
                name = right
            }
        }

        name = name.replacingOccurrences(of: "_", with: " ")
        return name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Strips a single trailing parenthetical — "Pacific 0101 (Remix Edit)"
    /// → "Pacific 0101" — for a fallback search when the full title
    /// (including a mix/edit name) returns zero results. Returns nil when
    /// there's nothing to strip, so callers know not to retry.
    static func strippingTrailingParenthetical(from trackTitle: String) -> String? {
        guard let range = trackTitle.range(of: #"\s*\([^()]*\)\s*$"#, options: .regularExpression) else {
            return nil
        }
        let stripped = trackTitle.replacingCharacters(in: range, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.isEmpty ? nil : stripped
    }
}
