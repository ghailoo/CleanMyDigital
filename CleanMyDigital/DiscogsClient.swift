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
    let thumb: String?
    let coverImage: String?

    enum CodingKeys: String, CodingKey {
        case id, title, year, genre, style, label, thumb
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

    private static func normalize(_ string: String) -> String {
        string.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct DiscogsTrack: Identifiable, Hashable, Sendable {
    let position: String
    let title: String
    let duration: String?

    var id: String { position + "|" + title }
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
    /// an otherwise-findable release. A thrown error (bad token, rate
    /// limit, network failure) propagates immediately without retrying.
    ///
    /// `album`, when non-empty, is sent alongside artist/track as
    /// `release_title` to narrow the search — useful for Albums/Compilations
    /// files where the release title is already known from the tag or folder.
    static func search(artist: String, track: String, album: String = "", token: String) async throws -> [DiscogsRelease] {
        guard !token.isEmpty else { throw DiscogsError.missingToken }

        let results = try await performSearch(artist: artist, track: track, album: album, token: token)
        if !results.isEmpty { return results }

        guard let fallbackTrack = MetadataQuery.strippingTrailingParenthetical(from: track) else {
            return results
        }
        return try await performSearch(artist: artist, track: fallbackTrack, album: album, token: token)
    }

    /// Builds the `/database/search` query items for an artist+track(+album)
    /// lookup — factored out from `performSearch` so the request shape can
    /// be verified without hitting the network.
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
            queryItems.append(URLQueryItem(name: "q", value: track))
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
    /// The file's own Album tag, if present — an initial guess to narrow
    /// the search on Albums/Compilations files. Empty when the file has no
    /// Album tag yet, same as `artist`/`track` fall back to an empty guess.
    let album: String

    init(for file: AudioFile) {
        artist = MetadataQuery.artist(for: file)
        track = MetadataQuery.cleanedTrackTitle(from: file.fileName, artist: artist, category: file.category)
        album = file.album ?? ""
    }
}

/// Derives Discogs search terms for an album-completeness check — same
/// spirit as `DiscogsQuery`, but keyed on the album/folder rather than a
/// single track title.
struct DiscogsAlbumQuery {
    let artist: String
    let album: String

    init(for group: AlbumGroup) {
        artist = group.artist ?? ""
        album = group.albumTitle ?? group.folderURL.lastPathComponent
    }
}
