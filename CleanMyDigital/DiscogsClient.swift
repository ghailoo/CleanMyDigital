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
    func autoMatchedTrack(for cleanedFileName: String) -> DiscogsTrack? {
        let normalizedFile = Self.normalize(cleanedFileName)
        guard !normalizedFile.isEmpty else { return nil }
        return tracks.first { track in
            let normalizedTrack = Self.normalize(track.title)
            guard !normalizedTrack.isEmpty else { return false }
            return normalizedTrack.contains(normalizedFile) || normalizedFile.contains(normalizedTrack)
        }
    }

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

/// Caches release details in memory for the app's lifetime so revisiting a
/// candidate — or another file from the same release — doesn't re-spend
/// Discogs' 60 requests/minute rate limit.
private actor DiscogsReleaseDetailCache {
    static let shared = DiscogsReleaseDetailCache()

    private var storage: [Int: DiscogsReleaseDetail] = [:]

    func cached(_ id: Int) -> DiscogsReleaseDetail? { storage[id] }

    func store(_ detail: DiscogsReleaseDetail, for id: Int) { storage[id] = detail }
}

/// A minimal client for Discogs' public `/database/search` and
/// `/releases/{id}` endpoints.
enum DiscogsClient {
    private static let userAgent = "CleanMyDigital/1.0 +personal use"

    static func search(artist: String, track: String, token: String) async throws -> [DiscogsRelease] {
        guard !token.isEmpty else { throw DiscogsError.missingToken }

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
        } else {
            queryItems.append(URLQueryItem(name: "q", value: track))
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

    init(for file: AudioFile) {
        artist = MetadataQuery.artist(for: file)
        track = MetadataQuery.cleanedTrackTitle(from: file.fileName)
    }
}
