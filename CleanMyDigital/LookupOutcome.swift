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

    /// Builds tag changes for exactly the fields in `fillable`, using each
    /// provider's release-level fields the same way the per-file comparison
    /// views (`MetadataLookupView.swift`'s `ComparisonView`/
    /// `MusicBrainzComparisonView`) do — shared here so a bulk "apply every
    /// found match" flow doesn't reimplement the mapping.
    ///
    /// `discogsToken` is only used for the `.discogs` case (Discogs'
    /// artwork endpoint requires the same auth header the search itself
    /// used); pass an empty string for `.musicBrainz` candidates, which
    /// ignore it.
    ///
    /// Discogs candidates never fill Title/Track Number here — Discogs
    /// search results are release-level only (see
    /// `DiscogsRelease.fillableFields`'s own doc comment), so `fillable`
    /// will never contain those fields for a Discogs candidate reached this
    /// way. Filling them still requires the per-file flow's separate
    /// tracklist-match step (`ComparisonView`'s own track selection); that's
    /// an existing, accepted limitation this shared path doesn't change.
    func buildChanges(fillable: Set<MetadataField>, discogsToken: String) async throws -> TagChanges {
        var changes = TagChanges()
        switch self {
        case .discogs(let release):
            if fillable.contains(.artist) { changes.artist = release.parsedArtist }
            if fillable.contains(.album) { changes.album = release.parsedReleaseTitle }
            if fillable.contains(.year) { changes.year = release.year }
            if fillable.contains(.genre) {
                changes.genre = release.combinedGenre.isEmpty ? nil : release.combinedGenre
            }
            if fillable.contains(.artwork), let url = release.coverImageURL ?? release.thumbURL {
                changes.artworkJPEG = try await ArtworkDownloader.downloadJPEG(
                    from: url, headers: ["Authorization": "Discogs token=\(discogsToken)"])
            }
        case .musicBrainz(let recording):
            if fillable.contains(.title) { changes.title = recording.title }
            if fillable.contains(.artist) { changes.artist = recording.artistNames }
            if fillable.contains(.album) { changes.album = recording.releaseTitle }
            if fillable.contains(.year) { changes.year = recording.yearString }
            if fillable.contains(.artwork), let url = recording.coverArtURL {
                changes.artworkJPEG = try await ArtworkDownloader.downloadJPEG(from: url)
            }
        }
        return changes
    }
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
