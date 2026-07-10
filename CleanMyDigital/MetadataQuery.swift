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

    /// Strips a leading track number ("01 - ", "3.", "07_", "12)") and turns
    /// remaining underscores into spaces before searching.
    static func cleanedTrackTitle(from fileName: String) -> String {
        var name = (fileName as NSString).deletingPathExtension
        if let range = name.range(of: #"^\s*\d{1,3}[\s._\-)]+"#, options: .regularExpression) {
            name.removeSubrange(range)
        }
        name = name.replacingOccurrences(of: "_", with: " ")
        return name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
