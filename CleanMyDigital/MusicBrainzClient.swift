//
//  MusicBrainzClient.swift
//  CleanMyDigital
//

import Foundation

/// A single recording candidate returned by MusicBrainz' `/ws/2/recording`
/// search endpoint, flattened to its first associated release (if any).
struct MusicBrainzRecording: Identifiable, Sendable {
    let id: String
    let title: String
    let artistNames: String
    let releaseTitle: String?
    let releaseDate: String?
    let releaseID: String?

    /// The Cover Art Archive front image for this recording's first
    /// release, if it has one.
    var coverArtURL: URL? {
        guard let releaseID else { return nil }
        return URL(string: "https://coverartarchive.org/release/\(releaseID)/front-250")
    }

    var yearString: String? {
        guard let releaseDate else { return nil }
        let year = releaseDate.prefix(4)
        return (year.count == 4 && year.allSatisfy(\.isNumber)) ? String(year) : nil
    }

    /// Which of the file's missing fields this candidate has data for,
    /// based purely on search-result data. Excludes Artwork, which needs an
    /// extra network round-trip against the Cover Art Archive to confirm —
    /// callers with a way to check that should factor it in separately.
    /// Unlike Discogs, a recording already IS a track, so Title is
    /// fillable directly with no separate tracklist match needed.
    func fillableFields(missing: [MetadataField]) -> Set<MetadataField> {
        var fillable: Set<MetadataField> = []
        if missing.contains(.title), !title.isEmpty { fillable.insert(.title) }
        if missing.contains(.artist), !artistNames.isEmpty { fillable.insert(.artist) }
        if missing.contains(.album), let releaseTitle, !releaseTitle.isEmpty { fillable.insert(.album) }
        if missing.contains(.year), yearString != nil { fillable.insert(.year) }
        return fillable
    }
}

private struct MusicBrainzSearchResponse: Decodable {
    let recordings: [RawRecording]?
}

private struct RawRecording: Decodable {
    let id: String
    let title: String?
    let artistCredit: [RawArtistCredit]?
    let releases: [RawRelease]?

    enum CodingKeys: String, CodingKey {
        case id, title, releases
        case artistCredit = "artist-credit"
    }

    var mapped: MusicBrainzRecording {
        let firstRelease = releases?.first
        return MusicBrainzRecording(
            id: id,
            title: title ?? "",
            artistNames: (artistCredit ?? []).compactMap(\.name).joined(separator: ", "),
            releaseTitle: firstRelease?.title,
            releaseDate: firstRelease?.date,
            releaseID: firstRelease?.id
        )
    }
}

private struct RawArtistCredit: Decodable {
    let name: String?
}

private struct RawRelease: Decodable {
    let id: String?
    let title: String?
    let date: String?
}

enum MusicBrainzError: LocalizedError {
    case missingContact
    case rateLimited
    case http(Int)
    case invalidResponse
    case underlying(Error)

    var errorDescription: String? {
        switch self {
        case .missingContact:
            return "Add a contact email in Settings — MusicBrainz requires one in the User-Agent header."
        case .rateLimited:
            return "MusicBrainz rate limit reached (max 1 request/second). Wait a moment and try again."
        case .http(let code):
            return "MusicBrainz returned an unexpected error (HTTP \(code))."
        case .invalidResponse:
            return "MusicBrainz returned a response CleanMyDigital couldn't read."
        case .underlying(let error):
            return error.localizedDescription
        }
    }
}

/// Serializes MusicBrainz requests to at most one per second, as required
/// by their API etiquette (unauthenticated clients get no higher quota).
private actor MusicBrainzRateLimiter {
    static let shared = MusicBrainzRateLimiter()

    private let minimumInterval: TimeInterval = 1.0
    private var lastRequestDate: Date?

    func waitIfNeeded() async {
        if let lastRequestDate {
            let elapsed = Date().timeIntervalSince(lastRequestDate)
            if elapsed < minimumInterval {
                let remaining = minimumInterval - elapsed
                try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            }
        }
        lastRequestDate = Date()
    }
}

/// A minimal client for MusicBrainz' public `/ws/2/recording` search
/// endpoint. No API key is required, but every request must carry a
/// descriptive User-Agent with contact info and be rate-limited to 1/second.
enum MusicBrainzClient {
    /// Searches with the given recording title; if that comes back with
    /// zero results, retries once with a trailing "(Mix)"-style
    /// parenthetical stripped. A thrown error propagates immediately
    /// without retrying.
    static func searchRecordings(
        artist: String, recording: String, contactEmail: String
    ) async throws -> [MusicBrainzRecording] {
        guard !contactEmail.isEmpty else { throw MusicBrainzError.missingContact }

        let results = try await performSearch(artist: artist, recording: recording, contactEmail: contactEmail)
        if !results.isEmpty { return results }

        guard let fallbackRecording = MetadataQuery.strippingTrailingParenthetical(from: recording) else {
            return results
        }
        return try await performSearch(artist: artist, recording: fallbackRecording, contactEmail: contactEmail)
    }

    private static func performSearch(
        artist: String, recording: String, contactEmail: String
    ) async throws -> [MusicBrainzRecording] {
        var queryParts: [String] = []
        if !artist.isEmpty { queryParts.append("artist:\"\(escape(artist))\"") }
        if !recording.isEmpty { queryParts.append("recording:\"\(escape(recording))\"") }
        guard !queryParts.isEmpty else { throw MusicBrainzError.invalidResponse }

        var components = URLComponents(string: "https://musicbrainz.org/ws/2/recording")!
        components.queryItems = [
            URLQueryItem(name: "query", value: queryParts.joined(separator: " AND ")),
            URLQueryItem(name: "fmt", value: "json"),
            URLQueryItem(name: "limit", value: "10"),
        ]
        guard let url = components.url else { throw MusicBrainzError.invalidResponse }

        var request = URLRequest(url: url)
        request.setValue(userAgent(contactEmail: contactEmail), forHTTPHeaderField: "User-Agent")

        await MusicBrainzRateLimiter.shared.waitIfNeeded()

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw MusicBrainzError.underlying(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MusicBrainzError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200..<300:
            break
        case 429, 503:
            throw MusicBrainzError.rateLimited
        default:
            throw MusicBrainzError.http(httpResponse.statusCode)
        }

        do {
            let decoded = try JSONDecoder().decode(MusicBrainzSearchResponse.self, from: data)
            return (decoded.recordings ?? []).map(\.mapped)
        } catch {
            throw MusicBrainzError.underlying(error)
        }
    }

    /// MusicBrainz etiquette requires a descriptive User-Agent that
    /// identifies the application, version, and a way to contact its author.
    private static func userAgent(contactEmail: String) -> String {
        "CleanMyDigital/1.0 (\(contactEmail))"
    }

    /// Escapes Lucene special characters MusicBrainz's search syntax cares
    /// about within a quoted phrase.
    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

/// Derives MusicBrainz search terms from a scanned file, using the same
/// cleaned filename Discogs searches use.
struct MusicBrainzQuery {
    let artist: String
    let recording: String

    init(for file: AudioFile) {
        artist = MetadataQuery.artist(for: file)
        recording = MetadataQuery.cleanedTrackTitle(from: file.fileName, artist: artist, category: file.category)
    }
}
