//
//  DiscogsClient.swift
//  CleanMyDigital
//

import Foundation

/// A single release candidate returned by Discogs' `/database/search` endpoint.
struct DiscogsRelease: Identifiable, Decodable, Sendable {
    let id: Int
    let title: String
    let year: String?
    let genre: [String]?
    let style: [String]?
    let label: [String]?
    let format: [String]?
    let thumb: String?
    let coverImage: String?

    enum CodingKeys: String, CodingKey {
        case id, title, year, genre, style, label, format, thumb
        case coverImage = "cover_image"
    }

    /// Discogs formats release search results as "Artist - Release Title".
    var parsedArtist: String? {
        guard let range = title.range(of: " - ") else { return nil }
        let artist = title[title.startIndex..<range.lowerBound].trimmingCharacters(in: .whitespaces)
        return artist.isEmpty ? nil : artist
    }

    var parsedReleaseTitle: String? {
        guard let range = title.range(of: " - ") else { return title }
        let releaseTitle = title[range.upperBound...].trimmingCharacters(in: .whitespaces)
        return releaseTitle.isEmpty ? nil : releaseTitle
    }

    var combinedGenre: String {
        ((genre ?? []) + (style ?? [])).joined(separator: ", ")
    }

    /// The release's physical format(s) — e.g. "Vinyl, LP, Album" — empty
    /// when Discogs didn't report any.
    var formattedFormat: String {
        (format ?? []).joined(separator: ", ")
    }

    var thumbURL: URL? { thumb.flatMap(URL.init) }
    var coverImageURL: URL? { coverImage.flatMap(URL.init) }
    var releasePageURL: URL? { URL(string: "https://www.discogs.com/release/\(id)") }

    /// Which of this file's missing fields this candidate has data for.
    /// Search results only cover release-level metadata — there's no
    /// per-track title or track number, so those never come back fillable.
    func fillableFields(missing: [MetadataField]) -> Set<MetadataField> {
        var fillable: Set<MetadataField> = []
        if missing.contains(.artist), parsedArtist != nil { fillable.insert(.artist) }
        if missing.contains(.album), parsedReleaseTitle != nil { fillable.insert(.album) }
        if missing.contains(.year), let year, !year.isEmpty { fillable.insert(.year) }
        if missing.contains(.genre), !combinedGenre.isEmpty { fillable.insert(.genre) }
        if missing.contains(.artwork), thumbURL != nil || coverImageURL != nil { fillable.insert(.artwork) }
        return fillable
    }
}

private struct DiscogsSearchResponse: Decodable {
    let results: [DiscogsRelease]
}

enum DiscogsError: LocalizedError {
    case missingToken
    case unauthorized
    case rateLimited
    case http(Int)
    case invalidResponse
    case underlying(Error)

    var errorDescription: String? {
        switch self {
        case .missingToken:
            return "Add a Discogs personal access token in Settings to search."
        case .unauthorized:
            return "Discogs rejected this token. Check it in Settings and try again."
        case .rateLimited:
            return "Discogs rate limit reached. Wait a moment and try again."
        case .http(let code):
            return "Discogs returned an unexpected error (HTTP \(code))."
        case .invalidResponse:
            return "Discogs returned a response CleanMyDigital couldn't read."
        case .underlying(let error):
            return error.localizedDescription
        }
    }
}

/// A Discogs release's full detail: tracklist plus release-level credits.
/// Fetched from `/releases/{id}` only once a candidate is selected, since
/// it's a heavier call than the search endpoint.
struct DiscogsReleaseDetail: Decodable, Sendable {
    let id: Int
    let title: String
    let year: Int?
    let genres: [String]?
    let styles: [String]?
    let artists: [ArtistCredit]?
    private let tracklist: [RawTrack]

    struct ArtistCredit: Decodable, Sendable {
        let name: String
    }

    fileprivate struct RawTrack: Decodable, Sendable {
        let position: String?
        let title: String?
        let duration: String?
        let type_: String?
    }

    /// Only the actual playable tracks — Discogs also lists section
    /// headings ("Side A") and indices in the same array.
    var tracks: [DiscogsTrack] {
        tracklist.compactMap { raw in
            guard (raw.type_ ?? "track") == "track",
                  let title = raw.title, !title.isEmpty
            else { return nil }
            return DiscogsTrack(position: raw.position ?? "", title: title, duration: raw.duration)
        }
    }

    var artistNames: String {
        (artists ?? []).map { Self.stripDisambiguation($0.name) }.joined(separator: ", ")
    }

    var combinedGenre: String {
        ((genres ?? []) + (styles ?? [])).joined(separator: ", ")
    }

    var yearString: String? {
        guard let year, year > 0 else { return nil }
        return String(year)
    }

    /// Discogs appends " (2)" etc. to artist names that collide with an
    /// existing one in their database.
    private static func stripDisambiguation(_ name: String) -> String {
        name.replacingOccurrences(of: #"\s\(\d+\)$"#, with: "", options: .regularExpression)
    }

    /// Case/diacritic-insensitive contains match, in either direction,
    /// between a tracklist title and the cleaned filename. Falls back to
    /// nil so the caller can let the user pick manually.
    ///
    /// Used to fill a *single* file's Title/Track Number tag, where one
    /// file can only hold one title — for that, one best match is correct
    /// and this should keep returning exactly one. For crediting a combined
    /// audio file against *every* track it plausibly covers, see
    /// `allMatchedTracks(for:)` instead.
    func autoMatchedTrack(for cleanedFileName: String) -> DiscogsTrack? {
        let normalizedFile = Self.normalize(cleanedFileName)
        guard !normalizedFile.isEmpty else { return nil }
        return tracks.first { track in
            let normalizedTrack = Self.normalize(track.title)
            guard !normalizedTrack.isEmpty else { return false }
            return normalizedTrack.contains(normalizedFile) || normalizedFile.contains(normalizedTrack)
        }
    }

    /// Every track this cleaned filename plausibly covers: the same single
    /// best match `autoMatchedTrack(for:)` would find, plus any *other*
    /// track whose normalized title is itself a substring of the cleaned
    /// filename — the "file contains track" direction only (not the
    /// reverse `autoMatchedTrack` also checks), since this exists to credit
    /// a combined/segued rip like "06 - Misterio - Interlude.flac" for
    /// covering both a "Mistério" and a separate "Interlude" track
    /// concatenated into its name, not to find a single track a short
    /// filename happens to be an abbreviation of.
    ///
    /// Two guards keep this from over-matching on coincidental substrings:
    /// - Nothing is returned at all unless the file already has a primary
    ///   match via `autoMatchedTrack(for:)` — this scopes the search to
    ///   files already reasonably confident to belong to this release,
    ///   rather than substring-matching every track against every file in
    ///   the album regardless of whether anything matched to begin with.
    /// - Beyond that primary match, only tracks with a normalized title of
    ///   at least `minimumSupplementaryMatchLength` characters are
    ///   considered, so a short/generic title (e.g. "Love") can't tack
    ///   itself on as a substring of an unrelated word elsewhere in the
    ///   filename.
    ///
    /// Only ever used for the album-completeness "what's covered" check —
    /// never for filling tags, where `autoMatchedTrack(for:)`'s single-match
    /// behavior is what's wanted and stays unchanged.
    func allMatchedTracks(for cleanedFileName: String) -> [DiscogsTrack] {
        guard let primary = autoMatchedTrack(for: cleanedFileName) else { return [] }
        let normalizedFile = Self.normalize(cleanedFileName)
        guard !normalizedFile.isEmpty else { return [primary] }

        let supplementary = tracks.filter { track in
            guard track.id != primary.id else { return false }
            let normalizedTrack = Self.normalize(track.title)
            guard normalizedTrack.count >= Self.minimumSupplementaryMatchLength else { return false }
            return normalizedFile.contains(normalizedTrack)
        }
        return [primary] + supplementary
    }

    /// Below this normalized length, a track title is common/generic enough
    /// (e.g. "Love", "Go") that treating its mere appearance as a substring
    /// of some other file's name as a real match would produce far more
    /// false positives than genuine combined-track credits. Deliberately
    /// excludes 4-letter titles too ("Love" itself included) — for this
    /// bonus-credit path, erring toward under-crediting (a real compound
    /// match reads as "possibly missing" instead) is safer than the
    /// alternative failure mode this feature exists to fix: silently
    /// marking an album complete when it isn't.
    private static let minimumSupplementaryMatchLength = 5

    /// Case-, diacritic- and punctuation-insensitive, whitespace collapsed —
    /// so "Ain't Talkin' 'Bout Dub" matches "Ain't Talkin' Bout Dub".
    private static func normalize(_ string: String) -> String {
        let folded = string.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        let kept = folded.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        return String(kept).split(separator: " ").joined(separator: " ")
    }
}

struct DiscogsTrack: Identifiable, Hashable, Sendable {
    let position: String
    let title: String
    let duration: String?

    var id: String { position + "|" + title }

    /// Discogs writes "6:13", and occasionally "1:06:13" for a long mix.
    /// Anything it can't read — an empty string, a stray word — is nil
    /// rather than zero, so an unknown length never reads as a match.
    var seconds: Int? {
        guard let duration else { return nil }
        let parts = duration.split(separator: ":")
        guard (2...3).contains(parts.count) else { return nil }
        var total = 0
        for part in parts {
            guard let value = Int(part), value >= 0 else { return nil }
            total = total * 60 + value
        }
        return total
    }
}

extension DiscogsReleaseDetail {
    /// How far apart two timings can be and still be the same recording.
    /// From the user's own tally over several days of matching by hand: a
    /// correct pressing routinely reads 4-6 seconds off what the file
    /// measures, because Discogs' times are rounded by whoever typed them
    /// and rips differ in lead-in and fade. Seven gives that a little room
    /// without reaching the next mix, which is usually half a minute away.
    static let durationTolerance = 7

    /// Whether this release's tracklist holds `track` *and* lists it at the
    /// file's own length — the title and the clock agreeing on one entry.
    /// Much stronger than either alone, and the case an album defeats: the
    /// release is called "Lets Push It" while the file is "Just Like
    /// Before", track 5 on it, so the release's own name says nothing.
    func hasTrack(named track: String, ofDuration duration: TimeInterval) -> Bool {
        guard duration > 0,
              let matched = autoMatchedTrack(for: track),
              let seconds = matched.seconds
        else { return false }
        return abs(seconds - Int(duration.rounded())) <= Self.durationTolerance
    }

    /// Whether this release lists a track as long as `duration`.
    func hasTrack(ofDuration duration: TimeInterval) -> Bool {
        guard duration > 0 else { return false }
        let target = Int(duration.rounded())
        return tracks.contains { track in
            guard let seconds = track.seconds else { return false }
            return abs(seconds - target) <= Self.durationTolerance
        }
    }
}

extension [DiscogsTrack] {
    /// Titles of the tracks in this list with no corresponding entry among
    /// `matchedTrackIDs` — used to determine whether a release's tracklist
    /// is fully covered by an album's locally matched files.
    func missingTitles(matchedTrackIDs: Set<String>) -> [String] {
        filter { !matchedTrackIDs.contains($0.id) }.map(\.title)
    }
}

/// Caches release details in memory for the app's lifetime so revisiting a
/// candidate — or another file from the same release — doesn't re-spend
/// Discogs' 60 requests/minute rate limit.
private actor DiscogsReleaseDetailCache {
    static let shared = DiscogsReleaseDetailCache()

    private var storage: [Int: DiscogsReleaseDetail] = [:]

    func cached(_ id: Int) -> DiscogsReleaseDetail? { storage[id] }

    func store(_ detail: DiscogsReleaseDetail, for id: Int) { storage[id] = detail }
}

/// Paces Discogs requests to ~1/second (well under their 60/minute limit)
/// and backs off further whenever Discogs itself reports 429.
private actor DiscogsRateLimiter {
    static let shared = DiscogsRateLimiter()

    private let minimumInterval: TimeInterval = 1.0
    private let backoffInterval: TimeInterval = 5.0
    private var nextAllowedDate: Date?

    func waitIfNeeded() async {
        if let nextAllowedDate {
            let remaining = nextAllowedDate.timeIntervalSinceNow
            if remaining > 0 {
                try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            }
        }
        nextAllowedDate = Date().addingTimeInterval(minimumInterval)
    }

    func registerRateLimited() {
        nextAllowedDate = Date().addingTimeInterval(backoffInterval)
    }
}

/// A minimal client for Discogs' public `/database/search` and
/// `/releases/{id}` endpoints.
enum DiscogsClient {
    private static let userAgent = "CleanMyDigital/1.0 +personal use"

    /// Searches with the given track title; if that comes back with zero
    /// results, retries once with a trailing "(Mix)"-style parenthetical
    /// stripped, since a mix/edit name Discogs doesn't recognize can shadow
    /// an otherwise-findable release, then once more with whatever trails
    /// the last " - " dropped (a label or compilation name the filename
    /// carried along). If that's still empty and
    /// `allowArtistOnlyFallback` is true, retries once more with just the
    /// artist (empty track) — Discogs' track-level search is much narrower
    /// than its artist-only search and can fail on small differences
    /// (accents, apostrophes, an unindexed track title) that an artist
    /// search shrugs off, especially for less mainstream releases. Skipped
    /// when `artist` is empty (the `q`-based free-text fallback below
    /// already covers that case) or when `track` is already empty (the
    /// first attempt was already effectively artist-only, so retrying would
    /// just repeat the same request). A thrown error (bad token, rate
    /// limit, network failure) propagates immediately without retrying at
    /// any tier.
    ///
    /// `allowArtistOnlyFallback` defaults to true for the interactive
    /// "Find on Discogs" flow, where a human reviews the result list before
    /// anything is applied — a broader "any of this artist's releases"
    /// result set is strictly useful there. The automated batch "Find All
    /// Metadata" lookup (`LibraryScanner.lookupOutcome`) passes `false`:
    /// it picks `releases.first` and applies its Genre/Year/Artwork with no
    /// human review, so trading "found nothing" for "confidently applied
    /// the wrong release's data" would be a regression, not a fix, for that
    /// path.
    ///
    /// `album`, when non-empty, is sent alongside artist/track as
    /// `release_title` to narrow the search — useful for Albums/Compilations
    /// files where the release title is already known from the tag or folder.
    static func search(
        artist: String, track: String, album: String = "", token: String, allowArtistOnlyFallback: Bool = true
    ) async throws -> [DiscogsRelease] {
        guard !token.isEmpty else { throw DiscogsError.missingToken }

        let results = try await performSearch(artist: artist, track: track, album: album, token: token)
        if !results.isEmpty { return results }

        if let fallbackTrack = MetadataQuery.strippingTrailingParenthetical(from: track) {
            let fallbackResults = try await performSearch(artist: artist, track: fallbackTrack, album: album, token: token)
            if !fallbackResults.isEmpty { return fallbackResults }
        }

        // Then without whatever trails the last " - " — filenames carry a
        // label or compilation name there ("Doggystyle - Crydamoure 2")
        // that Discogs never indexes as part of the track.
        if let fallbackTrack = MetadataQuery.strippingTrailingDashSegment(from: track) {
            let fallbackResults = try await performSearch(artist: artist, track: fallbackTrack, album: album, token: token)
            if !fallbackResults.isEmpty { return fallbackResults }
        }

        guard shouldAttemptArtistOnlyFallback(
            artist: artist, track: track, allowArtistOnlyFallback: allowArtistOnlyFallback)
        else { return [] }
        return try await performSearch(artist: artist, track: "", album: album, token: token)
    }

    /// The gating decision behind `search`'s last retry tier — factored
    /// out, like `searchURL`, so it can be verified without hitting the
    /// network. See `search`'s doc comment for what each condition guards
    /// against.
    static func shouldAttemptArtistOnlyFallback(artist: String, track: String, allowArtistOnlyFallback: Bool) -> Bool {
        allowArtistOnlyFallback && !artist.isEmpty && !track.isEmpty
    }

    /// Searches for a compilation by its release title alone (free-text
    /// `q=`, via `searchAlbum`) — never with the track term, which only
    /// ever shadowed releases Discogs finds by title (the "Ice MC — It's A
    /// Rainy Day" / "Maxi Power Best Of 94" case), and never with
    /// artist "Various", which misses series Discogs credits to a compiler
    /// instead ("Hôtel Costes 10"). The track is confirmed afterwards
    /// against the picked release's tracklist instead — by the user in the
    /// lookup sheet, or by `firstRelease(containingTrack:in:token:)` in the
    /// batch lookup.
    ///
    /// A user-typed artist is still honored (`artist=`+`release_title=`).
    /// With no album term at all, falls back to a per-track search.
    static func searchCompilation(
        artist: String, track: String, album: String, token: String
    ) async throws -> [DiscogsRelease] {
        guard !album.isEmpty else {
            return try await searchTrack(
                artist: artist, track: track, token: token, allowArtistOnlyFallback: false
            ).releases
        }
        return try await searchAlbum(artist: artist, album: album, token: token)
    }

    /// The first of the top `limit` releases whose tracklist contains
    /// `track` — how the no-review batch lookup confirms a compilation
    /// match, since a title-only search can't tell volumes or pressings
    /// apart. Release details are cached, so every file from the same
    /// compilation shares one detail fetch per release.
    /// ponytail: stops at `limit` releases; raise it if long series miss.
    static func firstRelease(
        containingTrack track: String, in releases: [DiscogsRelease], token: String, limit: Int = 5
    ) async -> DiscogsRelease? {
        for release in releases.prefix(limit) {
            guard let detail = try? await releaseDetail(id: release.id, token: token) else { continue }
            if detail.autoMatchedTrack(for: track) != nil { return release }
        }
        return nil
    }

    /// The result of a per-file (non-compilation) `searchTrack` search — the
    /// same releases it would return, plus whether they came from its
    /// broader title-only retry tier. A result found that way used no
    /// artist term at all, so a caller showing these to a human should say
    /// so rather than let it read as a confirmed artist+title match.
    struct TrackSearchResult: Sendable {
        let releases: [DiscogsRelease]
        let usedBroaderTitleOnlyFallback: Bool
    }

    /// Searches for a single track using Discogs' free-text `q=` search
    /// rather than its structured `artist=`/`track=` params. Verified
    /// against the live API on a real case ("The KLF" /
    /// "3 A.M. Eternal (Live At The S.S.L.)"): every structured
    /// `artist=`+`track=` combination tried — full title, mix stripped,
    /// even the exact correct artist and title — returned either zero
    /// results or the wrong release, while `q=` with "Artist - Title"
    /// combined found the exact pressing on the first try. Discogs' `track=`
    /// param searches its per-track index, which is evidently far more
    /// patchy than its general free-text index. This is specific to
    /// `track=`, not to structured params generally — `searchCompilation`'s
    /// `artist=`+`release_title=` shape is unrelated and unaffected; see its
    /// doc comment.
    ///
    /// Deliberately does NOT strip a mix/version parenthetical from `track`
    /// before combining it into `q` — the same verification found that
    /// doing so turns an exact match into wrong, generic-pressing results.
    /// See `MetadataQuery.cleanedTrackTitle`'s doc comment.
    ///
    /// Deliberately does NOT send `album` as `release_title` alongside `q`
    /// either, even when the caller has one. `searchURL`'s own free-text
    /// branch already drops `album` unconditionally whenever `artist` is
    /// empty, which is effectively what this function does by routing
    /// through it with `artist: ""` — see
    /// `fallsBackToQParamWhenArtistIsEmptyRegardlessOfAlbum`. That's the
    /// right call here too: for Singles specifically, the derived album
    /// term is often just the containing folder name, which for Singles
    /// carries no reliable meaning at all (files may sit loose in any
    /// folder) — sending it as an additional filter would risk silently
    /// reintroducing exactly the "nonsense structured term shadows a
    /// findable release" failure this function exists to fix.
    ///
    /// If the primary combined search returns zero results, retries with the
    /// artist still attached but a trailing "(Mix)" dropped, then with just
    /// `track` (mix included) — dropping the artist rather than any part of
    /// the title, since the title is the strongest identifying signal here,
    /// not a redundant artist prefix. When
    /// `allowArtistOnlyFallback` is false (the no-review batch lookup), that
    /// retry keeps only releases whose own artist matches
    /// (`releaseArtist(of:matches:)`), so it never applies a same-titled but
    /// wrong track's release.
    static func searchTrack(
        artist: String, track: String, token: String,
        fallbackTrack: String? = nil, allowArtistOnlyFallback: Bool = true
    ) async throws -> TrackSearchResult {
        guard !token.isEmpty else { throw DiscogsError.missingToken }

        let combined = combinedQuery(artist: artist, track: track)
        guard !combined.isEmpty else {
            return TrackSearchResult(releases: [], usedBroaderTitleOnlyFallback: false)
        }

        let results = try await performSearch(artist: "", track: combined, album: "", token: token)
        if !results.isEmpty {
            return TrackSearchResult(releases: results, usedBroaderTitleOnlyFallback: false)
        }

        guard !artist.isEmpty, !track.isEmpty else {
            return TrackSearchResult(releases: [], usedBroaderTitleOnlyFallback: false)
        }

        // The filename's wording of the same title, when the tag's found
        // nothing — a tag can be abbreviated, misspelled or name a different
        // pressing than the file actually is. Still a full combined search,
        // so this stays a match on both terms.
        if let fallbackTrack, !fallbackTrack.isEmpty, fallbackTrack != track {
            let results = try await performSearch(
                artist: "", track: combinedQuery(artist: artist, track: fallbackTrack), album: "", token: token)
            if !results.isEmpty {
                return TrackSearchResult(releases: results, usedBroaderTitleOnlyFallback: false)
            }
        }
        // Still with the artist, but without a trailing "(Mix)" Discogs may
        // not know — a weaker pressing match beats no match, and keeping the
        // artist means this stays a full match, not a title-only one.
        if let withoutMix = MetadataQuery.strippingTrailingParenthetical(from: track) {
            let results = try await performSearch(
                artist: "", track: combinedQuery(artist: artist, track: withoutMix), album: "", token: token)
            if !results.isEmpty {
                return TrackSearchResult(releases: results, usedBroaderTitleOnlyFallback: false)
            }
        }
        // A title-only result whose own artist is this artist is as good as a
        // combined hit: listed first, and no "title only" warning. Without a
        // human reviewing (batch lookup), only those are kept — never a
        // same-titled track by someone else.
        let broaderResults = try await performSearch(artist: "", track: track, album: "", token: token)
        let matching = broaderResults.filter { releaseArtist(of: $0, matches: artist) }
        guard allowArtistOnlyFallback else {
            return TrackSearchResult(releases: matching, usedBroaderTitleOnlyFallback: false)
        }
        let others = broaderResults.filter { !releaseArtist(of: $0, matches: artist) }
        return TrackSearchResult(releases: matching + others, usedBroaderTitleOnlyFallback: matching.isEmpty && !others.isEmpty)
    }

    /// Whether a release's own artist (Discogs' "Artist - Title") is `artist`,
    /// ignoring case, accents, punctuation, "feat." credits and Discogs' "*" /
    /// " (2)" name suffixes. Either may contain the other, so "Wareband"
    /// matches "Wareband Featuring Tad Robinson" and "808 State & UB40".
    /// A long name misspelled in the file's own tag still matches, within a
    /// typo or two — see `MetadataQuery.isNearMatch`.
    static func releaseArtist(of release: DiscogsRelease, matches artist: String) -> Bool {
        guard let releaseArtist = release.parsedArtist else { return false }
        func key(_ name: String) -> String {
            MetadataQuery.strippingFeaturedArtist(from: name)
                .replacingOccurrences(of: #"\s\(\d+\)"#, with: "", options: .regularExpression)
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
                .unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
                .map(String.init).joined()
        }
        let found = key(releaseArtist), wanted = key(artist)
        // Very short names ("X") would be contained in almost anything.
        guard found.count >= 3, wanted.count >= 3 else { return !found.isEmpty && found == wanted }
        if found.contains(wanted) || wanted.contains(found) { return true }
        // A typo in the file's own tag ("Kings Of Tommorow") shouldn't demote
        // the right release to a title-only match.
        return MetadataQuery.isNearMatch(found, wanted)
    }

    /// Combines an artist and a track title into one free-text search term
    /// — "Artist - Title", or just whichever of the two is non-empty.
    /// Factored out so it's verifiable without hitting the network.
    static func combinedQuery(artist: String, track: String) -> String {
        [artist, track].filter { !$0.isEmpty }.joined(separator: " - ")
    }

    /// Builds the `/database/search` query items for an artist+track(+album)
    /// lookup — factored out from `performSearch` so the request shape can
    /// be verified without hitting the network.
    ///
    /// `track` is only appended when non-empty, so an artist-only request
    /// never sends an empty "track" param. With no artist, `q` is the track,
    /// or the album when the track is blank too.
    static func searchURL(artist: String, track: String, album: String) -> URL? {
        var components = URLComponents(string: "https://api.discogs.com/database/search")!
        var queryItems = [
            URLQueryItem(name: "type", value: "release"),
            URLQueryItem(name: "per_page", value: "10"),
        ]
        if !artist.isEmpty {
            queryItems.append(URLQueryItem(name: "artist", value: artist))
            if !track.isEmpty {
                queryItems.append(URLQueryItem(name: "track", value: track))
            }
            if !album.isEmpty {
                queryItems.append(URLQueryItem(name: "release_title", value: album))
            }
        } else {
            // Artist and track both blank (e.g. a compilation looked up by
            // album alone): an empty `q` makes Discogs return arbitrary
            // releases, so search the album title instead.
            queryItems.append(URLQueryItem(name: "q", value: track.isEmpty ? album : track))
        }
        components.queryItems = queryItems
        return components.url
    }

    private static func performSearch(
        artist: String, track: String, album: String, token: String
    ) async throws -> [DiscogsRelease] {
        guard let url = searchURL(artist: artist, track: track, album: album) else {
            throw DiscogsError.invalidResponse
        }

        let data = try await performRequest(makeRequest(url: url, token: token))
        do {
            return try JSONDecoder().decode(DiscogsSearchResponse.self, from: data).results
        } catch {
            throw DiscogsError.underlying(error)
        }
    }

    /// Searches by release/album title instead of by track — used to check
    /// whether an album folder has its full tracklist, rather than to
    /// identify a single track.
    static func searchAlbum(artist: String, album: String, token: String) async throws -> [DiscogsRelease] {
        guard !token.isEmpty else { throw DiscogsError.missingToken }

        var components = URLComponents(string: "https://api.discogs.com/database/search")!
        var queryItems = [
            URLQueryItem(name: "type", value: "release"),
            URLQueryItem(name: "per_page", value: "10"),
        ]
        if !artist.isEmpty {
            queryItems.append(URLQueryItem(name: "artist", value: artist))
            if !album.isEmpty {
                queryItems.append(URLQueryItem(name: "release_title", value: album))
            }
        } else {
            queryItems.append(URLQueryItem(name: "q", value: album))
        }
        components.queryItems = queryItems

        guard let url = components.url else { throw DiscogsError.invalidResponse }

        let data = try await performRequest(makeRequest(url: url, token: token))
        do {
            return try JSONDecoder().decode(DiscogsSearchResponse.self, from: data).results
        } catch {
            throw DiscogsError.underlying(error)
        }
    }

    static func releaseDetail(id: Int, token: String) async throws -> DiscogsReleaseDetail {
        if let cached = await DiscogsReleaseDetailCache.shared.cached(id) {
            return cached
        }
        guard !token.isEmpty else { throw DiscogsError.missingToken }
        guard let url = URL(string: "https://api.discogs.com/releases/\(id)") else {
            throw DiscogsError.invalidResponse
        }

        let data = try await performRequest(makeRequest(url: url, token: token))
        let detail: DiscogsReleaseDetail
        do {
            detail = try JSONDecoder().decode(DiscogsReleaseDetail.self, from: data)
        } catch {
            throw DiscogsError.underlying(error)
        }
        await DiscogsReleaseDetailCache.shared.store(detail, for: id)
        return detail
    }

    private static func makeRequest(url: URL, token: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("Discogs token=\(token)", forHTTPHeaderField: "Authorization")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    private static func performRequest(_ request: URLRequest) async throws -> Data {
        await DiscogsRateLimiter.shared.waitIfNeeded()

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw DiscogsError.underlying(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DiscogsError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200..<300:
            return data
        case 401:
            throw DiscogsError.unauthorized
        case 429:
            await DiscogsRateLimiter.shared.registerRateLimited()
            throw DiscogsError.rateLimited
        default:
            throw DiscogsError.http(httpResponse.statusCode)
        }
    }
}

/// Derives Discogs search terms from a scanned file.
struct DiscogsQuery {
    let artist: String
    let track: String
    /// The file's own Album tag when it has one, else its containing
    /// folder name, with a trailing disc/CD marker stripped either way —
    /// see `MetadataQuery.albumSearchTerm(for:)`.
    let album: String

    /// The *filename's* reading of the track title, when it differs from
    /// `track` — i.e. when `track` came from the Title tag. Nil otherwise.
    /// `DiscogsClient.searchTrack` retries with it when the tag's wording
    /// finds nothing, so a wrong or over-abbreviated tag can't hide a
    /// release the filename would have found.
    let fileNameTrack: String?

    /// Compilations leave `artist` blank: Discogs credits a compilation to
    /// "Various" or to its compiler, never to one track's artist, so the
    /// release is searched by `album` alone (`DiscogsClient.searchCompilation`)
    /// and `track` is matched against its tracklist afterwards. `track` is
    /// still populated — it's what that tracklist match uses, and what the
    /// user needs to see to judge the result.
    init(for file: AudioFile) {
        artist = file.category == .compilations ? "" : MetadataQuery.artist(for: file)
        track = MetadataQuery.trackSearchTerm(for: file, artist: artist)
        let parsed = MetadataQuery.cleanedTrackTitle(
            from: file.fileName, artist: artist, category: file.category)
        fileNameTrack = parsed.isEmpty || parsed == track ? nil : parsed
        album = MetadataQuery.albumSearchTerm(for: file)
    }
}

/// Derives Discogs search terms for an album-completeness check — same
/// spirit as `DiscogsQuery`, but keyed on the album/folder rather than a
/// single track title.
struct DiscogsAlbumQuery {
    let artist: String
    let album: String

    /// Same blank-artist rule as `DiscogsQuery` for `.compilations` — see its
    /// doc comment. `group.artist` (the folder name) is never a real artist
    /// for a compilation, so the release is searched by title alone.
    init(for group: AlbumGroup) {
        artist = group.category == .compilations ? "" : (group.artist ?? "")
        album = MetadataQuery.strippingDiscAnnotation(from: group.albumTitle ?? group.folderURL.lastPathComponent)
    }
}
