//
//  LookupOutcome.swift
//  CleanMyDigital
//

import Foundation

/// A metadata provider CleanMyDigital can search — shared between the
/// manual lookup UI (as a tab selector) and stored batch-lookup outcomes.
enum MetadataProvider: String, CaseIterable, Identifiable, Sendable {
    case discogs = "Discogs"
    case musicBrainz = "MusicBrainz"

    var id: String { rawValue }
}

/// The top candidate a batch lookup found for a file, tagged by provider so
/// the UI can render either without the caller needing to know which.
enum LookupCandidate: Sendable {
    case discogs(DiscogsRelease)
    case musicBrainz(MusicBrainzRecording)
}

/// The result of an automated batch metadata lookup for one file, kept in
/// `LibraryScanner` (keyed by file URL) rather than on `AudioFile` itself —
/// it's a scan-session artifact, not part of the file's own metadata.
enum LookupOutcome: Sendable {
    case found(provider: MetadataProvider, candidate: LookupCandidate, fillableFields: Set<MetadataField>)
    case noMatch

    var isFound: Bool {
        if case .found = self { return true }
        return false
    }

    var provider: MetadataProvider? {
        if case .found(let provider, _, _) = self { return provider }
        return nil
    }
}
